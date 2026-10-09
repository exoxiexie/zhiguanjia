"""P2 线上端到端验收：档案云化（走公网 → Nginx → uvicorn → MySQL）

核心场景：**同一账号在两台设备上看到同一份档案**（换手机不丢档案）。
附带验证跨账号隔离。测试结束会自动清理测试账号。
"""

import json
import sys
import urllib.error
import urllib.request

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://8.137.71.241/api").rstrip("/")
PW = "e2eProfile123"
PASSED, FAILED = [], []


def check(name, cond, extra=""):
    (PASSED if cond else FAILED).append(name)
    print(("  ✅ " if cond else "  ❌ ") + name + (("  → " + str(extra)[:220]) if extra and not cond else ""))


def call(method, path, body=None, token=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw.strip().startswith("{") else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw[:200]}
    except Exception as e:  # noqa: BLE001
        return 0, {"error": str(e)}


PHONE_A, PHONE_B = "13900008801", "13900008802"

print("════ P2 线上验收：%s ════" % BASE)

print("── 1. 账号准备 ──")
code, a = call("POST", "/auth/register", {"phone": PHONE_A, "password": PW, "name": "档案A", "device_id": "dev-a"})
check("账号 A 注册", code in (201, 409), (code, a))
if code == 409:
    code, a = call("POST", "/auth/login", {"phone": PHONE_A, "password": PW, "device_id": "dev-a"})
    check("账号 A 登录（已存在）", code == 200, a)
token_a = a.get("access_token", "")
check("拿到 A 的令牌", bool(token_a))

# 同账号换设备：device_id 不同 = 第二台手机
code, a2 = call("POST", "/auth/login", {"phone": PHONE_A, "password": PW, "device_id": "dev-b"})
check("同账号在第二台设备登录", code == 200, a2)
token_a2 = a2.get("access_token", "")

code, b = call("POST", "/auth/register", {"phone": PHONE_B, "password": PW, "name": "档案B", "device_id": "dev-c"})
check("账号 B 注册", code in (201, 409), (code, b))
token_b = b.get("access_token", "")
if not token_b:
    code, b = call("POST", "/auth/login", {"phone": PHONE_B, "password": PW, "device_id": "dev-c"})
    token_b = b.get("access_token", "")

print("── 2. 设备一写入档案 ──")
code, r = call("PUT", "/profile/basic", {
    "province": "四川省", "city": "成都市", "district": "高新区",
    "address": "天府大道 1 号", "work_status": "在职", "marital_status": "未婚"}, token_a)
check("保存基础信息", code == 200, (code, r))
code, r = call("PUT", "/profile/evaluation", {"content": "十年产品经验，擅长从 0 到 1。"}, token_a)
check("保存自我评价", code == 200, (code, r))
code, r = call("POST", "/profile/experiences", {
    "id": "e2e-exp-1", "kind_id": "work",
    "values": {"company": "某某科技", "title": "产品经理", "start": "2020-09", "end": ""},
    "created_at": 1000, "updated_at": 1000}, token_a)
check("新增一条经历", code == 200, (code, r))

print("── 3. 设备二读取（核心：换手机档案一致）──")
code, r = call("GET", "/profile", token=token_a2)
check("设备二 GET /profile → 200", code == 200, (code, r))
basic = r.get("basic", {})
check("设备二看到同一份基础信息", basic.get("province") == "四川省" and basic.get("address") == "天府大道 1 号", basic)
check("设备二看到同一条自我评价", "十年产品经验" in (r.get("self_evaluation") or ""), r.get("self_evaluation"))
exps = r.get("experiences", [])
check("设备二看到同一份经历", len(exps) == 1 and exps[0]["values"].get("company") == "某某科技", exps)

print("── 4. 设备一修改，设备二刷新可见 ──")
code, r = call("PUT", "/profile/basic", {
    "province": "四川省", "city": "成都市", "district": "高新区",
    "address": "天府大道 2 号（改）", "work_status": "在职", "marital_status": "未婚"}, token_a)
check("设备一修改地址", code == 200, (code, r))
code, r = call("GET", "/profile", token=token_a2)
check("设备二刷新看到新地址", r.get("basic", {}).get("address") == "天府大道 2 号（改）", r.get("basic"))

print("── 5. 删除与批量补发 ──")
code, r = call("POST", "/profile/experiences/batch", {
    "items": [{"id": "e2e-exp-2", "kind_id": "education",
               "values": {"school": "某大学"}, "created_at": 2, "updated_at": 2}],
    "deleted_ids": ["e2e-exp-1"]}, token_a)
check("批量推送 + 删除", code == 200 and r.get("deleted") == 1, (code, r))
code, r = call("GET", "/profile", token=token_a)
ids = [e["id"] for e in r.get("experiences", [])]
check("删除生效、新增保留", "e2e-exp-1" not in ids and "e2e-exp-2" in ids, ids)

print("── 6. 跨账号隔离 ──")
code, r = call("GET", "/profile", token=token_b)
check("B 看到的是空档案", r.get("basic", {}).get("province") == "" and r.get("experiences") == [], r)
code, r = call("DELETE", "/profile/experiences/e2e-exp-2", token=token_b)
check("B 删 A 的经历 → 404", code == 404, (code, r))

print("── 7. 令牌失效 ──")
code, r = call("GET", "/profile")
check("无令牌 → 401", code == 401, (code, r))

print()
print("════════════════════════════════")
print("  通过 %d 项，失败 %d 项" % (len(PASSED), len(FAILED)))
for f in FAILED:
    print("    - " + f)
print("════════════════════════════════")
sys.exit(1 if FAILED else 0)
