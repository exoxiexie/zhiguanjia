"""后台操作审计

**为什么用中间件**：审计最怕漏记 —— 手写日志的话，新加一个接口忘了写就永远缺一条。
这里在中间件里统一捕获所有 `/admin` 下的写操作（POST/PUT/PATCH/DELETE），
包括**失败的**与**未授权尝试**（这两类恰恰最需要留痕）。

各接口可以再设置 `request.state.audit_target`，给日志补上人类可读的对象
（例如「文章《为什么职业规划要趁早》」），前端据此显示。
"""

import os
import time

from sqlalchemy import func, select
from starlette.middleware.base import BaseHTTPMiddleware

from ..db import SessionLocal
from ..models import AuditLog, utcnow

WRITE_METHODS = ("POST", "PUT", "PATCH", "DELETE")
# 最多保留多少条（小磁盘 + 只用于复盘，不需要无限增长）
KEEP = int(os.environ.get("ZGJ_AUDIT_KEEP", "5000"))
_PRUNE_SLACK = 200


def normalize_action(method: str, path: str) -> str:
    """把路径里的具体 id 换成 {id}，便于聚合与前端映射中文"""
    parts = []
    for seg in path.strip("/").split("/"):
        if not seg:
            continue
        # 文章 slug / 备份名 / uuid 都视为参数
        if len(seg) > 20 or ("-" in seg and any(c.isdigit() for c in seg)):
            parts.append("{id}")
        else:
            parts.append(seg)
    return "/" + "/".join(parts)


def client_ip(request) -> str:
    fwd = request.headers.get("x-forwarded-for", "")
    if fwd:
        return fwd.split(",")[0].strip()[:64]
    return (request.client.host if request.client else "")[:64]


def _prune(db) -> None:
    total = int(db.scalar(select(func.count()).select_from(AuditLog)) or 0)
    if total <= KEEP + _PRUNE_SLACK:
        return
    old_ids = [
        r[0]
        for r in db.execute(
            select(AuditLog.id).order_by(AuditLog.id.asc()).limit(total - KEEP)
        ).all()
    ]
    if old_ids:
        db.query(AuditLog).filter(AuditLog.id.in_(old_ids)).delete(
            synchronize_session=False
        )


class AuditMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        path = request.url.path
        if not (path.startswith("/admin") and request.method in WRITE_METHODS):
            return await call_next(request)

        started = time.time()
        response = await call_next(request)
        duration = int((time.time() - started) * 1000)

        # 审计写入失败绝不影响正常响应（尽力而为）
        try:
            db = SessionLocal()
            try:
                row = AuditLog(
                    actor=getattr(request.state, "actor", "") or "",
                    action=normalize_action(request.method, path),
                    method=request.method,
                    target=getattr(request.state, "audit_target", "") or "",
                    status=response.status_code,
                    ok=1 if response.status_code < 400 else 0,
                    ip=client_ip(request),
                    duration_ms=duration,
                    created_at=utcnow(),
                )
                db.add(row)
                db.commit()
                _prune(db)
                db.commit()
            finally:
                db.close()
        except Exception:  # noqa: BLE001
            pass
        return response
