"""当前用户相关接口

GET    /me          当前登录用户资料
GET    /me/export   导出全部个人数据（合规：个人信息可携带）
DELETE /me          注销账号（合规：删除权），级联清理服务端全部数据

合规说明：个人信息保护法要求用户能"查阅、复制、删除"自己的个人信息，
因此导出必须**完整**、注销必须**彻底**（含上传的图片文件）。
"""

import json
import os
import shutil

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..deps import get_current_user, get_db
from ..errors import api_error
from ..models import (
    AuthToken,
    BlogPost,
    Conversation,
    Device,
    Experience,
    Favorite,
    Follow,
    Memory,
    Message,
    SearchItem,
    User,
    UserProfile,
    UserSyncState,
)

router = APIRouter(tags=["me"])

# 图片落盘目录（与 content.py 保持一致）
UPLOAD_DIR = os.environ.get("ZGJ_UPLOAD_DIR", "/www/wwwroot/zhiguanjia-uploads")


@router.get("/me")
def me(user: User = Depends(get_current_user)) -> dict:
    """返回当前登录用户资料（不含密码哈希等敏感字段）"""
    return user.to_public()


@router.get("/me/export")
def export_my_data(
    user: User = Depends(get_current_user), db: Session = Depends(get_db)
) -> dict:
    """导出该账号在服务端的**全部**数据（JSON）"""

    def all_of(model):
        return [r.to_public() for r in db.scalars(select(model).where(model.user_id == user.id)).all()]

    profile = db.get(UserProfile, user.id)
    devices = db.scalars(select(Device).where(Device.user_id == user.id)).all()
    follows = db.scalars(select(Follow).where(Follow.user_id == user.id)).all()

    return {
        "exported_at": __import__("datetime").datetime.utcnow().isoformat(),
        "account": user.to_public(),
        "profile": profile.basic_public() if profile else {},
        "self_evaluation": (profile.self_evaluation if profile else "") or "",
        "experiences": all_of(Experience),
        "posts": all_of(BlogPost),
        "favorites": all_of(Favorite),
        "follows": [{"target_phone": f.target_phone, "created_at": f.created_at} for f in follows],
        "conversations": all_of(Conversation),
        "messages": all_of(Message),
        "memories": all_of(Memory),
        "search_items": all_of(SearchItem),
        "devices": [d.to_public() for d in devices],
        "note": "身份证号等敏感信息仅保存脱敏号与哈希，完整证件号从未上传，故导出中不含完整号码。",
    }


@router.delete("/me")
def delete_my_account(
    confirm: str = "",
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    """注销账号：级联删除服务端全部数据 + 上传文件

    需要显式 `confirm=DELETE`（防止误调用/误触导致不可逆的数据丢失）。
    """
    if confirm != "DELETE":
        raise api_error(400, "confirm_required", "注销需要二次确认（confirm=DELETE）")

    deleted = {}

    # 先删从表（有外键指向 users）
    for model in (
        Experience,
        BlogPost,
        Favorite,
        Conversation,
        Message,
        Memory,
        SearchItem,
        Device,
        AuthToken,
        UserSyncState,
    ):
        rows = db.scalars(select(model).where(model.user_id == user.id)).all()
        deleted[model.__tablename__] = len(rows)
        for r in rows:
            db.delete(r)

    profile = db.get(UserProfile, user.id)
    if profile is not None:
        db.delete(profile)
        deleted["user_profiles"] = 1

    follows = db.scalars(select(Follow).where(Follow.user_id == user.id)).all()
    deleted["follows"] = len(follows)
    for f in follows:
        db.delete(f)

    db.delete(user)
    db.commit()

    # 删除该用户上传的图片
    user_dir = os.path.join(UPLOAD_DIR, user.id)
    if os.path.isdir(user_dir):
        shutil.rmtree(user_dir, ignore_errors=True)

    return {"ok": True, "deleted": deleted, "note": "账号与全部服务端数据已删除，不可恢复"}

