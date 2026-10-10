"""后台「用户管理」

面向客服与风控：检索用户、看详情（实名/设备/内容量）、停用与恢复、管理员开关、重置密码。

安全护栏（避免把自己锁在门外）：
- 不能停用自己、不能取消自己的管理员
- 停用必须填原因（写进日志与登录提示）
- 停用/重置密码都会**吊销该用户所有令牌**（立即踢下线）
- 所有写操作自动进入操作审计
"""

import secrets

from fastapi import APIRouter, Depends, Request
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from ..deps import get_db
from ..errors import api_error
from ..models import (
    AuthToken,
    Conversation,
    Device,
    Message,
    User,
    utcnow,
)
from ..schemas import UserAdminIn, UserStatusIn
from ..security import hash_password
from .deps import require_admin

router = APIRouter(tags=["admin-users"])


def _counts(db: Session, uid: str) -> dict:
    def n(model, *conds) -> int:
        stmt = select(func.count()).select_from(model).where(model.user_id == uid)
        for c in conds:
            stmt = stmt.where(c)
        return int(db.scalar(stmt) or 0)

    device_rows = db.execute(
        select(Device).where(Device.user_id == uid).order_by(Device.last_seen_at.desc())
    ).scalars().all()
    last_seen = device_rows[0].last_seen_at if device_rows else None
    return {
        "devices": len(device_rows),
        "conversations": n(Conversation),
        "messages": n(Message),
        "messages_today": n(Message, Message.created_at >= _today_ms()),
        "last_seen_at": last_seen.isoformat() if last_seen else "",
        "device_list": [
            {
                "device_id": d.device_id,
                "platform": d.platform or "",
                "brand": d.brand or "",
                "model": d.model or "",
                "app_version": d.app_version or "",
                "version_code": d.version_code or 0,
                "first_seen_at": d.first_seen_at.isoformat() if d.first_seen_at else "",
                "last_seen_at": d.last_seen_at.isoformat() if d.last_seen_at else "",
            }
            for d in device_rows[:10]
        ],
    }


def _today_ms() -> int:
    import datetime

    now = datetime.datetime.utcnow() + datetime.timedelta(hours=8)
    start = datetime.datetime(now.year, now.month, now.day) - datetime.timedelta(hours=8)
    return int(start.replace(tzinfo=datetime.timezone.utc).timestamp() * 1000)


def _serialize(db: Session, u: User, with_counts: bool = False) -> dict:
    out = {
        "id": u.id,
        "phone": u.phone or "",
        "name": u.name or "",
        "is_admin": bool(u.is_admin),
        "status": u.status,
        "banned_reason": getattr(u, "banned_reason", "") or "",
        "verified": bool(u.verified_at),
        "id_card_masked": u.id_card_masked or "",
        "created_at": u.created_at.isoformat() if u.created_at else "",
    }
    if with_counts:
        out.update(_counts(db, u.id))
    return out


@router.get("/admin/users")
def list_users(
    q: str = "",
    limit: int = 50,
    offset: int = 0,
    only_banned: bool = False,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
) -> dict:
    """用户列表（按手机号或姓名检索；带设备/内容量等概览）"""
    limit = max(1, min(limit, 200))
    stmt = select(User)
    count_stmt = select(func.count()).select_from(User)
    if q.strip():
        like = f"%{q.strip()}%"
        cond = or_(User.phone.like(like), User.name.like(like))
        stmt = stmt.where(cond)
        count_stmt = count_stmt.where(cond)
    if only_banned:
        stmt = stmt.where(User.status != 1)
        count_stmt = count_stmt.where(User.status != 1)

    rows = db.scalars(
        stmt.order_by(User.created_at.desc()).offset(max(0, offset)).limit(limit)
    ).all()
    return {
        "items": [_serialize(db, u, with_counts=True) for u in rows],
        "total": int(db.scalar(count_stmt) or 0),
    }


@router.get("/admin/users/{user_id}")
def get_user(
    user_id: str,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
) -> dict:
    """用户详情（含设备列表与内容量）"""
    row = db.get(User, user_id)
    if row is None:
        raise api_error(404, "not_found", "用户不存在")
    return _serialize(db, row, with_counts=True)


@router.post("/admin/users/{user_id}/status")
def set_status(
    user_id: str,
    body: UserStatusIn,
    request: Request,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
) -> dict:
    """停用 / 恢复账号（停用会立即吊销其所有令牌）"""
    row = db.get(User, user_id)
    if row is None:
        raise api_error(404, "not_found", "用户不存在")
    if row.id == user.id:
        raise api_error(400, "self_action", "不能停用自己的账号")

    want = 1 if body.status == 1 else 0
    if want == 0 and not (body.reason or "").strip():
        raise api_error(400, "reason_required", "停用账号必须填写原因")

    row.status = want
    row.banned_reason = (body.reason or "").strip()[:200] if want == 0 else ""
    if want == 0:
        # 立即踢下线：吊销所有未失效令牌
        db.query(AuthToken).filter(
            AuthToken.user_id == row.id, AuthToken.revoked_at.is_(None)
        ).update({"revoked_at": utcnow()}, synchronize_session=False)
    request.state.audit_target = (
        f"用户 {row.phone}（{row.name}）" + ("停用" if want == 0 else "恢复")
    )
    db.add(row)
    db.commit()
    return {"ok": True, "user": _serialize(db, row)}


@router.post("/admin/users/{user_id}/admin")
def set_admin(
    user_id: str,
    body: UserAdminIn,
    request: Request,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
) -> dict:
    """授予 / 取消管理员"""
    row = db.get(User, user_id)
    if row is None:
        raise api_error(404, "not_found", "用户不存在")
    if row.id == user.id and not body.is_admin:
        raise api_error(400, "self_action", "不能取消自己的管理员权限")

    row.is_admin = 1 if body.is_admin else 0
    request.state.audit_target = (
        f"用户 {row.phone}（{row.name}）"
        + ("设为管理员" if body.is_admin else "取消管理员")
    )
    db.add(row)
    db.commit()
    return {"ok": True, "user": _serialize(db, row)}


@router.post("/admin/users/{user_id}/reset-password")
def reset_password(
    user_id: str,
    request: Request,
    random_password: bool = False,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
) -> dict:
    """重置密码并踢下线所有设备

    现阶段默认重置为**统一密码**（`ZGJ_DEFAULT_RESET_PASSWORD`，默认 123456）：
    用户多为手机号登录、常忘记密码，统一密码便于客服口头告知，用户登录后再自行修改。
    需要更强安全时：把该项配置清空（改为随机），或调用时带 `random_password=true`。
    """
    row = db.get(User, user_id)
    if row is None:
        raise api_error(404, "not_found", "用户不存在")

    from ..config import settings

    fixed = (settings.default_reset_password or "").strip()
    temp = secrets.token_urlsafe(6)[:9] if (random_password or not fixed) else fixed
    row.password_hash = hash_password(temp)
    db.query(AuthToken).filter(
        AuthToken.user_id == row.id, AuthToken.revoked_at.is_(None)
    ).update({"revoked_at": utcnow()}, synchronize_session=False)
    request.state.audit_target = f"用户 {row.phone}（{row.name}）重置密码"
    db.add(row)
    db.commit()
    return {
        "ok": True,
        "phone": row.phone,
        "temp_password": temp,
        "random": bool(random_password or not fixed),
        "note": ("已重置为统一密码，可直接告知用户，登录后建议自行修改。"
                 if fixed and not random_password
                 else "该临时密码仅显示这一次，请通过安全渠道告知用户。"),
    }
