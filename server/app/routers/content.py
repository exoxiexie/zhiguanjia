"""内容接口（P3）：说说/博客、收藏、关注、图片上传

同步策略（《商业版改造方案》第五节 B 类「内容类」）：**服务端为准 + 本地缓存**。

关于可见范围：`GET /content` 返回「我发布的 + 全站最近 N 条」，
客户端按作者手机号分组写回本机原有的 `blog_posts_{作者手机号}` 存储键，
因此「推荐 / 关注 / 我的」三个子 Tab 的既有逻辑**一行都不用改**。
"""

import json
import os
import uuid

from fastapi import APIRouter, Depends, File, UploadFile
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..deps import get_current_user, get_db
from ..errors import api_error
from ..models import BlogPost, Favorite, Follow, User, utcnow
from ..schemas import FavoriteUpsertRequest, FollowRequest, PostUpsertRequest

router = APIRouter(prefix="/content", tags=["content"])

# 图片落盘目录（Nginx 以 /uploads/ 对外提供；见部署文档）
UPLOAD_DIR = os.environ.get("ZGJ_UPLOAD_DIR", "/www/wwwroot/zhiguanjia-uploads")
ALLOWED_EXT = {".jpg", ".jpeg", ".png", ".gif", ".webp"}
MAX_UPLOAD_BYTES = 8 * 1024 * 1024  # 单图 8MB


@router.get("")
def get_content(
    feed_limit: int = 100,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    """拉取内容：全站说说（含我的）+ 我的收藏 + 我的关注"""
    feed_limit = max(1, min(feed_limit, 300))

    posts = db.scalars(
        select(BlogPost)
        .where(BlogPost.deleted_at.is_(None))
        .order_by(BlogPost.created_at.desc())
        .limit(feed_limit)
    ).all()

    favorites = db.scalars(
        select(Favorite)
        .where(Favorite.user_id == user.id, Favorite.deleted_at.is_(None))
        .order_by(Favorite.created_at.desc())
    ).all()

    follows = db.scalars(
        select(Follow).where(Follow.user_id == user.id).order_by(Follow.created_at.desc())
    ).all()

    return {
        "posts": [p.to_public() for p in posts],
        "favorites": [f.to_public() for f in favorites],
        "follows": [f.target_phone for f in follows],
        "user": user.to_public(),
    }


@router.post("/posts")
def upsert_post(
    body: PostUpsertRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    """发布 / 修改说说（只能改自己的内容）"""
    row = db.get(BlogPost, body.id)
    if row is not None and row.user_id != user.id:
        raise api_error(403, "not_owner", "只能修改自己发布的内容")
    if row is None:
        row = BlogPost(id=body.id, user_id=user.id)
        db.add(row)

    row.title = body.title.strip()
    row.content = (body.content or "")[:600000]
    row.images_json = json.dumps(
        [str(x)[:512] for x in (body.images or [])][:9], ensure_ascii=False
    )
    # 作者信息以账号为准（不接受客户端伪造作者）
    row.author_phone = user.phone
    row.author_name = user.name or ""
    row.author_avatar_path = user.avatar_path or ""
    row.created_at = body.created_at or row.created_at or 0
    row.updated_at = body.updated_at or row.updated_at or 0
    row.deleted_at = None
    db.commit()
    db.refresh(row)
    return {"post": row.to_public()}


@router.delete("/posts/{post_id}")
def delete_post(
    post_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    row = db.get(BlogPost, post_id)
    if row is None or row.user_id != user.id:
        raise api_error(404, "post_not_found", "内容不存在")
    row.deleted_at = utcnow()
    db.commit()
    return {"ok": True}


@router.post("/favorites")
def upsert_favorite(
    body: FavoriteUpsertRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    row = db.get(Favorite, body.id)
    if row is not None and row.user_id != user.id:
        raise api_error(403, "not_owner", "只能修改自己的收藏")
    if row is None:
        row = Favorite(id=body.id, user_id=user.id)
        db.add(row)
    row.content = (body.content or "")[:600000]
    row.source = body.source.strip()
    row.created_at = body.created_at or row.created_at or 0
    row.deleted_at = None
    db.commit()
    db.refresh(row)
    return {"favorite": row.to_public()}


@router.delete("/favorites/{favorite_id}")
def delete_favorite(
    favorite_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    row = db.get(Favorite, favorite_id)
    if row is None or row.user_id != user.id:
        raise api_error(404, "favorite_not_found", "收藏不存在")
    row.deleted_at = utcnow()
    db.commit()
    return {"ok": True}


@router.put("/follows")
def follow(
    body: FollowRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    target = body.target_phone.strip()
    if target == user.phone:
        raise api_error(400, "cannot_follow_self", "不能关注自己")
    row = db.get(Follow, (user.id, target))
    if row is None:
        db.add(Follow(user_id=user.id, target_phone=target,
                      created_at=int(utcnow().timestamp() * 1000)))
        db.commit()
    return {"ok": True, "following": True}


@router.delete("/follows/{target_phone}")
def unfollow(
    target_phone: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    row = db.get(Follow, (user.id, target_phone.strip()))
    if row is not None:
        db.delete(row)
        db.commit()
    return {"ok": True, "following": False}


@router.post("/upload")
async def upload_image(
    file: UploadFile = File(...),
    user: User = Depends(get_current_user),
) -> dict:
    """上传一张图片（说说配图）

    安全约束：仅图片扩展名 + 单文件 8MB + 按用户分目录存放，
    文件名由服务端生成（绝不使用客户端文件名，避免路径穿越）。
    """
    ext = os.path.splitext(file.filename or "")[1].lower()
    if ext not in ALLOWED_EXT:
        raise api_error(400, "bad_file_type", "只支持 jpg / png / gif / webp 图片")

    data = await file.read()
    if not data:
        raise api_error(400, "empty_file", "文件内容为空")
    if len(data) > MAX_UPLOAD_BYTES:
        raise api_error(413, "file_too_large", "图片不能超过 8MB")

    user_dir = os.path.join(UPLOAD_DIR, user.id)
    os.makedirs(user_dir, exist_ok=True)
    name = "%s%s" % (uuid.uuid4().hex, ext)
    with open(os.path.join(user_dir, name), "wb") as f:
        f.write(data)

    # 返回相对路径：客户端用同一个主机名拼出完整地址（换域名时无需改库）
    return {"url": "/uploads/%s/%s" % (user.id, name), "size": len(data)}
