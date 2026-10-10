"""后台「公告与配置」

管理服务端下发给 App 的配置（`app_config` 单行表），**不发版即可生效**：

- **公告**：开关 + 标题 + 正文；App 启动弹窗，同一条只弹一次（靠公告 ID 去重）
  —— 「重新弹一次」= 换一个公告 ID，用户会再次看到
- **强制更新**：最低支持版本；本机 versionCode 低于它会被拦在登录之前
  —— 是"紧急下线坏版本"的保命手段，因此界面必须解释清楚 + 二次确认
- **功能开关**：任意键值（含**测试入口灰度名单** `test_panel` / `test_panel_phones`）

配置写错影响面很大（可能把用户全拦在门外），因此：
1. 记录 `updated_by`（谁改的）；
2. 公告 ID 留空时自动生成，避免作者还要理解 ID 机制；
3. flags 必须是 JSON 对象且限制体积。
"""

import datetime
import json
import os
import secrets

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from ..deps import get_db
from ..errors import api_error
from ..models import AppConfig, User, utcnow
from ..schemas import ConfigIn
from .deps import require_admin
from .publisher import SITE_DIR

router = APIRouter(tags=["admin-config"])

DEFAULT_ID = 1
_CST = datetime.timedelta(hours=8)
_FLAGS_MAX = 8000


def _config_of(db: Session) -> AppConfig:
    row = db.get(AppConfig, DEFAULT_ID)
    if row is None:
        row = AppConfig(id=DEFAULT_ID)
        db.add(row)
        db.commit()
        db.refresh(row)
    return row


def _flags_of(row: AppConfig) -> dict:
    try:
        flags = json.loads(row.flags_json or "{}")
    except Exception:  # noqa: BLE001
        flags = {}
    return flags if isinstance(flags, dict) else {}


def _release_info() -> dict:
    """当前线上版本（读站点源码目录里的 version.json，供设置强制更新时参考）"""
    path = os.path.join(SITE_DIR, "version.json")
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return {
            "version_name": str(data.get("versionName", "")),
            "version_code": int(data.get("versionCode", 0) or 0),
            "url": str(data.get("url", "")),
            "changelog": str(data.get("changelog", "")),
        }
    except Exception:  # noqa: BLE001
        return {"version_name": "", "version_code": 0, "url": "", "changelog": ""}


def _serialize(row: AppConfig) -> dict:
    return {
        "announcement": {
            "enabled": bool(row.announcement_enabled),
            "id": row.announcement_id or "",
            "title": row.announcement_title or "",
            "body": row.announcement_body or "",
        },
        "min_version": {
            "version_code": row.min_version_code or 0,
            "version_name": row.min_version_name or "",
            "url": row.update_url or "",
            "note": row.update_note or "",
        },
        "flags": _flags_of(row),
        "updated_by": row.updated_by or "",
        "updated_at": (row.updated_at or utcnow()).isoformat(),
        "release": _release_info(),
    }


@router.get("/admin/config")
def get_config(
    user: User = Depends(require_admin), db: Session = Depends(get_db)
) -> dict:
    """当前下发配置 + 当前线上版本（供参考）"""
    return _serialize(_config_of(db))


@router.post("/admin/config")
def save_config(
    body: ConfigIn,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
) -> dict:
    """保存配置（只改传进来的块）；立即对客户端生效（App 下次启动即可读到）"""
    row = _config_of(db)

    if body.announcement is not None:
        a = body.announcement
        title = (a.title or "").strip()
        text = (a.body or "").strip()
        if a.enabled and not text:
            raise api_error(400, "empty_announcement", "公告已启用，但正文为空")
        aid = (a.id or "").strip()
        # 换 ID 才会"重新弹一次"；留空则沿用（首次自动生成），避免作者理解 ID 机制
        if body.reset_announcement_read or not aid:
            aid = secrets.token_hex(6)
        row.announcement_enabled = 1 if a.enabled else 0
        row.announcement_id = aid[:32]
        row.announcement_title = title[:120]
        row.announcement_body = text

    if body.min_version is not None:
        m = body.min_version
        row.min_version_code = int(m.version_code or 0)
        row.min_version_name = (m.version_name or "").strip()[:24]
        row.update_url = (m.url or "").strip()[:255]
        row.update_note = (m.note or "").strip()

    if body.flags is not None:
        if not isinstance(body.flags, dict):
            raise api_error(400, "bad_flags", "功能开关必须是 JSON 对象")
        text = json.dumps(body.flags, ensure_ascii=False)
        if len(text) > _FLAGS_MAX:
            raise api_error(400, "flags_too_large", f"功能开关过大（上限 {_FLAGS_MAX} 字符）")
        row.flags_json = text

    row.updated_by = (user.phone or "")[:32]
    row.updated_at = utcnow()
    db.add(row)
    db.commit()
    db.refresh(row)
    return {"ok": True, "config": _serialize(row)}
