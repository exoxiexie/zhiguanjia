"""后台「备份与恢复」接口

备份是"救命绳"：内容被误删、被覆盖、库写坏时能回到某个时间点。
真正的实现在 `backup_service.py`（后台与定时脚本共用）。
"""

import datetime

from fastapi import APIRouter, Depends, Request

from ..errors import api_error
from ..models import User
from .backup_service import (
    BACKUP_DIR,
    KEEP,
    PARTS,
    create_backup,
    delete_backup,
    disk_info,
    list_backups,
    restore_backup,
)
from .deps import require_admin
from .publisher import rebuild_and_deploy

router = APIRouter(tags=["admin-backup"])

_CST = datetime.timedelta(hours=8)


@router.get("/admin/backup")
def list_all(user: User = Depends(require_admin)) -> dict:
    """备份列表 + 磁盘情况"""
    items = list_backups()
    auto = next((i for i in items if i["name"].endswith("-auto")), None)
    return {
        "items": items,
        "dir": BACKUP_DIR,
        "keep": KEEP,
        "parts": list(PARTS),
        "disk": disk_info(),
        "last_auto": auto,
        "server_time": (datetime.datetime.utcnow() + _CST).isoformat(timespec="seconds"),
    }


@router.post("/admin/backup")
def create(request: Request, user: User = Depends(require_admin)) -> dict:
    """立即备份一次"""
    try:
        rec = create_backup(label="manual")
    except Exception as exc:  # noqa: BLE001
        raise api_error(500, "backup_failed", f"备份失败：{exc}")
    request.state.audit_target = f"新建备份 {rec['name']}"
    return {"ok": True, "backup": rec}


@router.post("/admin/backup/{name}/restore")
def restore(
    name: str,
    request: Request,
    confirm: str = "",
    parts: str = "",
    user: User = Depends(require_admin),
) -> dict:
    """恢复备份（必须显式确认；恢复前会自动先备份一次当前状态）"""
    if confirm != "RESTORE":
        raise api_error(400, "confirm_required", "恢复会覆盖当前数据，需显式确认")
    request.state.audit_target = f"备份 {name}"
    wanted = [p.strip() for p in parts.split(",") if p.strip()] if parts else None
    try:
        result = restore_backup(name, wanted)
    except Exception as exc:  # noqa: BLE001
        raise api_error(500, "restore_failed", f"恢复失败：{exc}")
    # 文章内容恢复后必须重建站点，否则线上页面还是旧的
    if "content" in result.get("restored", []):
        result["rebuild"] = rebuild_and_deploy()
    return {"ok": True, **result}


@router.delete("/admin/backup/{name}")
def delete(name: str, request: Request, user: User = Depends(require_admin)) -> dict:
    request.state.audit_target = f"备份 {name}"
    if not delete_backup(name):
        raise api_error(404, "not_found", "备份不存在")
    return {"ok": True}
