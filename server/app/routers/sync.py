"""对话同步接口（P4）：本地优先 + 增量同步（游标）

设计（《商业版改造方案》第五节 C 类「对话类」）：
- **本地优先**：App 端始终先写本地，离线可用；联网后经 outbox 补发到 `POST /sync/push`
- **增量拉取**：`GET /sync?since=<seq>` 只返回 `seq > since` 的变更（含软删除），
  客户端只需保存一个游标即可跨设备保持一致
- **游标来源**：`user_sync_state.last_seq` 按用户统一分配，保证同一用户内严格
  单调递增、四张表可直接合并比较（不能用各表自增主键：跨表不可比且有空洞）
"""

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..deps import get_current_user, get_db
from ..models import (
    Conversation,
    Memory,
    Message,
    SearchItem,
    User,
    UserSyncState,
    utcnow,
)
from ..schemas import SyncPushRequest

router = APIRouter(prefix="/sync", tags=["sync"])


def _alloc_seqs(db: Session, user_id: str, count: int) -> int:
    """为用户分配一段连续的 seq，返回起始值（首次返回 1）"""
    if count <= 0:
        return 0
    state = db.get(UserSyncState, user_id, with_for_update=True)
    if state is None:
        state = UserSyncState(user_id=user_id, last_seq=0)
        db.add(state)
        db.flush()
    start = (state.last_seq or 0) + 1
    state.last_seq = start + count - 1
    db.flush()
    return start


def _current_seq(db: Session, user_id: str) -> int:
    state = db.get(UserSyncState, user_id)
    return state.last_seq if state is not None else 0


