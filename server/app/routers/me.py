"""当前用户相关接口

GET /me  当前登录用户资料（P2 会在此扩展：修改资料、实名认证、头像上传等）
"""

from fastapi import APIRouter, Depends

from ..deps import get_current_user
from ..models import User

router = APIRouter(tags=["me"])


@router.get("/me")
def me(user: User = Depends(get_current_user)) -> dict:
    """返回当前登录用户资料（不含密码哈希等敏感字段）"""
    return user.to_public()
