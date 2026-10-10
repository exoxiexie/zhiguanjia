"""备份与恢复服务（API 与定时脚本共用同一条实现）

备份内容（一个 tar.gz 里打包四部分 + 清单）：
- `db.sql.gz`          数据库（MySQL 用 mysqldump；SQLite 直接复制文件）
- `site-content.tar.gz` 文章正文（后台发布的内容，丢失无法重建）
- `uploads.tar.gz`      用户上传的图片等（丢失无法重建）
- `etc.tar.gz`          服务端配置与密钥（恢复整套系统必需）
- `MANIFEST.json`       备份时间 / 版本 / 各部分大小

**为什么这些**：站点页面可以由站点源码重新构建，但上面四项是"丢了就没了"的数据。

安全与可靠性约定：
1. 备份目录在**站点根目录与 uploads 之外**（否则备份文件会被公网下载）
2. 恢复前**自动先做一次备份**（恢复错了还能再恢复回来）
3. 恢复必须显式确认；只接受严格文件名的备份（防路径穿越）
4. 只保留最近 KEEP 份，避免小磁盘被撑满
"""

import datetime
import gzip
import json
import os
import re
import shutil
import subprocess
import tarfile
import tempfile

from ..config import settings
from ..db import engine
from ..version import APP_VERSION

BACKUP_DIR = settings.backup_dir
SITE_DIR = settings.site_dir
UPLOAD_DIR = settings.upload_dir
SECRETS_FILE = os.environ.get("ZGJ_SECRETS_FILE", "/etc/zhiguanjia-api-secrets.json")
ENV_FILE = "/etc/zhiguanjia-api.env"
KEEP = settings.backup_keep

_CST = datetime.timedelta(hours=8)
_NAME_RE = re.compile(r"^[0-9]{8}-[0-9]{6}(-[a-z0-9-]{1,20})?$")
PARTS = ("db", "content", "uploads", "etc")


def _now_cst() -> datetime.datetime:
    return datetime.datetime.utcnow() + _CST


def _is_sqlite() -> bool:
    return engine.url.drivername.startswith("sqlite")


def _dump_db(dest_dir: str) -> str:
    """把数据库导出到 dest_dir/db.sql.gz；返回文件名"""
    out = os.path.join(dest_dir, "db.sql.gz")
    if _is_sqlite():
        # 测试/本地：SQLite 直接复制文件内容
        src = str(engine.url.database or "")
        raw = open(src, "rb").read() if src and os.path.exists(src) else b""
    else:
        # 凭据统一从 settings 取（它合并了环境变量与 /etc 下的密钥 JSON，
        # 环境变量里可能根本没有密码）
        env = dict(os.environ)
        env["MYSQL_PWD"] = settings.db_password or ""
        host, port = settings.db_host, settings.db_port
        user, name = settings.db_user, settings.db_name
        if not (user and name and settings.db_password):
            raise RuntimeError("数据库账号配置不完整，无法备份")
        proc = subprocess.run(
            ["mysqldump", "--single-transaction", "--quick", "--no-tablespaces",
             "--default-character-set=utf8mb4", "-h", host, "-P", str(port), "-u", user, name],
            capture_output=True, env=env, timeout=300,
        )
        if proc.returncode != 0:
            raise RuntimeError("mysqldump 失败：" + proc.stderr.decode("utf-8", "ignore")[-300:])
        raw = proc.stdout
    with gzip.open(out, "wb") as f:
        f.write(raw)
    return "db.sql.gz"


def _tar_dir(src: str, out: str, arcname: str) -> None:
    """把目录打包成 tar.gz（目录不存在时不报错，仅生成空包）"""
    with tarfile.open(out, "w:gz") as tar:
        if os.path.isdir(src):
            tar.add(src, arcname=arcname)


def _tar_files(files, out: str) -> list:
    """把若干文件打包；**读不到的文件跳过并返回**（备份不该因一个文件而整体失败）

    典型情况：`/etc/zhiguanjia-api.env` 是 root 属主，而以 www 运行时读不到 ——
    此时宁可少备一个文件，也要把数据库与内容备下来。
    """
    skipped = []
    with tarfile.open(out, "w:gz") as tar:
        for path in files:
            if not os.path.exists(path):
                continue
            try:
                tar.add(path, arcname=os.path.basename(path))
            except (PermissionError, OSError):
                skipped.append(os.path.basename(path))
    return skipped


