"""后台「内容审核」

范围说明（有意为之）：
- **审核对象是公开内容**（说说 / posts）—— 它会被其他用户看到，必须可管可下架
- **一对一对话属私密内容，不做批量巡检**（隐私优先）；若要处理具体投诉，
  按用户维度定位而不是全量浏览
- 下架是**软删除**（`deleted_at` + 原因）：App 拉取时按 deleted 同步消失，
  误下架可以一键恢复，数据不丢

后续（需 App 侧配合）：用户举报入口、图片鉴黄。
"""

import datetime

from fastapi import APIRouter, Depends, Request
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from ..deps import get_db
from ..errors import api_error
from ..models import BlogPost, User, utcnow
from ..schemas import ContentHideIn
from .deps import require_admin

router = APIRouter(tags=["admin-content"])

_CST = datetime.timedelta(hours=8)


def _serialize(p: BlogPost, author: User | None) -> dict:
    images = []
    try:
        import json

        images = json.loads(p.images_json or "[]")
    except Exception:  # noqa: BLE001
        images = []
    return {
        "id": p.id,
        "title": p.title or "",
        "content": p.content or "",
        "images": len(images),
        "author_phone": p.author_phone or (author.phone if author else ""),
        "author_name": p.author_name or (author.name if author else ""),
        "author_id": p.user_id,
        "author_hidden": bool(author and author.status != 1),
        "created_at": (p.created_at or 0),
        "hidden": p.deleted_at is not None,
        "hidden_at": (p.deleted_at + _CST).isoformat(sep=" ", timespec="seconds")
        if p.deleted_at
        else "",
        "hidden_reason": getattr(p, "hidden_reason", "") or "",
    }


@router.get("/admin/content")
def list_content(
    q: str = "",
    only_hidden: bool = False,
    limit: int = 50,
    offset: int = 0,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
) -> dict:
    """说说列表（按内容/作者检索；可只看已下架）"""
    limit = max(1, min(limit, 200))
    stmt = select(BlogPost)
    count_stmt = select(func.count()).select_from(BlogPost)
    if q.strip():
        like = f"%{q.strip()}%"
        cond = or_(BlogPost.content.like(like), BlogPost.title.like(like),
                   BlogPost.author_phone.like(like), BlogPost.author_name.like(like))
        stmt = stmt.where(cond)
        count_stmt = count_stmt.where(cond)
    if only_hidden:
        stmt = stmt.where(BlogPost.deleted_at.is_not(None))
        count_stmt = count_stmt.where(BlogPost.deleted_at.is_not(None))

    rows = db.scalars(
        stmt.order_by(BlogPost.created_at.desc()).offset(max(0, offset)).limit(limit)
    ).all()
    authors = {}
    if rows:
        ids = {p.user_id for p in rows}
        for u in db.scalars(select(User).where(User.id.in_(ids))).all():
            authors[u.id] = u

    total_all = int(db.scalar(select(func.count()).select_from(BlogPost)) or 0)
    total_hidden = int(
        db.scalar(
            select(func.count()).select_from(BlogPost).where(BlogPost.deleted_at.is_not(None))
        )
        or 0
    )
    return {
        "items": [_serialize(p, authors.get(p.user_id)) for p in rows],
        "total": int(db.scalar(count_stmt) or 0),
        "stats": {"all": total_all, "hidden": total_hidden},
    }


@router.post("/admin/content/{post_id}/hide")
def hide_content(
    post_id: str,
    body: ContentHideIn,
    request: Request,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
) -> dict:
    """下架（软删除，可恢复）：App 下次拉取即同步消失"""
    row = db.get(BlogPost, post_id)
    if row is None:
        raise api_error(404, "not_found", "内容不存在")
    reason = (body.reason or "").strip()
    if not reason:
        raise api_error(400, "reason_required", "下架必须填写原因（便于复查与申诉）")
    row.deleted_at = utcnow()
    row.hidden_reason = reason[:200]
    request.state.audit_target = f"说说《{(row.title or row.content or '')[:20]}》（作者 {row.author_phone}）下架"
    db.add(row)
    db.commit()
    return {"ok": True}


@router.post("/admin/content/{post_id}/restore")
def restore_content(
    post_id: str,
    request: Request,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
) -> dict:
    """恢复已下架内容（误操作可回退）"""
    row = db.get(BlogPost, post_id)
    if row is None:
        raise api_error(404, "not_found", "内容不存在")
    row.deleted_at = None
    row.hidden_reason = ""
    request.state.audit_target = f"说说《{(row.title or row.content or '')[:20]}》恢复"
    db.add(row)
    db.commit()
    return {"ok": True}
