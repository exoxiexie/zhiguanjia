"""后台专属鉴权：**权限边界的唯一入口**。

所有 /admin/* 接口都必须经过它；新增后台模块时挂上 `Depends(require_admin)`
就不会漏校验（这也是把后台从业务路由里独立出来的主要收益之一）。
"""

from fastapi import Depends, Request

from ..deps import get_current_user
from ..errors import api_error
from ..models import User


def require_admin(
    request: Request, user: User = Depends(get_current_user)
) -> User:
    """非管理员一律 403

    顺带把操作者写进 request.state —— 审计中间件据此记录"谁做的"。
    """
    if not getattr(user, "is_admin", False):
        request.state.actor = getattr(user, "phone", "") or ""
        raise api_error(403, "forbidden", "该账号没有管理权限")
    request.state.actor = getattr(user, "phone", "") or ""
    return user
