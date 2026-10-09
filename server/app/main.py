"""职管家 · 商业版 API 服务

P0（地基）阶段职责：
  1. 提供 /health 健康检查（进程 + 配置 + 数据库连通性）
  2. 作为后续业务路由（auth / users / posts / conversations / sync）的挂载点

路径约定：
  Nginx 把前端的 `/api/` 反代到本服务的 `/`（剥离前缀），
  因此本服务内部路由写 `/health`，对外即 `/api/health`；
  将来切到域名后同样是 `https://zhidongni.com.cn/api/health`，前端无需改动。
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .config import settings

APP_VERSION = "0.1.0"

app = FastAPI(
    title="职管家 API",
    version=APP_VERSION,
    docs_url="/docs" if settings.debug else None,
    redoc_url=None,
)

# App 端（移动端）不需要 CORS，但保留以便调试页面调用
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)


def _probe_db() -> bool:
    """真连一次数据库；未配置凭据时直接返回 False（不算故障）"""
    if not settings.db_configured():
        return False
    try:
        import pymysql

        conn = pymysql.connect(
            host=settings.db_host,
            port=settings.db_port,
            user=settings.db_user,
            password=settings.db_password,
            database=settings.db_name,
            charset="utf8mb4",
            connect_timeout=3,
        )
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
            cur.fetchone()
        conn.close()
        return True
    except Exception:  # noqa: BLE001
        return False


@app.get("/health")
async def health() -> JSONResponse:
    """/api/health —— 部署验收与监控探针"""
    body = {
        "ok": True,
        "service": "zhiguanjia-api",
        "version": APP_VERSION,
        "env": settings.env,
        "db_configured": settings.db_configured(),
        "db": _probe_db(),
        "jwt_configured": settings.jwt_configured(),
        "deepseek_configured": bool(settings.deepseek_api_key),
    }
    return JSONResponse(body)


@app.get("/")
async def index() -> JSONResponse:
    """根路径给个明确提示，避免误访问时 404 让人困惑"""
    return JSONResponse(
        {
            "service": "职管家 API",
            "version": APP_VERSION,
            "health": "/health",
            "hint": "本服务通过 /api/ 对外提供，请访问 /api/health",
        }
    )
