"""后台「版本发布」

分工说明（重要）：
- **编译**必须在本地（Flutter + Android SDK，服务器 2G 内存跑不了）
- **分发侧的一切**都在这里：上传 APK → 校验 → 写 version.json（App 更新源）
  → 铺到官网下载页 → 重建发布官网 → 可选开启强制更新 → 留发布历史

因此运营可以自己决定"什么时候发、更新说明写什么、要不要强制"，
不需要开发者去改代码常量或手工传文件。

安全约束：
- 只有管理员可用；只接受 `.apk`
- 版本号必须**大于**当前线上版本（防误上传旧包把用户降级）
- 上传后先落为草稿，**点「发布」才生效**（可先上传、择机发布）
"""

import datetime
import hashlib
import json
import os
import shutil

from fastapi import APIRouter, Depends, File, Form, Request, UploadFile
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..deps import get_db
from ..errors import api_error
from ..models import AppConfig, AppRelease, User, new_uuid, utcnow
from .deps import require_admin
from .publisher import SITE_DIR, rebuild_and_deploy

router = APIRouter(tags=["admin-release"])

_CST = datetime.timedelta(hours=8)
# 安装包存放：站点源码的 static 目录（build.py 会把它铺到官网下载页）
APK_DIR = os.path.join(SITE_DIR, "static")
VERSION_JSON = os.path.join(SITE_DIR, "version.json")
MAX_APK = 200 * 1024 * 1024  # 200MB 上限


def _current_version() -> dict:
    try:
        with open(VERSION_JSON, encoding="utf-8") as f:
            return json.load(f)
    except Exception:  # noqa: BLE001
        return {}


