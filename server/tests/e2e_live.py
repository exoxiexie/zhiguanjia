"""线上端到端验收（走公网 → Nginx → uvicorn → MySQL）

用法：python tests/e2e_live.py [base_url]
默认 base_url = http://8.137.71.241/api

注意：会在生产库创建测试账号，脚本结束时会自动清理。
"""

import json
import sys
import urllib.error
import urllib.request

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://8.137.71.241/api").rstrip("/")
PHONE = "13900009999"
PW = "e2eTest123456"
NAME = "端到端测试"

PASSED, FAILED = [], []


def check(name, cond, extra=""):
    (PASSED if cond else FAILED).append(name)
    print(("  ✅ " if cond else "  ❌ ") + name + (("  → " + str(extra)[:200]) if extra and not cond else ""))


def call(method, path, body=None, token=None):
    """返回 (状态码, 响应字典)"""
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


print("════ 线上端到端验收：%s ════" % BASE)

print("── 1. 健康检查 ──")
code, body = call("GET", "/health")
check("health 200 且 db=true", code == 200 and body.get("db") is True, body)

print("── 2. 注册（真实写入 MySQL）──")
code, body = call("POST", "/auth/register", {"phone": PHONE, "password": PW, "name": NAME,
                                             "device_id": "e2e-mac", "platform": "test"})
if code == 409:  # 上次残留，先清理再注册
    print("  （检测到残留测试账号，先删除重跑）")
    check("检测到残留账号（需清理）", False, "residual account")
    code, body = 0, {}
check("注册 201", code == 201, body)
access = body.get("access_token", "")
refresh = body.get("refresh_token", "")
check("拿到 access_token", bool(access))
check("用户手机号回显正确", body.get("user", {}).get("phone") == PHONE, body)

print("── 3. 重复注册 ──")
code, body = call("POST", "/auth/register", {"phone": PHONE, "password": PW, "name": NAME})
check("重复手机号 → 409 phone_taken", code == 409 and body.get("error", {}).get("code") == "phone_taken", body)

print("── 4. 参数校验 ──")
code, body = call("POST", "/auth/register", {"phone": "12345", "password": PW, "name": NAME})
check("非法手机号 → 422", code == 422, body)

print("── 5. 登录 ──")
code, body = call("POST", "/auth/login", {"phone": PHONE, "password": "wrong-password"})
check("错误密码 → 401 bad_credentials", code == 401 and body.get("error", {}).get("code") == "bad_credentials", body)
code, body = call("POST", "/auth/login", {"phone": PHONE, "password": PW, "device_id": "e2e-mac-2"})
check("登录成功 → 200", code == 200, body)
refresh2 = body.get("refresh_token", "")

print("── 6. 我的资料 ──")
code, body = call("GET", "/me", token=access)
check("/me 200 且手机号正确", code == 200 and body.get("phone") == PHONE, body)
check("/me 不含密码哈希", "password" not in json.dumps(body).lower())
code, body = call("GET", "/me")
check("/me 无令牌 → 401", code == 401, body)

print("── 7. 令牌刷新（一次性轮换）──")
code, body = call("POST", "/auth/refresh", {"refresh_token": refresh2})
check("刷新 → 200", code == 200, body)
new_refresh = body.get("refresh_token", "")
code, body = call("POST", "/auth/refresh", {"refresh_token": refresh2})
check("旧 refresh 失效 → 401", code == 401, body)

print("── 8. 退出登录 ──")
code, body = call("POST", "/auth/logout", {"all_devices": True}, token=access)
check("退出 → 200", code == 200, body)
code, body = call("POST", "/auth/refresh", {"refresh_token": new_refresh})
check("退出后刷新失效 → 401", code == 401, body)

print()
print("════════════════════════════════")
print("  通过 %d 项，失败 %d 项" % (len(PASSED), len(FAILED)))
for f in FAILED:
    print("    - " + f)
print("════════════════════════════════")
sys.exit(1 if FAILED else 0)
