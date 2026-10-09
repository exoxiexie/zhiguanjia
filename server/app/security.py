"""密码与令牌：bcrypt 哈希 + JWT。

密码处理说明：bcrypt 只取前 72 字节，中文密码很容易超（一个汉字 3 字节），
因此**先做 SHA-256 再 base64**（固定 44 字节）再交给 bcrypt，
这样任意长度/任意语言的密码都能安全处理，且不损失强度。
"""

import base64
import datetime
import hashlib
import secrets

import bcrypt
import jwt

from .config import settings

_BCRYPT_ROUNDS = 10  # 2 核机器上约 100ms，安全与性能的平衡点


def _prehash(password: str) -> bytes:
    return base64.b64encode(hashlib.sha256(password.encode("utf-8")).digest())


def hash_password(password: str) -> str:
    return bcrypt.hashpw(_prehash(password), bcrypt.gensalt(rounds=_BCRYPT_ROUNDS)).decode()


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(_prehash(password), password_hash.encode())
    except Exception:  # noqa: BLE001
        return False


def create_access_token(user_id: str) -> tuple[str, int]:
    """签发 access token，返回 (token, 有效期秒数)"""
    now = datetime.datetime.now(datetime.timezone.utc)
    exp = now + datetime.timedelta(minutes=settings.access_token_minutes)
    payload = {
        "sub": user_id,
        "type": "access",
        "iat": int(now.timestamp()),
        "exp": int(exp.timestamp()),
    }
    token = jwt.encode(payload, settings.jwt_secret, algorithm="HS256")
    return token, settings.access_token_minutes * 60


def decode_access_token(token: str) -> dict | None:
    """解析 access token；无效/过期返回 None（调用方转 401）"""
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
        return payload if isinstance(payload, dict) else None
    except Exception:  # noqa: BLE001
        return None


def new_refresh_token() -> str:
    """刷新令牌：随机不可猜（库中只存哈希）"""
    return secrets.token_urlsafe(32)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()