def create_backup(label: str = "") -> dict:
    """创建一次备份，返回记录"""
    os.makedirs(BACKUP_DIR, exist_ok=True)
    try:
        os.chmod(BACKUP_DIR, 0o700)  # 备份里含配置密钥，仅属主可读
    except OSError:
        pass

    stamp = _now_cst().strftime("%Y%m%d-%H%M%S")
    name = f"{stamp}-{label}" if label else stamp
    if not _NAME_RE.match(name):
        name = stamp

    work = tempfile.mkdtemp(prefix="zgj-backup-")
    parts: dict = {}
    try:
        parts["db"] = _dump_db(work)
        _tar_dir(os.path.join(SITE_DIR, "content"),
                 os.path.join(work, "site-content.tar.gz"), "content")
        parts["content"] = "site-content.tar.gz"
        _tar_dir(UPLOAD_DIR, os.path.join(work, "uploads.tar.gz"), "uploads")
        parts["uploads"] = "uploads.tar.gz"
        skipped = _tar_files([SECRETS_FILE, ENV_FILE], os.path.join(work, "etc.tar.gz"))
        parts["etc"] = "etc.tar.gz"

        manifest = {
            "name": name,
            "created_at": _now_cst().isoformat(timespec="seconds"),
            "api_version": APP_VERSION,
            "site_dir": SITE_DIR,
            "upload_dir": UPLOAD_DIR,
            "sizes": {
                f: os.path.getsize(os.path.join(work, f))
                for f in os.listdir(work) if f.endswith(".gz")
            },
            # 读不到而跳过的文件（如 root 属主的 env）：如实记录，不假装备全了
            "skipped": skipped,
        }
        with open(os.path.join(work, "MANIFEST.json"), "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)

        target = os.path.join(BACKUP_DIR, f"{name}.tar.gz")
        with tarfile.open(target, "w:gz") as tar:
            for f in sorted(os.listdir(work)):
                tar.add(os.path.join(work, f), arcname=f)
        os.chmod(target, 0o600)
        _chown_to_web_user(target)
    finally:
        shutil.rmtree(work, ignore_errors=True)

    prune()
    return {"name": name, "size": os.path.getsize(target),
            "path": target, "created_at": manifest["created_at"]}


def _chown_to_web_user(path: str) -> None:
    """把备份归属改为网站运行用户。

    定时任务以 root 跑（这样才读得到 /etc 下的配置），但后台以 www 运行、
    需要能列出/删除/恢复这些备份 —— 因此生成后统一切换归属。
    """
    if os.geteuid() != 0:
        return
    try:
        import pwd

        ent = pwd.getpwnam(os.environ.get("ZGJ_WEB_USER", "www"))
        os.chown(path, ent.pw_uid, ent.pw_gid)
        os.chown(BACKUP_DIR, ent.pw_uid, ent.pw_gid)
    except Exception:  # noqa: BLE001
        pass


def _read_manifest(path: str) -> dict:
    try:
        with tarfile.open(path, "r:gz") as tar:
            f = tar.extractfile("MANIFEST.json")
            return json.loads(f.read().decode("utf-8")) if f else {}
    except Exception:  # noqa: BLE001
        return {}


def list_backups() -> list:
    if not os.path.isdir(BACKUP_DIR):
        return []
    items = []
    for fn in os.listdir(BACKUP_DIR):
        if not fn.endswith(".tar.gz"):
            continue
        full = os.path.join(BACKUP_DIR, fn)
        name = fn[:-7]
        man = _read_manifest(full)
        items.append({
            "name": name,
            "size": os.path.getsize(full),
            "created_at": man.get("created_at", ""),
            "api_version": man.get("api_version", ""),
            "parts": sorted((man.get("sizes") or {}).keys()),
        })
    items.sort(key=lambda x: x["name"], reverse=True)
    return items


def delete_backup(name: str) -> bool:
    if not _NAME_RE.match(name):
        return False
    path = os.path.join(BACKUP_DIR, f"{name}.tar.gz")
    if os.path.exists(path):
        os.remove(path)
        return True
    return False


def prune(keep: int = None) -> int:
    """只保留最近 N 份"""
    keep = KEEP if keep is None else keep
    items = list_backups()
    removed = 0
    for old in items[keep:]:
        if delete_backup(old["name"]):
            removed += 1
    return removed


def disk_info() -> dict:
    try:
        st = os.statvfs(BACKUP_DIR if os.path.isdir(BACKUP_DIR) else "/")
        total = st.f_blocks * st.f_frsize
        free = st.f_bavail * st.f_frsize
        return {"total": total, "free": free, "used": total - free}
    except Exception:  # noqa: BLE001
        return {"total": 0, "free": 0, "used": 0}


def restore_backup(name: str, parts=None) -> dict:
    """恢复备份（**恢复前自动先备份一次**）

    parts: 可指定只恢复其中几项（db/content/uploads/etc），默认全部
    """
    if not _NAME_RE.match(name):
        raise RuntimeError("备份名不合法")
    path = os.path.join(BACKUP_DIR, f"{name}.tar.gz")
    if not os.path.exists(path):
        raise RuntimeError("备份不存在")

    wanted = [p for p in (parts or PARTS) if p in PARTS]
    if not wanted:
        raise RuntimeError("未指定要恢复的内容")

    # ① 先把"现在"备份下来 —— 恢复错了还能再恢复回来
    safety = create_backup(label="prerestore")

    work = tempfile.mkdtemp(prefix="zgj-restore-")
    done = []
    try:
        with tarfile.open(path, "r:gz") as tar:
            tar.extractall(work)

        if "content" in wanted and os.path.exists(os.path.join(work, "site-content.tar.gz")):
            # 先清空再解包：否则"已删除的文章"会残留，恢复不彻底
            dst = os.path.join(SITE_DIR, "content")
            shutil.rmtree(dst, ignore_errors=True)
            os.makedirs(dst, exist_ok=True)
            with tarfile.open(os.path.join(work, "site-content.tar.gz")) as tar:
                tar.extractall(SITE_DIR)
            done.append("content")

        if "uploads" in wanted and os.path.exists(os.path.join(work, "uploads.tar.gz")):
            staging = os.path.join(work, "uploads-stage")
            os.makedirs(staging, exist_ok=True)
            with tarfile.open(os.path.join(work, "uploads.tar.gz")) as tar:
                tar.extractall(staging)
            src = os.path.join(staging, "uploads")
            if os.path.isdir(src):
                shutil.rmtree(UPLOAD_DIR, ignore_errors=True)
                shutil.move(src, UPLOAD_DIR)
                done.append("uploads")

        if "etc" in wanted and os.path.exists(os.path.join(work, "etc.tar.gz")):
            with tarfile.open(os.path.join(work, "etc.tar.gz")) as tar:
                tar.extractall("/")
            done.append("etc")

        if "db" in wanted and os.path.exists(os.path.join(work, "db.sql.gz")):
            if _is_sqlite():
                src = str(engine.url.database or "")
                if src:
                    with gzip.open(os.path.join(work, "db.sql.gz"), "rb") as f:
                        raw = f.read()
                    with open(src, "wb") as f:
                        f.write(raw)
                    done.append("db")
            else:
                env = dict(os.environ)
                env["MYSQL_PWD"] = settings.db_password or ""
                host, port = settings.db_host, settings.db_port
                user, dbname = settings.db_user, settings.db_name
                proc = subprocess.run(
                    ["mysql", "-h", host, "-P", str(port), "-u", user, dbname],
                    input=gzip.open(os.path.join(work, "db.sql.gz"), "rb").read(),
                    capture_output=True, env=env, timeout=600,
                )
                if proc.returncode != 0:
                    raise RuntimeError("数据库恢复失败：" + proc.stderr.decode("utf-8", "ignore")[-300:])
                done.append("db")
    finally:
        shutil.rmtree(work, ignore_errors=True)

    return {"restored": done, "safety_backup": safety["name"]}
