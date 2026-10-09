"""服务配置

配置分两层，**都不进仓库**：

1. `/etc/zhiguanjia-api.env`（systemd 注入）：非敏感、结构简单的配置
   —— 运行环境、JWT 密钥、数据库主机/端口
2. `/etc/zhiguanjia-api-secrets.json`（应用自行读取）：**可能含特殊字符的密钥**
   —— 数据库名/用户/密码、DeepSeek Key 等

为什么密钥单独放 JSON：systemd 的 EnvironmentFile 对 `"` `\` `$` `#` 等字符
有转义歧义，密码由宝塔随机生成时极易踩坑。交给 Python 用 json 读写可以
安全处理任意字符（写入侧统一用 json.dump，读取侧用 json.load）。

文件缺失或损坏时**不抛异常**：对应项留空，/health 会显示为未配置，
避免服务因配置问题启动失败。
"""

import json
import os
from dataclasses import dataclass

# 密钥文件位置（可用环境变量覆盖，便于本地测试）
SECRETS_FILE = os.environ.get(
    "ZGJ_SECRETS_FILE", "/etc/zhiguanjia-api-secrets.json"
)


def _load_secrets() -> dict:
    """读取密钥 JSON；文件不存在或格式错误时返回空字典（不抛异常）"""
    try:
        with open(SECRETS_FILE, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except Exception:  # noqa: BLE001
        return {}


_SECRETS = _load_secrets()


def _get(key: str, default: str = "") -> str:
    """取值优先级：环境变量 → 密钥 JSON → 默认值"""
    value = os.environ.get(key)
    if value:
        return value
    value = _SECRETS.get(key)
    if value is None or value == "":
        return default
    return str(value)


@dataclass(frozen=True)
class Settings:
    """运行期配置"""

    env: str = _get("ZGJ_ENV", "dev")
    debug: bool = _get("ZGJ_DEBUG", "0") == "1"

    # 数据库
    db_host: str = _get("ZGJ_DB_HOST", "127.0.0.1")
    db_port: int = int(_get("ZGJ_DB_PORT", "3306") or 3306)
    db_name: str = _get("ZGJ_DB_NAME")
    db_user: str = _get("ZGJ_DB_USER")
    db_password: str = _get("ZGJ_DB_PASSWORD")

    # 鉴权
    jwt_secret: str = _get("ZGJ_JWT_SECRET")
    access_token_minutes: int = int(_get("ZGJ_ACCESS_TOKEN_MINUTES", "120") or 120)
    refresh_token_days: int = int(_get("ZGJ_REFRESH_TOKEN_DAYS", "30") or 30)

    # 上游大模型（与现有代理共用同一个 Key）
    deepseek_api_key: str = _get("DEEPSEEK_API_KEY")
    deepseek_base: str = _get("DEEPSEEK_BASE", "https://api.deepseek.com")

    def db_configured(self) -> bool:
        """数据库凭据是否已配置（未配置时 /health 不报错，仅标记 db=false）"""
        return bool(self.db_name and self.db_user and self.db_password)

    def jwt_configured(self) -> bool:
        return bool(self.jwt_secret)


settings = Settings()
