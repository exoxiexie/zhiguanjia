"""数据库连接层（SQLAlchemy）。

生产用 MySQL（PyMySQL 驱动）；本地测试可用环境变量 ZGJ_DATABASE_URL 覆盖为 SQLite。
数据库密码含特殊字符时会被正确 URL 转义，不会破坏连接串。
"""

import os
from urllib.parse import quote_plus

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from .config import settings


def database_url() -> str:
    """连接串：优先环境变量（便于测试），否则按配置拼 MySQL 连接串"""
    override = os.environ.get("ZGJ_DATABASE_URL")
    if override:
        return override
    return "mysql+pymysql://%s:%s@%s:%s/%s?charset=utf8mb4" % (
        quote_plus(settings.db_user),
        quote_plus(settings.db_password),
        settings.db_host,
        settings.db_port,
        settings.db_name,
    )


_is_sqlite = database_url().startswith("sqlite")

engine = create_engine(
    database_url(),
    pool_pre_ping=True,      # 连接失效自动重连（MySQL 8h 超时问题）
    pool_recycle=1800,
    future=True,
    connect_args={"check_same_thread": False} if _is_sqlite else {},
)

SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


class Base(DeclarativeBase):
    """ORM 基类"""
