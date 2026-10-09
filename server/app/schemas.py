"""请求/响应模型（Pydantic v2）。

校验与错误提示都在这里，接口层只管业务逻辑。
"""

import re

from pydantic import BaseModel, Field, field_validator

PHONE_RE = re.compile(r"^1[3-9]\d{9}$")


class RegisterRequest(BaseModel):
    phone: str = Field(..., description="手机号（11 位）")
    password: str = Field(..., min_length=6, max_length=64)
    name: str = Field(..., min_length=1, max_length=32)
    device_id: str = Field(default="", max_length=64)
    device_name: str = Field(default="", max_length=64)
    platform: str = Field(default="android", max_length=16)

    @field_validator("phone")
    @classmethod
    def _check_phone(cls, v: str) -> str:
        v = (v or "").strip()
        if not PHONE_RE.match(v):
            raise ValueError("手机号格式不正确")
        return v

    @field_validator("name")
    @classmethod
    def _check_name(cls, v: str) -> str:
        v = (v or "").strip()
        if not v:
            raise ValueError("姓名不能为空")
        return v

    @field_validator("password")
    @classmethod
    def _check_password(cls, v: str) -> str:
        if len(v.strip()) < 6:
            raise ValueError("密码至少 6 位")
        return v


class LoginRequest(BaseModel):
    phone: str
    password: str
    device_id: str = Field(default="", max_length=64)
    device_name: str = Field(default="", max_length=64)
    platform: str = Field(default="android", max_length=16)


class RefreshRequest(BaseModel):
    refresh_token: str


class LogoutRequest(BaseModel):
    refresh_token: str = ""
    all_devices: bool = False


# ────────────────────── P2：职业档案 ──────────────────────


class BasicInfoRequest(BaseModel):
    """基础信息（与 App 端 BasicInfo 对齐）"""

    province: str = Field(default="", max_length=32)
    city: str = Field(default="", max_length=32)
    district: str = Field(default="", max_length=32)
    address: str = Field(default="", max_length=255)
    work_status: str = Field(default="", max_length=24)
    marital_status: str = Field(default="", max_length=24)


class SelfEvaluationRequest(BaseModel):
    """自我评价（整段文本，保存空串即清空）"""

    content: str = Field(default="", max_length=20000)


class ExperienceUpsertRequest(BaseModel):
    """单条经历（字段整体透传，服务端不理解字段语义）"""

    id: str = Field(..., min_length=1, max_length=64)
    kind_id: str = Field(..., min_length=1, max_length=32)
    values: dict = Field(default_factory=dict)
    created_at: int = 0
    updated_at: int = 0


class ExperienceBatchRequest(BaseModel):
    """批量推送：新增/更新 + 删除（离线补发用）"""

    items: list[ExperienceUpsertRequest] = Field(default_factory=list)
    deleted_ids: list[str] = Field(default_factory=list)


class IdentityRequest(BaseModel):
    """实名认证（P2 服务端能力；App 侧在切 HTTPS 后启用）

    传输的是完整身份证号，因此**必须走 HTTPS**：
    服务端只落库「脱敏号 + SHA-256 哈希」，明文不落盘、不打日志。
    """

    id_card: str = Field(..., min_length=15, max_length=18)
    real_name: str = Field(default="", max_length=32)
    gender: str = Field(default="", max_length=8)
    birthday: str = Field(default="", max_length=16)
    province: str = Field(default="", max_length=32)


# ══════════════════ P3：内容（说说 / 收藏 / 关注） ══════════════════


class PostUpsertRequest(BaseModel):
    """说说 / 博客（含图片地址列表）"""

    id: str = Field(..., min_length=1, max_length=64)
    title: str = Field(default="", max_length=200)
    content: str = Field(default="", max_length=50000)
    images: list[str] = Field(default_factory=list)
    created_at: int = 0
    updated_at: int = 0


class FavoriteUpsertRequest(BaseModel):
    id: str = Field(..., min_length=1, max_length=64)
    content: str = Field(default="", max_length=50000)
    source: str = Field(default="", max_length=64)
    created_at: int = 0


class FollowRequest(BaseModel):
    target_phone: str = Field(..., min_length=1, max_length=20)


# ══════════════════ P4：对话同步（增量 + 游标） ══════════════════


class ConversationPush(BaseModel):
    id: str = Field(..., min_length=1, max_length=64)
    title: str = Field(default="", max_length=200)
    business_tag: str = Field(default="", max_length=32)
    message_count: int = 0
    last_extracted_message_id: str = Field(default="", max_length=128)
    created_at: int = 0
    updated_at: int = 0


class MessagePush(BaseModel):
    id: str = Field(..., min_length=1, max_length=128)
    conversation_id: str = Field(..., min_length=1, max_length=64)
    role: str = Field(default="user", max_length=16)
    content: str = Field(default="", max_length=200000)
    attachment_type: str = Field(default="", max_length=16)
    attachment_path: str = Field(default="", max_length=512)
    created_at: int = 0


class MemoryPush(BaseModel):
    id: str = Field(..., min_length=1, max_length=128)
    title: str = Field(default="", max_length=200)
    content: str = Field(default="", max_length=200000)
    tags: list[str] = Field(default_factory=list)
    weight: int = 50
    category: str = Field(default="", max_length=32)
    source: str = Field(default="", max_length=64)
    created_at: int = 0
    updated_at: int = 0


class SearchItemPush(BaseModel):
    id: str = Field(..., min_length=1, max_length=128)
    title: str = Field(default="", max_length=200)
    content: str = Field(default="", max_length=200000)
    search_query: str = Field(default="", max_length=300)
    source: str = Field(default="", max_length=64)
    category: str = Field(default="", max_length=32)
    weight: int = 30
    tags: list[str] = Field(default_factory=list)
    sources: list[dict] = Field(default_factory=list)
    created_at: int = 0
    updated_at: int = 0


class SyncDeleted(BaseModel):
    """本地删除的记录（软删除同步到云端，避免"这台删了那台又回来"）"""

    conversations: list[str] = Field(default_factory=list)
    messages: list[str] = Field(default_factory=list)
    memories: list[str] = Field(default_factory=list)
    search_items: list[str] = Field(default_factory=list)


class SyncPushRequest(BaseModel):
    """离线补发：一次把攒下的变更全部推上来"""

    conversations: list[ConversationPush] = Field(default_factory=list)
    messages: list[MessagePush] = Field(default_factory=list)
    memories: list[MemoryPush] = Field(default_factory=list)
    search_items: list[SearchItemPush] = Field(default_factory=list)
    deleted: SyncDeleted = Field(default_factory=SyncDeleted)
