"""服务端下发配置（P5-b）

`GET /app/config` **无需登录**：公告与强制更新必须在**登录页也能生效**
（例如某个版本有严重缺陷，必须拦在登录之前）。

配置行懒创建（首次访问写入默认值），因此不需要初始化脚本。
"""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from ..deps import get_db
from ..models import AppConfig

router = APIRouter(tags=["config"])

DEFAULT_ID = 1


def _config_of(db: Session) -> AppConfig:
    row = db.get(AppConfig, DEFAULT_ID)
    if row is None:
        row = AppConfig(id=DEFAULT_ID)
        db.add(row)
        db.commit()
        db.refresh(row)
    return row


@router.get("/app/config")
def app_config(db: Session = Depends(get_db)) -> dict:
    """App 启动时读取：公告 / 强制更新 / 功能开关"""
    import json

    row = _config_of(db)
    try:
        flags = json.loads(row.flags_json or "{}")
    except Exception:  # noqa: BLE001
        flags = {}
    if not isinstance(flags, dict):
        flags = {}

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
        "flags": flags,
        "updated_at": row.updated_at.isoformat() if row.updated_at else "",
    }
