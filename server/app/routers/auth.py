"""账号体系接口（P1）

POST /auth/register  注册
POST /auth/login     登录
POST /auth/refresh   刷新令牌（一次性轮换，防重放）
POST /auth/logout    退出（吊销本设备令牌，可选全部设备）
GET  /me             当前用户资料
"""

import datetime
import time

from fastapi import APIRouter, Depends, Request
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..config import settings
from ..deps import get_current_user, get_db
from ..errors import api_error
from ..models import AuthToken, User, new_uuid, utcnow
from ..schemas import LoginRequest, LogoutRequest, RefreshRequest, RegisterRequest
from ..security import (
    create_access_token,
    hash_password,
    hash_token,
    new_refresh_token,
    verify_password,
)

router = APIRouter(prefix="/auth", tags=["auth"])

# ── 简易内存限流（MVP；多 worker 下按进程计数，后续可换 Redis）──
_attempts: dict = {}


def _client_ip(request: Request) -> str:
    fwd = request.headers.get("x-forwarded-for", "")
    if fwd:
        return fwd.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def _rate_limit(key: str, limit: int, window_seconds: int) -> None:
    now = time.time()
    hits = [t for t in _attempts.get(key, []) if now - t < window_seconds]
    if len(hits) >= limit:
        raise api_error(429, "too_many_requests", "操作过于频繁，请稍后再试")
    hits.append(now)
    _attempts[key] = hits


def _issue_tokens(
    db: Session,
    user: User,
    device_id: str = "",
    device_name: str = "",
    platform: str = "android",
) -> dict:
    """签发 access + refresh 令牌（refresh 只存哈希）"""
    access_token, expires_in = create_access_token(user.id)
    refresh_token = new_refresh_token()
    db.add(
        AuthToken(
            id=new_uuid(),
            user_id=user.id,
            token_hash=hash_token(refresh_token),
            device_id=device_id or "",
            device_name=device_name or "",
            platform=platform or "android",
            expires_at=utcnow() + datetime.timedelta(days=settings.refresh_token_days),
        )
    )
    db.commit()
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "Bearer",
        "expires_in": expires_in,
    }


@router.post("/register", status_code=201)
def register(
    body: RegisterRequest, request: Request, db: Session = Depends(get_db)
) -> dict:
    _rate_limit("reg:" + _client_ip(request), limit=10, window_seconds=3600)

    if db.scalar(select(User).where(User.phone == body.phone)) is not None:
        raise api_error(409, "phone_taken", "该手机号已注册，请直接登录")

    user = User(
        id=new_uuid(),
        phone=body.phone,
        password_hash=hash_password(body.password),
        name=body.name,
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    tokens = _issue_tokens(db, user, body.device_id, body.device_name, body.platform)
    return {"user": user.to_public(), **tokens}


@router.post("/login")
def login(body: LoginRequest, request: Request, db: Session = Depends(get_db)) -> dict:
    # 同一手机号 + 同一 IP：5 分钟内最多 10 次，防爆破
    _rate_limit("login:%s:%s" % (_client_ip(request), body.phone), 10, 300)

    user = db.scalar(select(User).where(User.phone == body.phone.strip()))
    # 统一提示，不区分"账号不存在"与"密码错误"，避免被枚举
    if user is None or not verify_password(body.password, user.password_hash):
        raise api_error(401, "bad_credentials", "手机号或密码不正确")
    if user.status != 1:
        raise api_error(
            403,
            "user_disabled",
            "该账号已被停用"
            + (f"：{getattr(user, 'banned_reason', '')}" if getattr(user, "banned_reason", "") else ""),
        )

    tokens = _issue_tokens(db, user, body.device_id, body.device_name, body.platform)
    return {"user": user.to_public(), **tokens}


@router.post("/refresh")
def refresh(body: RefreshRequest, db: Session = Depends(get_db)) -> dict:
    row = db.scalar(
        select(AuthToken).where(AuthToken.token_hash == hash_token(body.refresh_token))
    )
    if row is None or not row.is_valid():
        raise api_error(401, "refresh_invalid", "登录已过期，请重新登录")
    user = db.get(User, row.user_id)
    if user is None or user.status != 1:
        raise api_error(401, "refresh_invalid", "登录已过期，请重新登录")

    # 一次性轮换：旧令牌立即作废，防止被重放
    row.revoked_at = utcnow()
    db.commit()

    tokens = _issue_tokens(db, user, row.device_id, row.device_name, row.platform)
    return {"user": user.to_public(), **tokens}


@router.post("/logout")
def logout(
    body: LogoutRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    now = utcnow()
    if body.all_devices:
        rows = db.scalars(
            select(AuthToken).where(
                AuthToken.user_id == user.id, AuthToken.revoked_at.is_(None)
            )
        ).all()
    elif body.refresh_token:
        rows = db.scalars(
            select(AuthToken).where(
                AuthToken.token_hash == hash_token(body.refresh_token),
                AuthToken.user_id == user.id,
            )
        ).all()
    else:
        rows = db.scalars(
            select(AuthToken).where(
                AuthToken.user_id == user.id, AuthToken.revoked_at.is_(None)
            )
        ).all()

    for row in rows:
        row.revoked_at = now
    db.commit()
    return {"ok": True, "revoked": len(rows)}
