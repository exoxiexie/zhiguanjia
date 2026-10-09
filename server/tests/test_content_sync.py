"""P3 内容 + P4 对话同步 接口测试（本地 SQLite）

覆盖：
- 内容：发布/修改/删除说说、收藏、关注；作者信息以账号为准；不能改别人的内容
- 内容可见范围：说说全站可见（设计如此），收藏与关注严格按账号隔离
- 同步：增量游标单调递增、since 过滤、消息不可变、旧版本不覆盖、
        删除可同步、跨账号隔离、has_more
"""

import os
import sys
import tempfile

os.environ["ZGJ_DATABASE_URL"] = "sqlite:///" + os.path.join(tempfile.mkdtemp(), "t.db")
os.environ["ZGJ_JWT_SECRET"] = "content-sync-test"
os.environ["ZGJ_SECRETS_FILE"] = os.path.join(tempfile.mkdtemp(), "none.json")
os.environ["ZGJ_ENV"] = "test"
os.environ["ZGJ_UPLOAD_DIR"] = tempfile.mkdtemp()

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402

_client = TestClient(app)
_client.__enter__()

PASSED, FAILED = [], []


def check(name, cond, extra=""):
    (PASSED if cond else FAILED).append(name)
    print(("  ✅ " if cond else "  ❌ ") + name + (("  → " + str(extra)[:200]) if extra and not cond else ""))


def register(phone, name):
    r = _client.post("/auth/register", json={"phone": phone, "password": "test123456", "name": name})
    assert r.status_code == 201, r.text
    return r.json()["access_token"]


def h(t):
    return {"Authorization": "Bearer " + t}


A = register("13800001111", "作者A")
B = register("13800002222", "作者B")

print("── 1. 鉴权 ──")
check("未登录 GET /content → 401", _client.get("/content").status_code == 401)
check("未登录 GET /sync → 401", _client.get("/sync").status_code == 401)
check("未登录 POST /sync/push → 401", _client.post("/sync/push", json={}).status_code == 401)

print("── 2. 说说：发布 / 修改 / 删除 ──")
r = _client.post("/content/posts", headers=h(A), json={
    "id": "post-1", "title": "我的第一篇", "content": "正文内容",
    "images": ["/uploads/x/a.jpg"], "created_at": 1000, "updated_at": 1000,
    "author_phone": "19900000000", "author_name": "伪造作者"})
check("发布说说 → 200", r.status_code == 200, r.text)
post = r.json()["post"]
check("作者以账号为准（不采信客户端伪造）", post["author_phone"] == "13800001111" and post["author_name"] == "作者A", post)
check("图片地址保留", post["images"] == ["/uploads/x/a.jpg"])

r = _client.post("/content/posts", headers=h(B), json={"id": "post-1", "content": "篡改"})
check("B 修改 A 的说说 → 403", r.status_code == 403, r.text)

r = _client.get("/content", headers=h(B))
check("说说全站可见（B 能看到 A 的）", any(p["id"] == "post-1" for p in r.json()["posts"]), r.text)

r = _client.post("/content/posts", headers=h(A), json={"id": "post-1", "title": "改后标题", "content": "改后正文", "updated_at": 2000})
check("作者本人可修改", r.status_code == 200 and r.json()["post"]["title"] == "改后标题", r.text)

r = _client.delete("/content/posts/post-1", headers=h(B))
check("B 删除 A 的说说 → 404", r.status_code == 404, r.text)

print("── 3. 收藏（严格按账号隔离）──")
r = _client.post("/content/favorites", headers=h(A), json={"id": "fav-1", "content": "收藏内容", "source": "对话", "created_at": 1000})
check("A 收藏 → 200", r.status_code == 200, r.text)
r = _client.get("/content", headers=h(A))
check("A 能看到自己的收藏", len(r.json()["favorites"]) == 1, r.text)
r = _client.get("/content", headers=h(B))
check("B 看不到 A 的收藏", r.json()["favorites"] == [], r.text)
r = _client.delete("/content/favorites/fav-1", headers=h(B))
check("B 删除 A 的收藏 → 404", r.status_code == 404, r.text)

print("── 4. 关注 ──")
r = _client.put("/content/follows", headers=h(A), json={"target_phone": "13800002222"})
check("A 关注 B → 200", r.status_code == 200, r.text)
r = _client.get("/content", headers=h(A))
check("A 的关注列表含 B", r.json()["follows"] == ["13800002222"], r.text)
r = _client.put("/content/follows", headers=h(A), json={"target_phone": "13800001111"})
check("不能关注自己 → 400", r.status_code == 400, r.text)
r = _client.delete("/content/follows/13800002222", headers=h(A))
check("取关 → 200", r.status_code == 200 and r.json()["following"] is False, r.text)
r = _client.get("/content", headers=h(A))
check("取关后列表为空", r.json()["follows"] == [], r.text)

