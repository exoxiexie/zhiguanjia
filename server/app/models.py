"""数据模型（P1：账号体系）。

设计要点：
- 主键用客户端/服务端生成的 **UUID 字符串**（后续同步表也沿用，天然去重）
- 密码只存 **bcrypt 哈希**，永不落明文
- 身份证只存 **脱敏号 + SHA-256 哈希**（哈希用于"同一证件不能绑多号"校验）
- refresh token 只存 **SHA-256 哈希**，即使库被读也无法直接使用
"""

import datetime
import uuid

from sqlalchemy import BigInteger, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base


def utcnow() -> datetime.datetime:
    """UTC 当前时间（naive，MySQL DATETIME 不存时区）"""
    return datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)


def new_uuid() -> str:
    return str(uuid.uuid4())


class User(Base):
    """用户账号"""

    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    phone: Mapped[str] = mapped_column(String(20), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(120))
    name: Mapped[str] = mapped_column(String(64), default="")

    # 档案（P2 完善，先建好字段）
    avatar_path: Mapped[str] = mapped_column(String(255), default="")
    gender: Mapped[str] = mapped_column(String(8), default="")
    birthday: Mapped[str] = mapped_column(String(16), default="")
    province: Mapped[str] = mapped_column(String(32), default="")
    id_card_masked: Mapped[str] = mapped_column(String(24), default="")
    id_card_hash: Mapped[str] = mapped_column(String(64), default="")
    verified_at: Mapped[datetime.datetime | None] = mapped_column(
        DateTime, nullable=True
    )

    status: Mapped[int] = mapped_column(Integer, default=1)  # 1 正常，0 禁用
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[datetime.datetime] = mapped_column(
        DateTime, default=utcnow, onupdate=utcnow
    )

    def to_public(self) -> dict:
        """对外返回的用户信息（不含密码哈希等敏感字段）"""
        return {
            "id": self.id,
            "phone": self.phone,
            "name": self.name,
            "avatar_path": self.avatar_path or "",
            "gender": self.gender or "",
            "birthday": self.birthday or "",
            "province": self.province or "",
            "id_card_masked": self.id_card_masked or "",
            "is_verified": bool(self.verified_at),
            "verified_at": self.verified_at.isoformat() if self.verified_at else "",
            "created_at": self.created_at.isoformat() if self.created_at else "",
        }


class AuthToken(Base):
    """刷新令牌（每设备一条，可单独吊销）"""

    __tablename__ = "auth_tokens"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("users.id"), index=True
    )
    token_hash: Mapped[str] = mapped_column(String(64), index=True)
    device_id: Mapped[str] = mapped_column(String(64), default="")
    device_name: Mapped[str] = mapped_column(String(64), default="")
    platform: Mapped[str] = mapped_column(String(16), default="android")
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime, default=utcnow)
    last_used_at: Mapped[datetime.datetime | None] = mapped_column(
        DateTime, nullable=True
    )
    expires_at: Mapped[datetime.datetime] = mapped_column(DateTime)
    revoked_at: Mapped[datetime.datetime | None] = mapped_column(
        DateTime, nullable=True
    )

    def is_valid(self) -> bool:
        return self.revoked_at is None and self.expires_at > utcnow()


class UserProfile(Base):
    """用户档案（P2）：一账号一行，承载基础信息与自我评价

    与 [User] 分表的原因：`users` 是**账号身份**（登录、实名），
    本表是**职业档案**（可频繁修改、将来字段会不断增多），
    两者变更频率与敏感度都不同，分表避免互相加锁与误更新。
    """

    __tablename__ = "user_profiles"

    user_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("users.id"), primary_key=True
    )
    # 基础信息（与 App 端 BasicInfo 字段一一对应）
    province: Mapped[str] = mapped_column(String(32), default="")
    city: Mapped[str] = mapped_column(String(32), default="")
    district: Mapped[str] = mapped_column(String(32), default="")
    address: Mapped[str] = mapped_column(String(255), default="")
    work_status: Mapped[str] = mapped_column(String(24), default="")
    marital_status: Mapped[str] = mapped_column(String(24), default="")

    # 自我评价
    self_evaluation: Mapped[str] = mapped_column(Text, default="")

    updated_at: Mapped[datetime.datetime] = mapped_column(
        DateTime, default=utcnow, onupdate=utcnow
    )

    def basic_public(self) -> dict:
        return {
            "province": self.province or "",
            "city": self.city or "",
            "district": self.district or "",
            "address": self.address or "",
            "work_status": self.work_status or "",
            "marital_status": self.marital_status or "",
        }


class Experience(Base):
    """职业经历（教育 / 工作 / 培训）

    **为什么字段整体存 JSON**：App 端经历是「描述表驱动」的通用实体
    （见 experience_models.dart），字段清单会随业务增长（项目经历、证书…）。
    存 JSON 意味着**新增经历类型或字段不需要改表、不需要发版迁移**，
    服务端只做「按 kind 分组存储 + 按更新时间合并」。
    """

    __tablename__ = "experiences"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("users.id"), index=True
    )
    kind_id: Mapped[str] = mapped_column(String(32), index=True)
    values_json: Mapped[str] = mapped_column(Text, default="{}")
    # 客户端毫秒时间戳（用于 last-write-wins 与展示排序）
    created_at: Mapped[int] = mapped_column(BigInteger, default=0)
    updated_at: Mapped[int] = mapped_column(BigInteger, default=0)
    # 服务端写入时间（客户端时间不可信，作为冲突裁决的次级依据）
    server_updated_at: Mapped[datetime.datetime] = mapped_column(
        DateTime, default=utcnow, onupdate=utcnow
    )

    def to_public(self) -> dict:
        import json as _json

        try:
            values = _json.loads(self.values_json or "{}")
        except Exception:  # noqa: BLE001
            values = {}
        if not isinstance(values, dict):
            values = {}
        return {
            "id": self.id,
            "kind_id": self.kind_id,
            "values": {str(k): str(v) for k, v in values.items()},
            "created_at": self.created_at or 0,
            "updated_at": self.updated_at or 0,
        }
