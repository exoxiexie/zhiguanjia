"""后台「系统管理」

定位：**站点级 / 系统级操作**的家，与内容模块（博客、用户、审核）分开。
随着后台长大，这类操作会越来越多（备份恢复、日志、权限、定时任务……），
统一收到这里，内容模块就不会被系统操作污染。

当前包含：站点状态、发布站点。
"""

import datetime
import os

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..deps import get_db
from .deps import require_admin
from ..errors import api_error
from ..models import Article, User, utcnow
from .publisher import (
    SITE_DIR,
    WEB_ROOT,
    get_last_build,
    rebuild_and_deploy,
)

router = APIRouter(tags=["admin-system"])

_CST = datetime.timedelta(hours=8)


@router.get("/admin/system/status")
def system_status(
    user: User = Depends(require_admin), db: Session = Depends(get_db)
) -> dict:
    """系统状态：站点目录、内容量、最近一次发布

    `last_build` 从磁盘读取（跨 worker、跨重启一致）；
    从未发布过时为 None —— 界面会如实标注，不假装知道。
    """
    from ..version import APP_VERSION

    articles = int(db.scalar(select(func.count()).select_from(Article)) or 0)
    published = int(
        db.scalar(
            select(func.count()).select_from(Article).where(Article.status == "published")
        )
        or 0
    )
    users = int(db.scalar(select(func.count()).select_from(User)) or 0)
    return {
        "api_version": APP_VERSION,
        "server_time": (utcnow() + _CST).isoformat(timespec="seconds"),
        "site_dir": SITE_DIR,
        "site_dir_ready": os.path.isdir(SITE_DIR),
        "web_root": WEB_ROOT,
        "web_root_ready": os.path.isdir(WEB_ROOT),
        "articles": articles,
        "articles_published": published,
        "users": users,
        "last_build": get_last_build(),
    }


@router.post("/admin/system/rebuild")
def system_rebuild(
    user: User = Depends(require_admin), db: Session = Depends(get_db)
) -> dict:
    """发布站点：把当前文章与页面重新构建后发布到官网

    （从「博客发布管理」搬来 —— 它重建的是整站，属于系统操作）
    """
    result = rebuild_and_deploy()
    if not result["ok"]:
        if result.get("busy"):
            raise api_error(409, "busy", result["message"])
        raise api_error(500, "rebuild_failed", result["message"])
    return {"ok": True, "message": result["message"], "last_build": get_last_build()}