def _write_version(name: str, code: int, url: str, changelog: str) -> None:
    data = {
        "versionName": name,
        "versionCode": code,
        "url": url,
        "changelog": changelog,
    }
    with open(VERSION_JSON, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")


def _serialize(r: AppRelease) -> dict:
    return {
        "id": r.id,
        "version_name": r.version_name,
        "version_code": r.version_code,
        "file_name": r.file_name,
        "size": r.size,
        "sha256": r.sha256,
        "changelog": r.changelog,
        "force_update": bool(r.force_update),
        "status": r.status,
        "created_by": r.created_by,
        "created_at": (r.created_at + _CST).isoformat(sep=" ", timespec="seconds")
        if r.created_at
        else "",
        "published_at": (r.published_at + _CST).isoformat(sep=" ", timespec="seconds")
        if r.published_at
        else "",
    }


def _apk_url(version_name: str) -> str:
    """下载地址：**用我们自己的站点**（不依赖第三方，Gitee 挂了也不影响用户更新）"""
    from ..config import settings

    base = os.environ.get("ZGJ_SITE_URL", "") or ""
    if not base:
        # 默认用官网（备案前后分别为 IP / 域名，可用 ZGJ_SITE_URL 覆盖）
        base = "http://8.137.71.241"
    return "%s/zhiguanjia/zhiguanjia-v%s.apk" % (base.rstrip("/"), version_name)


@router.get("/admin/release")
def list_releases(
    user: User = Depends(require_admin), db: Session = Depends(get_db)
) -> dict:
    """发布列表 + 当前线上版本"""
    rows = db.scalars(
        select(AppRelease).order_by(AppRelease.version_code.desc())
    ).all()
    cur = _current_version()
    return {
        "items": [_serialize(r) for r in rows],
        "current": {
            "version_name": cur.get("versionName", ""),
            "version_code": cur.get("versionCode", 0),
            "url": cur.get("url", ""),
            "changelog": cur.get("changelog", ""),
        },
        "apk_dir": APK_DIR,
    }


@router.post("/admin/release")
async def upload_release(
    request: Request,
    file: UploadFile = File(...),
    version_name: str = Form(...),
    version_code: int = Form(...),
    changelog: str = Form(""),
    force_update: bool = Form(False),
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
) -> dict:
    """上传安装包（落为草稿，稍后点「发布」才生效）"""
    name = (version_name or "").strip().lstrip("v")
    if not name:
        raise api_error(400, "bad_version", "版本名不能为空")
    if version_code <= 0:
        raise api_error(400, "bad_code", "版本号（versionCode）必须是正整数")

    filename = (file.filename or "").strip()
    if not filename.lower().endswith(".apk"):
        raise api_error(400, "bad_file", "只接受 .apk 安装包")

    cur = _current_version()
    cur_code = int(cur.get("versionCode", 0) or 0)
    if version_code <= cur_code:
        raise api_error(
            400,
            "version_too_old",
            f"版本号必须大于当前线上版本（{cur.get('versionName', '-')} / {cur_code}），"
            "否则会造成用户降级",
        )

    os.makedirs(APK_DIR, exist_ok=True)
    target_name = f"zhiguanjia-v{name}.apk"
    target = os.path.join(APK_DIR, target_name)
    digest = hashlib.sha256()
    size = 0
    try:
        with open(target, "wb") as out:
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break
                size += len(chunk)
                if size > MAX_APK:
                    out.close()
                    os.remove(target)
                    raise api_error(400, "too_large", "安装包超过 200MB")
                digest.update(chunk)
                out.write(chunk)
    except api_error:
        raise
    except Exception as exc:  # noqa: BLE001
        raise api_error(500, "save_failed", f"保存安装包失败：{exc}")
    finally:
        await file.close()

    if size < 1024:
        os.remove(target)
        raise api_error(400, "empty_file", "安装包为空或过小，请确认文件是否正确")

    row = AppRelease(
        id=new_uuid(),
        version_name=name,
        version_code=version_code,
        file_name=target_name,
        size=size,
        sha256=digest.hexdigest(),
        changelog=(changelog or "").strip(),
        force_update=1 if force_update else 0,
        status="draft",
        created_by=(user.phone or "")[:32],
        created_at=utcnow(),
    )
    db.add(row)
    request.state.audit_target = f"上传安装包 v{name}（{size / 1048576:.1f} MB）"
    db.commit()
    return {"ok": True, "release": _serialize(row)}


@router.post("/admin/release/{release_id}/publish")
def publish_release(
    release_id: str,
    request: Request,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
) -> dict:
    """发布：写更新源 → 铺官网下载页 → 重建发布 → 可选强制更新"""
    row = db.get(AppRelease, release_id)
    if row is None:
        raise api_error(404, "not_found", "发布记录不存在")
    apk = os.path.join(APK_DIR, row.file_name)
    if not os.path.exists(apk):
        raise api_error(400, "apk_missing", "安装包文件不存在，请重新上传")

    request.state.audit_target = f"发布版本 v{row.version_name}"

    # ① 更新源（App 检查更新读它；同时官网构建也以它为准）
    _write_version(row.version_name, row.version_code, _apk_url(row.version_name),
                   row.changelog)

    # ② 可选：开启强制更新（低于本版本必须升级）
    if row.force_update:
        cfg = db.get(AppConfig, 1)
        if cfg is None:
            cfg = AppConfig(id=1)
            db.add(cfg)
        cfg.min_version_code = row.version_code
        cfg.min_version_name = row.version_name
        cfg.update_url = _apk_url(row.version_name)
        cfg.update_note = row.changelog[:2000]
        cfg.updated_by = (user.phone or "")[:32]
        cfg.updated_at = utcnow()
        db.add(cfg)

    # ③ 重建并发布官网（下载页/首页版本号随之更新）
    result = rebuild_and_deploy()
    if not result["ok"]:
        if result.get("busy"):
            raise api_error(409, "busy", result["message"])
        raise api_error(500, "publish_failed", result["message"])

    # ④ 归档旧版本
    db.query(AppRelease).filter(
        AppRelease.id != row.id, AppRelease.status == "published"
    ).update({"status": "archived"}, synchronize_session=False)
    row.status = "published"
    row.published_at = utcnow()
    db.add(row)
    db.commit()
    return {
        "ok": True,
        "message": result["message"],
        "release": _serialize(row),
        "force_update": bool(row.force_update),
        "url": _apk_url(row.version_name),
    }


@router.delete("/admin/release/{release_id}")
def delete_release(
    release_id: str,
    request: Request,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
) -> dict:
    """删除发布记录（已发布的版本会连同安装包一起删掉）"""
    row = db.get(AppRelease, release_id)
    if row is None:
        raise api_error(404, "not_found", "发布记录不存在")
    request.state.audit_target = f"版本 v{row.version_name}"
    apk = os.path.join(APK_DIR, row.file_name)
    if os.path.exists(apk):
        os.remove(apk)
    db.delete(row)
    db.commit()
    return {"ok": True}
