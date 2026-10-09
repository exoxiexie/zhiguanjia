"""服务配置：全部来自环境变量（/etc/zhiguanjia-api.env），**不落仓库**。

密钥（JWT / DeepSeek Key / 数据库密码）只存在服务器环境变量文件里，
启动时由 systemd 注入，代码与仓库中不含任何密钥。
"""

import os
from dataclasses import dataclass


def _env(key: str, default: str = "") -> str:
    return os.environ.get(key, default)


@dataclass(frozen=True)
class Settings:
    """运行期配置"""

    env: str = _env("ZGJ_ENV", "dev")
    debug: bool = _env("ZGJ_DEBUG", "0") == "1"

    # 数据库
    db_host: str = _env("ZGJ_DB_HOST", "127.0.0.1")
    db_port: int = int(_env("ZGJ_DB_PORT", "3306") or 3306)
    db_name: str = _env("ZGJ_DB_NAME", "")
    db_user: str = _env("ZGJ_DB_USER", "")
    db_password: str = _env("ZGJ_DB_PASSWORD", "")

    # 鉴权
    jwt_secret: str = _env("ZGJ_JWT_SECRET", "")
    access_token_minutes: int = int(_env("ZGJ_ACCESS_TOKEN_MINUTES", "120") or 120)
    refresh_token_days: int = int(_env("ZGJ_REFRESH_TOKEN_DAYS", "30") or 30)

    # 上游大模型（与现有代理共用同一个 Key）
    deepseek_api_key: str = _env("DEEPSEEK_API_KEY", "")
    deepseek_base: str = _env("DEEPSEEK_BASE", "https://api.deepseek.com")

    def db_configured(self) -> bool:
        """数据库凭据是否已配置（未配置时 /health 不报错，仅标记 db=false）"""
        return bool(self.db_name and self.db_user and self.db_password)

    def jwt_configured(self) -> bool:
        return bool(self.jwt_secret)


settings = Settings()
