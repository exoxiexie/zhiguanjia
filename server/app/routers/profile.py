"""职业档案接口（P2）

GET    /profile                     拉取整份档案（基础信息 + 自我评价 + 经历）
PUT    /profile/basic               保存基础信息
PUT    /profile/evaluation          保存自我评价
POST   /profile/experiences         新增/更新一条经历（按 id 幂等）
POST   /profile/experiences/batch   批量新增/更新 + 批量删除（离线补发）
DELETE /profile/experiences/{id}    删除一条经历
PUT    /profile/identity            实名认证（App 侧在 HTTPS 后启用）

同步策略（见《商业版改造方案》第五节 A 类「档案类」）：
**服务端为准**，App 端只做本地缓存 —— 写完即上云、启动时拉取，
因此换手机后档案立即一致，且不存在"两边各改一半"的合并难题。
"""

import datetime
import hashlib

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..deps import get_current_user, get_db
from ..errors import api_error
from ..models import Experience, User, UserProfile, utcnow
from ..schemas import (
    BasicInfoRequest,
    ExperienceBatchRequest,
    ExperienceUpsertRequest,
    IdentityRequest,
    SelfEvaluationRequest,
)

router = APIRouter(prefix="/profile", tags=["profile"])


def _profile_of(db: Session, user: User) -> UserProfile:
    """取当前用户档案，没有则建一行（懒初始化，避免注册时写一堆空数据）"""
    profile = db.get(UserProfile, user.id)
    if profile is None:
        profile = UserProfile(user_id=user.id)
        db.add(profile)
        db.commit()
        db.refresh(profile)
    return profile


def _clean_values(raw: dict) -> dict:
    """经历字段统一成 {str: str}，过滤空键，限制长度避免脏数据撑爆库"""
    out = {}
    for key, value in (raw or {}).items():
        k = str(key)[:64]
        v = "" if value is None else str(value)
        out[k] = v[:4000]
    return out


def _upsert_experience(
    db: Session, user: User, item: ExperienceUpsertRequest
) -> Experience:
    """按 id 幂等写入；已存在时按 updated_at 做 last-write-wins"""
    row = db.get(Experience, item.id)
    if row is not None and row.user_id != user.id:
        # 同一 id 被别的账号占用：极不可能（id 由客户端生成），直接拒绝而非覆盖
        raise api_error(409, "experience_id_conflict", "该记录已属于其他账号")
    if row is None:
        row = Experience(id=item.id, user_id=user.id, kind_id=item.kind_id)
        db.add(row)
    elif (item.updated_at or 0) < (row.updated_at or 0):
        # 客户端提交的是旧版本（补发乱序），保留服务端较新的那份
        return row

    row.kind_id = item.kind_id
    row.values_json = _json_dumps(_clean_values(item.values))
    row.created_at = item.created_at or row.created_at or 0
    row.updated_at = item.updated_at or row.updated_at or 0
    row.server_updated_at = utcnow()
    return row


def _json_dumps(data: dict) -> str:
    import json

    return json.dumps(data, ensure_ascii=False)


@router.get("")
def get_profile(
    user: User = Depends(get_current_user), db: Session = Depends(get_db)
) -> dict:
    """拉取整份档案：一次请求拿全 P2 数据，减少首屏往返"""
    profile = _profile_of(db, user)
    rows = db.scalars(
        select(Experience)
        .where(Experience.user_id == user.id)
        .order_by(Experience.updated_at.desc())
    ).all()
    return {
        "basic": profile.basic_public(),
        "self_evaluation": profile.self_evaluation or "",
        "experiences": [r.to_public() for r in rows],
        "user": user.to_public(),
        "server_time": utcnow().isoformat(),
    }


@router.put("/basic")
def save_basic(
    body: BasicInfoRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    profile = _profile_of(db, user)
    profile.province = body.province.strip()
    profile.city = body.city.strip()
    profile.district = body.district.strip()
    profile.address = body.address.strip()
    profile.work_status = body.work_status.strip()
    profile.marital_status = body.marital_status.strip()
    db.commit()
    db.refresh(profile)
    return {"basic": profile.basic_public(), "updated_at": profile.updated_at.isoformat()}


@router.put("/evaluation")
def save_evaluation(
    body: SelfEvaluationRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    profile = _profile_of(db, user)
    profile.self_evaluation = body.content
    db.commit()
    db.refresh(profile)
    return {
        "self_evaluation": profile.self_evaluation or "",
        "updated_at": profile.updated_at.isoformat(),
    }


@router.post("/experiences")
def upsert_experience(
    body: ExperienceUpsertRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    row = _upsert_experience(db, user, body)
    db.commit()
    db.refresh(row)
    return {"experience": row.to_public()}


@router.post("/experiences/batch")
def upsert_experiences_batch(
    body: ExperienceBatchRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    """批量推送（离线期间攒下的变更一次补发）+ 批量删除

    语义：**先应用新增/更新，再应用删除**（删除优先，符合"离线期间先改后删"）。
    注意必须先 flush：否则同批新增的记录还没进数据库，删除时按 id 查不到，
    会出现"删了却还在"的假成功。
    """
    for item in body.items:
        _upsert_experience(db, user, item)
    db.flush()

    deleted = 0
    for exp_id in body.deleted_ids:
        row = db.get(Experience, exp_id)
        if row is not None and row.user_id == user.id:
            db.delete(row)
            deleted += 1

    db.commit()
    return {"upserted": len(body.items), "deleted": deleted}


@router.delete("/experiences/{exp_id}")
def delete_experience(
    exp_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    row = db.get(Experience, exp_id)
    if row is None or row.user_id != user.id:
        raise api_error(404, "experience_not_found", "记录不存在")
    db.delete(row)
    db.commit()
    return {"ok": True}


@router.put("/identity")
def save_identity(
    body: IdentityRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    """实名认证：只落库脱敏号 + SHA-256 哈希，明文不落盘

    同一证件不得绑定多个账号（按哈希查重）——这是合规与风控的双重要求。
    """
    normalized = body.id_card.strip().upper()
    id_hash = hashlib.sha256(normalized.encode("utf-8")).hexdigest()

    conflict = db.scalar(
        select(User).where(User.id_card_hash == id_hash, User.id != user.id)
    )
    if conflict is not None:
        raise api_error(409, "id_card_taken", "该身份证号已绑定其他账号")

    # 脱敏：保留前 6 位 + 后 4 位
    masked = (
        "%s********%s" % (normalized[:6], normalized[-4:])
        if len(normalized) >= 10
        else normalized[:2] + "****"
    )

    user.id_card_masked = masked
    user.id_card_hash = id_hash
    if body.real_name.strip():
        user.name = body.real_name.strip()
        user.gender = body.gender.strip() or user.gender
        user.birthday = body.birthday.strip() or user.birthday
        user.province = body.province.strip() or user.province
    user.verified_at = utcnow()
    db.commit()
    db.refresh(user)
    return {"user": user.to_public(), "verified_at": user.verified_at.isoformat()}
