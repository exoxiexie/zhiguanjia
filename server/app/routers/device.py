"""设备上报与运营统计（P5-a）

- `POST /device/report`：App 启动上报设备/版本/机型（幂等，同设备只更新最后活跃）
- `GET  /admin/stats`：装机量、活跃、版本分布、内容量（**仅管理员**）

为什么要单独一张 devices 表而不是只看登录记录：
登录令牌会过期、会被清理，而"装机量"要求**一台设备只算一次**；
按 (user_id, device_id) 唯一即可得到稳定的装机口径。
"""

import datetime

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..deps import get_current_user, get_db
from ..errors import api_error
from ..models import (
    Conversation,
    Device,
    Experience,
    Favorite,
    Memory,
    Message,
    BlogPost,
    User,
    new_uuid,
    utcnow,
)
from ..schemas import DeviceReportRequest

router = APIRouter(tags=["device"])


@router.post("/device/report")
def report_device(
    body: DeviceReportRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    """上报设备信息（幂等）"""
    row = db.scalar(
        select(Device).where(
            Device.user_id == user.id, Device.device_id == body.device_id
        )
    )
    is_new = row is None
    if row is None:
        row = Device(
            id=new_uuid(),
            user_id=user.id,
            device_id=body.device_id,
            first_seen_at=utcnow(),
        )
        db.add(row)

    row.platform = body.platform or row.platform or "android"
    row.brand = body.brand or row.brand or ""
    row.model = body.model or row.model or ""
    row.os_version = body.os_version or row.os_version or ""
    row.app_version = body.app_version or row.app_version or ""
    row.version_code = body.version_code or row.version_code or 0
    row.channel = body.channel or row.channel or ""
    row.last_seen_at = utcnow()
    db.commit()
    return {"ok": True, "is_new_device": is_new, "device": row.to_public()}


def _require_admin(user: User) -> None:
    if not user.is_admin:
        raise api_error(403, "forbidden", "无权访问运营数据")


@router.get("/admin/stats")
def admin_stats(
    days: int = 7,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    """运营统计：装机 / 活跃 / 版本分布 / 内容量"""
    _require_admin(user)
    days = max(1, min(days, 90))
    since = utcnow() - datetime.timedelta(days=days)
    day_ago = utcnow() - datetime.timedelta(days=1)

    def count(model, *conditions) -> int:
        stmt = select(func.count()).select_from(model)
        for c in conditions:
            stmt = stmt.where(c)
        return int(db.scalar(stmt) or 0)

    total_devices = count(Device)
    total_users = count(User)
    active_1d = count(Device, Device.last_seen_at >= day_ago)
    active_nd = count(Device, Device.last_seen_at >= since)
    verified_users = count(User, User.verified_at.is_not(None))

    # 版本分布
    version_rows = db.execute(
        select(Device.app_version, func.count())
        .group_by(Device.app_version)
        .order_by(func.count().desc())
    ).all()
    # 平台分布
    platform_rows = db.execute(
        select(Device.platform, func.count()).group_by(Device.platform)
    ).all()

    # 人均内容量（判断真实使用深度）
    content = {
        "posts": count(BlogPost),
        "conversations": count(Conversation),
        "messages": count(Message),
        "memories": count(Memory),
        "experiences": count(Experience),
        "favorites": count(Favorite),
    }

    return {
        "devices": {
            "total": total_devices,
            "active_1d": active_1d,
            "active_%dd" % days: active_nd,
        },
        "users": {"total": total_users, "verified": verified_users},
        "versions": [
            {"version": v or "未知", "devices": int(c)} for v, c in version_rows
        ],
        "platforms": [
            {"platform": p or "未知", "devices": int(c)} for p, c in platform_rows
        ],
        "content": content,
        "generated_at": utcnow().isoformat(),
    }
