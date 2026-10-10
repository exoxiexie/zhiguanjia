"""FastAPI 依赖：数据库会话 + 当前登录用户"""

from fastapi import Depends, Header
from sqlalchemy.orm import Session

from .db import SessionLocal
from .errors import api_error
from .models import User
from .security import decode_access_token


def get_db():
    """每个请求一个数据库会话，结束自动关闭"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def get_current_user(
    authorization: str = Header(default=""),
    db: Session = Depends(get_db),
) -> User:
    """从 Authorization: Bearer <access_token> 解析当前用户"""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise api_error(401, "unauthorized", "未登录或缺少令牌")
    token = authorization.split(" ", 1)[1].strip()
    payload = decode_access_token(token)
    if not payload or payload.get("type") != "access":
        raise api_error(401, "token_invalid", "登录已过期，请重新登录")
    user = db.get(User, payload.get("sub"))
    if user is None:
        raise api_error(401, "user_not_found", "账号不存在")
    if user.status != 1:
        reason = getattr(user, "banned_reason", "") or ""
        raise api_error(403, "user_disabled",
                        "该账号已被停用" + (f"：{reason}" if reason else ""))
    return user
