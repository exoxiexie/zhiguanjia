"""后台路由聚合：main.py 只需挂载一次。"""

from fastapi import APIRouter

from . import backup, blog, config, logs, stats, system

router = APIRouter()
router.include_router(stats.router)
router.include_router(blog.router)
router.include_router(system.router)
router.include_router(config.router)
router.include_router(backup.router)
router.include_router(logs.router)
