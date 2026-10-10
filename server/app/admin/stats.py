"""管理后台接口（运营看板 / 后续各管理模块）

设计约定：
- **所有接口**都走 `require_admin`，非管理员 403
- 只返回统计与聚合结果，不返回用户隐私字段（脱敏在各自模块内做）
- 时间口径：库里有两种时间列 —— `DateTime`（UTC naive）与"毫秒时间戳整数"，
  统计时必须分别处理，否则按天分桶会算错（见 `_day_bounds`）

后续模块（用户管理 / 内容审核 / 公告配置 / 版本发布 / 反馈）在此文件下追加路由即可。
"""

import datetime

from fastapi import APIRouter, Depends
from sqlalchemy import DateTime, func, select
from sqlalchemy.orm import Session

from ..deps import get_db
from .deps import require_admin
from ..models import (
    BlogPost,
    Conversation,
    Device,
    Experience,
    Favorite,
    Memory,
    Message,
    SearchItem,
    User,
    utcnow,
)

router = APIRouter(tags=["admin"])

# 运营以中国日历日为准（服务器本身也是 Asia/Shanghai，这里显式处理更稳妥）
_CST = datetime.timedelta(hours=8)
_UTC = datetime.timezone.utc


def _iso_utc(dt: datetime.datetime) -> str:
    """UTC 时间带时区后缀：前端 new Date() 才能正确换算成本地时间

    （不带后缀的 ISO 会被浏览器按本地时间解析 —— 会导致看板"更新时间"差 8 小时。）
    """
    return dt.replace(tzinfo=_UTC).isoformat()


def _day_bounds(day: datetime.date):
    """中国日历日 [day 00:00, day+1 00:00) → 对应的 UTC 起止（naive）"""
    lo = datetime.datetime(day.year, day.month, day.day) - _CST
    return lo, lo + datetime.timedelta(days=1)


def _is_datetime_col(col) -> bool:
    return isinstance(col.type, DateTime)


def _count_range(db: Session, model, col, day: datetime.date) -> int:
    """按中国日历日统计某表某列的条数（自动适配两种时间列）"""
    lo, hi = _day_bounds(day)
    if not _is_datetime_col(col):
        # 毫秒时间戳：把 UTC naive 边界当成 UTC 时刻转成毫秒
        lo = int(lo.replace(tzinfo=_UTC).timestamp() * 1000)
        hi = int(hi.replace(tzinfo=_UTC).timestamp() * 1000)
    stmt = select(func.count()).select_from(model).where(col >= lo, col < hi)
    return int(db.scalar(stmt) or 0)


def _count(db: Session, model, *conditions) -> int:
    stmt = select(func.count()).select_from(model)
    for c in conditions:
        stmt = stmt.where(c)
    return int(db.scalar(stmt) or 0)


@router.get("/admin/stats")
def admin_stats(
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
) -> dict:
    """运营看板快照：装机 / 活跃 / 版本 / 平台 / 内容量 / 使用深度

    口径（看板直接展示，务必与实现一致）：
    - **装机**：devices 表按 (user_id, device_id) 唯一 → 一台设备只算一次
    - **活跃**：设备最近一次上报时间落在 1/7/30 日窗口内
    - **新增**：首次上报（或注册）时间落在窗口内
    - **使用深度**：装机量不等于真实使用，人均对话/消息才看得出"有没有人在用"
    """
    now = utcnow()
    day_ago = now - datetime.timedelta(days=1)
    week_ago = now - datetime.timedelta(days=7)
    month_ago = now - datetime.timedelta(days=30)

    total_devices = _count(db, Device)
    total_users = _count(db, User)

    devices = {
        "total": total_devices,
        "active_1d": _count(db, Device, Device.last_seen_at >= day_ago),
        "active_7d": _count(db, Device, Device.last_seen_at >= week_ago),
        "active_30d": _count(db, Device, Device.last_seen_at >= month_ago),
        "new_1d": _count(db, Device, Device.first_seen_at >= day_ago),
        "new_7d": _count(db, Device, Device.first_seen_at >= week_ago),
        "new_30d": _count(db, Device, Device.first_seen_at >= month_ago),
    }
    users = {
        "total": total_users,
        "verified": _count(db, User, User.verified_at.is_not(None)),
        "new_1d": _count(db, User, User.created_at >= day_ago),
        "new_7d": _count(db, User, User.created_at >= week_ago),
    }

    def _dist(rows, key):
        total = sum(int(c) for _, c in rows) or 1
        return [
            {
                key: k or "未知",
                "devices": int(c),
                "share": round(int(c) * 100.0 / total, 1),
            }
            for k, c in rows
        ]

    version_rows = db.execute(
        select(Device.app_version, func.count())
        .group_by(Device.app_version)
        .order_by(func.count().desc())
    ).all()
    platform_rows = db.execute(
        select(Device.platform, func.count())
        .group_by(Device.platform)
        .order_by(func.count().desc())
    ).all()

    content = {
        "posts": _count(db, BlogPost),
        "conversations": _count(db, Conversation),
        "messages": _count(db, Message),
        "memories": _count(db, Memory),
        "experiences": _count(db, Experience),
        "favorites": _count(db, Favorite),
        "search_items": _count(db, SearchItem),
    }

    users_with_conversations = int(
        db.scalar(
            select(func.count(func.distinct(Conversation.user_id))).select_from(
                Conversation
            )
        )
        or 0
    )
    engagement = {
        "users_with_conversations": users_with_conversations,
        "conversations_per_user": round(
            content["conversations"] / max(users_with_conversations, 1), 1
        ),
        "messages_per_conversation": round(
            content["messages"] / max(content["conversations"], 1), 1
        ),
        "conversion": round(users_with_conversations * 100.0 / max(total_users, 1), 1),
    }

    return {
        "devices": devices,
        "users": users,
        "versions": _dist(version_rows, "version"),
        "platforms": _dist(platform_rows, "platform"),
        "content": content,
        "engagement": engagement,
        "generated_at": _iso_utc(now),
    }


@router.get("/admin/trend")
def admin_trend(
    days: int = 14,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
) -> dict:
    """按天趋势：新增装机 / 新增用户 / 内容产出

    只给**真实可算**的口径：每日"活跃设备"无法回溯（devices 只存最近一次活跃时间），
    需要每日快照表才能做，属后续迭代；宁可少给一个指标，也不给会误导决策的数。
    """
    days = max(1, min(days, 90))
    today = (utcnow() + _CST).date()

    series = {
        "new_devices": (Device, Device.first_seen_at),
        "new_users": (User, User.created_at),
        "messages": (Message, Message.created_at),
        "conversations": (Conversation, Conversation.created_at),
        "posts": (BlogPost, BlogPost.created_at),
    }

    items = []
    for offset in range(days - 1, -1, -1):
        day = today - datetime.timedelta(days=offset)
        row = {"date": day.isoformat()}
        for name, (model, col) in series.items():
            row[name] = _count_range(db, model, col, day)
        items.append(row)

    return {"days": days, "items": items, "generated_at": _iso_utc(utcnow())}
