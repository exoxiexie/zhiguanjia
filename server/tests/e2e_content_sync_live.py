"""P3 + P4 线上端到端验收（公网 → Nginx → uvicorn → MySQL）

覆盖：说说发布/可见性、收藏、关注、**图片上传并可通过 /uploads/ 访问**、
增量同步（推送 → 游标 → 增量拉取 → 删除同步）、跨账号隔离。
"""

import base64
import json
import sys
import urllib.error
import urllib.request

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://8.137.71.241/api").rstrip("/")
HOST = BASE.rsplit("/api", 1)[0]
PW = "e2eContent123"
PASSED, FAILED = [], []

PNG_1PX = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
)


def check(name, cond, extra=""):
    (PASSED if cond else FAILED).append(name)
    print(("  ✅ " if cond else "  ❌ ") + name + (("  → " + str(extra)[:200]) if extra and not cond else ""))


def call(method, path, body=None, token=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    return _send(req)


def upload(data, token, filename="t.png"):
    boundary = "----zgjE2E"
    body = b""
    body += ("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"%s\"\r\n"
             "Content-Type: image/png\r\n\r\n" % (boundary, filename)).encode()
    body += data
    body += ("\r\n--%s--\r\n" % boundary).encode()
    req = urllib.request.Request(BASE + "/content/upload", data=body, method="POST")
    req.add_header("Content-Type", "multipart/form-data; boundary=" + boundary)
    req.add_header("Authorization", "Bearer " + token)
    return _send(req)


def fetch_status(url):
    """只取状态码，不解析响应体（图片是二进制，不能当文本解码）"""
    try:
        with urllib.request.urlopen(urllib.request.Request(url), timeout=30) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception:  # noqa: BLE001
        return 0


def _send(req):
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            ctype = r.headers.get("Content-Type", "")
            if "json" in ctype:
                try:
                    return r.status, json.loads(raw.decode("utf-8"))
                except Exception:  # noqa: BLE001
                    return r.status, {}
            return r.status, {}
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw[:200]}
    except Exception as e:  # noqa: BLE001
        return 0, {"error": str(e)}


PA, PB = "13900007701", "13900007702"
print("════ P3+P4 线上验收：%s ════" % BASE)

print("── 1. 账号准备 ──")
_, ra = call("POST", "/auth/register", {"phone": PA, "password": PW, "name": "内容A"})
if not ra.get("access_token"):
    _, ra = call("POST", "/auth/login", {"phone": PA, "password": PW})
TA = ra.get("access_token", "")
_, rb = call("POST", "/auth/register", {"phone": PB, "password": PW, "name": "内容B"})
if not rb.get("access_token"):
    _, rb = call("POST", "/auth/login", {"phone": PB, "password": PW})
TB = rb.get("access_token", "")
check("两个账号均拿到令牌", bool(TA) and bool(TB))

print("── 2. 说说发布与可见性 ──")
code, r = call("POST", "/content/posts", {"id": "live-post-1", "title": "线上说说", "content": "正文",
                                         "created_at": 1000, "updated_at": 1000}, TA)
check("发布说说 → 200", code == 200, (code, r))
code, r = call("GET", "/content", token=TB)
check("B 能在全站说说里看到 A 的帖子", any(p["id"] == "live-post-1" for p in r.get("posts", [])), r)
code, r = call("POST", "/content/posts", {"id": "live-post-1", "content": "篡改"}, TB)
check("B 改 A 的说说 → 403", code == 403, (code, r))

print("── 3. 图片上传（含静态访问）──")
code, r = upload(PNG_1PX, TA)
check("上传图片 → 200", code == 200 and r.get("url"), (code, r))
url = r.get("url", "")
code2 = fetch_status(HOST + url)
check("上传的图片可通过 %s 静态访问" % url[:24], code2 == 200, code2)
code, r = upload(b"not an image", TA, filename="x.exe")
check("非图片扩展名被拒 → 400", code == 400, (code, r))

print("── 4. 收藏与关注 ──")
code, r = call("POST", "/content/favorites", {"id": "live-fav-1", "content": "收藏内容", "source": "对话", "created_at": 1}, TA)
check("收藏 → 200", code == 200, (code, r))
code, r = call("GET", "/content", token=TB)
check("B 看不到 A 的收藏（隔离）", r.get("favorites") == [], r.get("favorites"))
code, r = call("PUT", "/content/follows", {"target_phone": PB}, TA)
check("关注 → 200", code == 200, (code, r))
code, r = call("GET", "/content", token=TA)
check("关注列表含 B", PB in r.get("follows", []), r.get("follows"))

print("── 5. 对话同步（推送 + 增量）──")
# 取当前游标作为基线（同一账号重复跑测试时游标不会从 0 开始）
_, baseline = call("GET", "/sync?since=999999999", token=TA)
seq_before = baseline.get("seq", 0)
code, r = call("POST", "/sync/push", {
    "conversations": [{"id": "live-c1", "title": "线上会话", "message_count": 2, "created_at": 1, "updated_at": 1}],
    "messages": [
        {"id": "live-m1", "conversation_id": "live-c1", "role": "user", "content": "问题", "created_at": 1},
        {"id": "live-m2", "conversation_id": "live-c1", "role": "assistant", "content": "回答", "created_at": 2},
    ],
    "memories": [{"id": "live-mem1", "title": "记忆", "content": "内容", "tags": ["求职"], "created_at": 1, "updated_at": 1}],
}, TA)
check("批量推送 → 200", code == 200, (code, r))
seq_after_push = r.get("seq", 0)
check("游标前进 ≥ 4", seq_after_push >= seq_before + 4,
      "before=%s after=%s" % (seq_before, seq_after_push))

code, r = call("GET", "/sync?since=0", token=TA)
check("全量：1 会话 / 2 消息 / 1 记忆", len(r.get("conversations", [])) == 1 and len(r.get("messages", [])) == 2
      and len(r.get("memories", [])) == 1, r)

code, r = call("GET", "/sync?since=%d" % seq_after_push, token=TA)
check("增量（无新变更）为空", r.get("conversations") == [] and r.get("messages") == [], r)

code, r = call("POST", "/sync/push", {"deleted": {"conversations": ["live-c1"]}}, TA)
check("推送删除 → 200", code == 200, (code, r))
code, r = call("GET", "/sync?since=%d" % seq_after_push, token=TA)
check("增量里出现删除标记", any(c["id"] == "live-c1" and c["deleted"] for c in r.get("conversations", [])), r.get("conversations"))

print("── 6. 跨账号隔离 ──")
code, r = call("GET", "/sync?since=0", token=TB)
check("B 拉不到 A 的对话数据", r.get("conversations") == [] and r.get("messages") == [], r)

print()
print("════════════════════════════════")
print("  通过 %d 项，失败 %d 项" % (len(PASSED), len(FAILED)))
for f in FAILED:
    print("    - " + f)
print("════════════════════════════════")
sys.exit(1 if FAILED else 0)
