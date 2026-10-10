"""职管家 · 商业版 API 服务

P1 阶段：账号体系（注册/登录/刷新/退出/我的资料）

路径约定：Nginx 把 `/api/` 反代到本服务的 `/`（剥离前缀），
因此本服务内部路由写 `/auth/login`、`/health`，
对外即 `/api/auth/login`、`/api/health`；将来切域名后前端无需改动。
"""

from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from .admin import router as admin_router
from .config import settings
from .db import Base, engine
from .routers import auth, config, content, device, me, profile, sync

from .version import APP_VERSION  # noqa: E402


@asynccontextmanager
async def lifespan(_: FastAPI):
    """启动时建表（MVP 阶段；表结构稳定后改用 Alembic 迁移）"""
    Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(
    title="职管家 API",
    version=APP_VERSION,
    docs_url="/docs" if settings.debug else None,
    redoc_url=None,
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)


# ── 统一错误结构：{"error": {"code": "...", "message": "..."}} ──
@app.exception_handler(StarletteHTTPException)
async def _http_error_handler(_: Request, exc: StarletteHTTPException) -> JSONResponse:
    detail = exc.detail
    if isinstance(detail, dict) and "code" in detail:
        body = {"error": detail}
    else:
        body = {
            "error": {"code": "http_%d" % exc.status_code, "message": str(detail)}
        }
    return JSONResponse(status_code=exc.status_code, content=body)


@app.exception_handler(RequestValidationError)
async def _validation_error_handler(
    _: Request, exc: RequestValidationError
) -> JSONResponse:
    errors = exc.errors() or []
    first = errors[0] if errors else {}
    loc = [str(x) for x in first.get("loc", []) if x not in ("body", "query", "path")]
    message = str(first.get("msg", "请求参数不正确")).replace("Value error, ", "")
    field = ".".join(loc) or "参数"
    return JSONResponse(
        status_code=422,
        content={
            "error": {
                "code": "invalid_request",
                "message": "%s: %s" % (field, message),
            }
        },
    )


app.include_router(auth.router)
app.include_router(me.router)
app.include_router(profile.router)
app.include_router(content.router)
app.include_router(sync.router)
app.include_router(device.router)
app.include_router(admin_router)  # 后台管理系统（独立子包）
app.include_router(config.router)


def _probe_db() -> bool:
    """真连一次数据库；未配置凭据时直接返回 False（不算故障）"""
    if not settings.db_configured() and not settings.db_override:
        return False
    try:
        from sqlalchemy import text

        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return True
    except Exception:  # noqa: BLE001
        return False


@app.get("/health")
async def health() -> JSONResponse:
    """/api/health —— 部署验收与监控探针"""
    return JSONResponse(
        {
            "ok": True,
            "service": "zhiguanjia-api",
            "version": APP_VERSION,
            "env": settings.env,
            "db_configured": settings.db_configured() or settings.db_override,
            "db": _probe_db(),
            "jwt_configured": settings.jwt_configured(),
            "deepseek_configured": bool(settings.deepseek_api_key),
        }
    )


@app.get("/")
async def index() -> JSONResponse:
    return JSONResponse(
        {
            "service": "职管家 API",
            "version": APP_VERSION,
            "health": "/health",
            "auth": ["/auth/register", "/auth/login", "/auth/refresh", "/auth/logout"],
            "me": "/me",
            "profile": "/profile",
            "content": "/content",
            "sync": "/sync",
            "hint": "本服务通过 /api/ 对外提供，请访问 /api/health",
        }
    )
