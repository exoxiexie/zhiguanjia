"""后台操作审计查询接口

日志由中间件自动写入（见 audit.py），这里只负责查询与筛选。
"""

import datetime

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..deps import get_db
from ..models import AuditLog, User
from .audit import KEEP
from .deps import require_admin

router = APIRouter(tags=["admin-audit"])

_CST = datetime.timedelta(hours=8)


@router.get("/admin/audit")
def list_logs(
    limit: int = 100,
    before: int = 0,
    action: str = "",
    actor: str = "",
    only_failed: bool = False,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
) -> dict:
    """操作日志（按时间倒序；支持按动作/操作者/只看失败筛选）"""
    limit = max(1, min(limit, 500))
    stmt = select(AuditLog)
    count_stmt = select(func.count()).select_from(AuditLog)
    if before:
        stmt = stmt.where(AuditLog.id < before)
        count_stmt = count_stmt.where(AuditLog.id < before)
    if action:
        stmt = stmt.where(AuditLog.action == action)
        count_stmt = count_stmt.where(AuditLog.action == action)
    if actor:
        stmt = stmt.where(AuditLog.actor == actor)
        count_stmt = count_stmt.where(AuditLog.actor == actor)
    if only_failed:
        stmt = stmt.where(AuditLog.ok == 0)
        count_stmt = count_stmt.where(AuditLog.ok == 0)

    rows = db.scalars(stmt.order_by(AuditLog.id.desc()).limit(limit)).all()
    total = int(db.scalar(count_stmt) or 0)

    # 可选的动作清单（供前端筛选下拉）
    actions = [
        r[0]
        for r in db.execute(
            select(AuditLog.action).group_by(AuditLog.action).order_by(AuditLog.action)
        ).all()
    ]

    return {
        "items": [
            {
                "id": r.id,
                "actor": r.actor or "",
                "action": r.action or "",
                "method": r.method or "",
                "target": r.target or "",
                "status": r.status,
                "ok": bool(r.ok),
                "ip": r.ip or "",
                "duration_ms": r.duration_ms,
                "created_at": (r.created_at + _CST).isoformat(sep=" ", timespec="seconds")
                if r.created_at
                else "",
            }
            for r in rows
        ],
        "total": total,
        "keep": KEEP,
        "actions": actions,
    }