@router.get("")
def pull(
    since: int = 0,
    limit: int = 500,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    """增量拉取：[since] 之后的全部变更（含已删除标记）"""
    limit = max(1, min(limit, 2000))

    def _fetch(model):
        return db.scalars(
            select(model)
            .where(model.user_id == user.id, model.seq > since)
            .order_by(model.seq)
            .limit(limit)
        ).all()

    conversations = _fetch(Conversation)
    messages = _fetch(Message)
    memories = _fetch(Memory)
    search_items = _fetch(SearchItem)

    total = len(conversations) + len(messages) + len(memories) + len(search_items)
    return {
        "seq": _current_seq(db, user.id),
        "has_more": total >= limit,
        "conversations": [r.to_public() for r in conversations],
        "messages": [r.to_public() for r in messages],
        "memories": [r.to_public() for r in memories],
        "search_items": [r.to_public() for r in search_items],
    }


@router.post("/push")
def push(
    body: SyncPushRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    """批量推送本地变更（offline outbox 补发）

    合并规则：
    - 会话 / 记忆 / 搜索沉淀：按 `updated_at` 做 last-write-wins（旧版本不覆盖新版本）
    - 消息：**只增不改**（消息一旦发出即不可变），已存在则跳过，避免重发改写历史
    - 删除：软删除并分配 seq，保证"这台删了那台也会删"
    """
    applied = {"conversations": 0, "messages": 0, "memories": 0,
               "search_items": 0, "deleted": 0}

    # ── 会话 ──
    if body.conversations:
        seq = _alloc_seqs(db, user.id, len(body.conversations))
        for offset, item in enumerate(body.conversations):
            row = db.get(Conversation, item.id)
            if row is None:
                row = Conversation(id=item.id, user_id=user.id)
                db.add(row)
            elif row.user_id != user.id:
                continue
            elif (item.updated_at or 0) < (row.updated_at or 0):
                continue  # 补发的旧版本，保留服务端较新的
            row.title = item.title
            row.business_tag = item.business_tag
            row.message_count = item.message_count
            row.last_extracted_message_id = item.last_extracted_message_id
            row.created_at = item.created_at or row.created_at or 0
            row.updated_at = item.updated_at or row.updated_at or 0
            row.deleted_at = None
            row.seq = seq + offset
            applied["conversations"] += 1
        db.flush()

    # ── 消息（只增不改）──
    if body.messages:
        seq = _alloc_seqs(db, user.id, len(body.messages))
        for offset, item in enumerate(body.messages):
            if db.get(Message, item.id) is not None:
                continue  # 已存在：消息不可变，跳过
            db.add(Message(
                id=item.id,
                user_id=user.id,
                conversation_id=item.conversation_id,
                role=item.role,
                content=item.content,
                attachment_type=item.attachment_type,
                attachment_path=item.attachment_path,
                created_at=item.created_at,
                seq=seq + offset,
            ))
            applied["messages"] += 1
        db.flush()

        # 校正受影响会话的消息数：客户端计数可能滞后（只增消息、不同步计数），
        # 以服务端实际条数为准，避免新设备拉到的会话显示成 "0 条消息"
        for cid in {m.conversation_id for m in body.messages}:
            row = db.get(Conversation, cid)
            if row is not None and row.user_id == user.id:
                count = db.scalar(
                    select(func.count())
                    .select_from(Message)
                    .where(
                        Message.conversation_id == cid,
                        Message.deleted_at.is_(None),
                    )
                )
                row.message_count = int(count or 0)
        db.flush()

    # ── 记忆 ──
    if body.memories:
        import json as _json

        seq = _alloc_seqs(db, user.id, len(body.memories))
        for offset, item in enumerate(body.memories):
            row = db.get(Memory, item.id)
            if row is None:
                row = Memory(id=item.id, user_id=user.id)
                db.add(row)
            elif row.user_id != user.id or (item.updated_at or 0) < (row.updated_at or 0):
                continue
            row.title = item.title
            row.content = item.content
            row.tags_json = _json.dumps(item.tags or [], ensure_ascii=False)
            row.weight = item.weight
            row.category = item.category
            row.source = item.source
            row.created_at = item.created_at or row.created_at or 0
            row.updated_at = item.updated_at or row.updated_at or 0
            row.deleted_at = None
            row.seq = seq + offset
            applied["memories"] += 1
        db.flush()

    # ── 搜索沉淀 ──
    if body.search_items:
        import json as _json

        seq = _alloc_seqs(db, user.id, len(body.search_items))
        for offset, item in enumerate(body.search_items):
            row = db.get(SearchItem, item.id)
            if row is None:
                row = SearchItem(id=item.id, user_id=user.id)
                db.add(row)
            elif row.user_id != user.id or (item.updated_at or 0) < (row.updated_at or 0):
                continue
            row.title = item.title
            row.content = item.content
            row.search_query = item.search_query
            row.source = item.source
            row.category = item.category
            row.weight = item.weight
            row.tags_json = _json.dumps(item.tags or [], ensure_ascii=False)
            row.sources_json = _json.dumps(item.sources or [], ensure_ascii=False)
            row.created_at = item.created_at or row.created_at or 0
            row.updated_at = item.updated_at or row.updated_at or 0
            row.deleted_at = None
            row.seq = seq + offset
            applied["search_items"] += 1
        db.flush()

    # ── 删除（软删除 + 分配 seq，保证能同步到其他设备）──
    deletions = (
        (Conversation, body.deleted.conversations),
        (Message, body.deleted.messages),
        (Memory, body.deleted.memories),
        (SearchItem, body.deleted.search_items),
    )
    total_deleted = sum(len(ids) for _, ids in deletions)
    if total_deleted:
        seq = _alloc_seqs(db, user.id, total_deleted)
        offset = 0
        for model, ids in deletions:
            for record_id in ids:
                row = db.get(model, record_id)
                if row is not None and row.user_id == user.id:
                    row.deleted_at = utcnow()
                    row.seq = seq + offset
                    offset += 1
                    applied["deleted"] += 1
        db.flush()

    db.commit()
    return {"ok": True, "applied": applied, "seq": _current_seq(db, user.id)}