print("── 5. 同步：推送与增量游标 ──")
r = _client.post("/sync/push", headers=h(A), json={
    "conversations": [{"id": "c1", "title": "会话1", "created_at": 1, "updated_at": 1}],
    "messages": [
        {"id": "m1", "conversation_id": "c1", "role": "user", "content": "你好", "created_at": 1},
        {"id": "m2", "conversation_id": "c1", "role": "assistant", "content": "你好呀", "created_at": 2},
    ],
    "memories": [{"id": "mem1", "title": "记忆1", "content": "内容", "tags": ["求职"], "created_at": 1, "updated_at": 1}],
    "search_items": [{"id": "s1", "title": "搜索1", "content": "沉淀", "search_query": "AI 岗位", "tags": ["搜索"], "created_at": 1, "updated_at": 1}],
})
check("批量推送 → 200", r.status_code == 200, r.text)
seq1 = r.json()["seq"]
check("推送后游标前进", seq1 == 5, seq1)
check("applied 统计正确", r.json()["applied"]["messages"] == 2, r.json()["applied"])

r = _client.get("/sync?since=0", headers=h(A))
body = r.json()
check("全量拉取：1 会话", len(body["conversations"]) == 1, body)
check("全量拉取：2 消息", len(body["messages"]) == 2, body)
check("全量拉取：1 记忆 + 1 搜索", len(body["memories"]) == 1 and len(body["search_items"]) == 1, body)
check("服务端游标 = 5", body["seq"] == 5, body)

r = _client.post("/sync/push", headers=h(A), json={
    "conversations": [{"id": "c2", "title": "会话2", "created_at": 3, "updated_at": 3}]})
seq2 = r.json()["seq"]
check("第二次推送游标继续递增", seq2 == 6, seq2)

r = _client.get("/sync?since=%d" % seq1, headers=h(A))
body = r.json()
check("增量只返回新会话", len(body["conversations"]) == 1 and body["conversations"][0]["id"] == "c2", body)
check("增量不含旧消息", body["messages"] == [], body)

print("── 6. 同步：消息不可变 + 旧版本不覆盖 ──")
_client.post("/sync/push", headers=h(A), json={
    "messages": [{"id": "m1", "conversation_id": "c1", "role": "user", "content": "被篡改", "created_at": 9}]})
r = _client.get("/sync?since=0", headers=h(A))
m1 = [m for m in r.json()["messages"] if m["id"] == "m1"][0]
check("已存在的消息不被改写", m1["content"] == "你好", m1)

_client.post("/sync/push", headers=h(A), json={
    "conversations": [{"id": "c2", "title": "过期补发", "created_at": 3, "updated_at": 1}]})
r = _client.get("/sync?since=0", headers=h(A))
c2 = [c for c in r.json()["conversations"] if c["id"] == "c2"][0]
check("旧版本 updated_at 不覆盖新标题", c2["title"] == "会话2", c2)

print("── 7. 同步：删除可同步 ──")
r = _client.post("/sync/push", headers=h(A), json={"deleted": {"conversations": ["c1"]}})
check("推送删除 → 200", r.status_code == 200, r.text)
since_before_delete = r.json()["seq"] - 1
r = _client.get("/sync?since=%d" % since_before_delete, headers=h(A))
check("增量里出现删除标记", any(c["id"] == "c1" and c["deleted"] for c in r.json()["conversations"]), r.json()["conversations"])

print("── 8. 同步：跨账号隔离 ──")
r = _client.get("/sync?since=0", headers=h(B))
b = r.json()
check("B 拉不到 A 的会话", b["conversations"] == [], b)
check("B 拉不到 A 的消息", b["messages"] == [], b)
r = _client.post("/sync/push", headers=h(B), json={"deleted": {"conversations": ["c2"]}})
r = _client.get("/sync?since=0", headers=h(A))
c2 = [c for c in r.json()["conversations"] if c["id"] == "c2"][0]
check("B 无法删除 A 的会话", c2["deleted"] is False, c2)

print("── 9. has_more ──")
r = _client.get("/sync?since=0&limit=1", headers=h(A))
check("limit=1 时 has_more=True", r.json()["has_more"] is True, r.json().get("has_more"))

print()
print("════════════════════════════════")
print("  通过 %d 项，失败 %d 项" % (len(PASSED), len(FAILED)))
for f in FAILED:
    print("    - " + f)
print("════════════════════════════════")
_client.__exit__(None, None, None)
sys.exit(1 if FAILED else 0)
