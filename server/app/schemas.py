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
