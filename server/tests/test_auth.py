"""账号体系接口测试（本地 SQLite 运行，不碰生产数据库）

运行：python tests/test_auth.py
"""

import os
import sys
import tempfile

# ── 测试环境：SQLite + 临时密钥，绝不能读到生产配置 ──
_dbfile = os.path.join(tempfile.mkdtemp(), "test.db")
os.environ["ZGJ_DATABASE_URL"] = "sqlite:///" + _dbfile
os.environ["ZGJ_JWT_SECRET"] = "unit-test-secret-not-used-in-prod"
os.environ["ZGJ_SECRETS_FILE"] = os.path.join(tempfile.mkdtemp(), "none.json")
os.environ["ZGJ_ENV"] = "test"

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402

_client = TestClient(app)
_client.__enter__()  # 触发 FastAPI startup 生命周期（建表）——等价于生产 uvicorn 启动
c = _client

PASSED, FAILED = [], []


def check(name, cond, extra=""):
    (PASSED if cond else FAILED).append(name)
    print(("  ✅ " if cond else "  ❌ ") + name + (("  → " + str(extra)) if extra and not cond else ""))


PHONE = "13800001111"
PW = "test123456"
NAME = "测试用户"

print("── 1. 健康检查 ──")
r = c.get("/health")
check("health 返回 200", r.status_code == 200, r.text)
check("health ok=true", r.json().get("ok") is True)

print("── 2. 参数校验 ──")
r = c.post("/auth/register", json={"phone": "123", "password": PW, "name": NAME})
check("非法手机号 → 422", r.status_code == 422, r.text)
check("错误结构含 error.code", r.json().get("error", {}).get("code") == "invalid_request", r.text)
r = c.post("/auth/register", json={"phone": PHONE, "password": "123", "name": NAME})
check("密码过短 → 422", r.status_code == 422, r.text)
r = c.post("/auth/register", json={"phone": PHONE, "password": PW, "name": "  "})
check("空姓名 → 422", r.status_code == 422, r.text)

print("── 3. 注册 ──")
r = c.post("/auth/register", json={"phone": PHONE, "password": PW, "name": NAME,
                                   "device_id": "dev-1", "platform": "android"})
check("注册成功 → 201", r.status_code == 201, r.text)
body = r.json()
check("返回 access_token", bool(body.get("access_token")))
check("返回 refresh_token", bool(body.get("refresh_token")))
check("token_type=Bearer", body.get("token_type") == "Bearer")
check("返回用户资料且手机号一致", body.get("user", {}).get("phone") == PHONE)
check("响应不含密码哈希", "password" not in str(body).lower(), str(body)[:120])

register_refresh = body.get("refresh_token", "")
access = body.get("access_token", "")

r = c.post("/auth/register", json={"phone": PHONE, "password": PW, "name": NAME})
check("重复手机号 → 409", r.status_code == 409, r.text)
check("409 code=phone_taken", r.json().get("error", {}).get("code") == "phone_taken", r.text)

print("── 4. 登录 ──")
r = c.post("/auth/login", json={"phone": PHONE, "password": "wrong-password"})
check("密码错误 → 401", r.status_code == 401, r.text)
check("401 code=bad_credentials", r.json().get("error", {}).get("code") == "bad_credentials", r.text)
r = c.post("/auth/login", json={"phone": "13900002222", "password": PW})
check("账号不存在 → 401（不泄漏账号是否存在）", r.status_code == 401, r.text)
r = c.post("/auth/login", json={"phone": PHONE, "password": PW, "device_id": "dev-2"})
check("登录成功 → 200", r.status_code == 200, r.text)
login_body = r.json()
check("登录返回令牌", bool(login_body.get("access_token")) and bool(login_body.get("refresh_token")))

print("── 5. 当前用户 /me ──")
r = c.get("/me", headers={"Authorization": "Bearer " + access})
check("/me 带令牌 → 200", r.status_code == 200, r.text)
check("/me 手机号正确", r.json().get("phone") == PHONE, r.text)
check("/me 不含密码字段", "password" not in str(r.json()).lower())
r = c.get("/me")
check("/me 无令牌 → 401", r.status_code == 401, r.text)
r = c.get("/me", headers={"Authorization": "Bearer not-a-real-token"})
check("/me 伪造令牌 → 401", r.status_code == 401, r.text)

print("── 6. 刷新令牌（一次性轮换）──")
r = c.post("/auth/refresh", json={"refresh_token": login_body["refresh_token"]})
check("刷新成功 → 200", r.status_code == 200, r.text)
new_refresh = r.json().get("refresh_token", "")
check("返回新的 refresh_token", bool(new_refresh) and new_refresh != login_body["refresh_token"])
r = c.post("/auth/refresh", json={"refresh_token": login_body["refresh_token"]})
check("旧 refresh_token 已失效 → 401", r.status_code == 401, r.text)
r = c.post("/auth/refresh", json={"refresh_token": "garbage"})
check("伪造 refresh_token → 401", r.status_code == 401, r.text)

print("── 7. 退出登录 ──")
r = c.post("/auth/logout", json={"refresh_token": new_refresh, "all_devices": True},
           headers={"Authorization": "Bearer " + access})
check("退出成功 → 200", r.status_code == 200, r.text)
check("吊销数量 >= 1", r.json().get("revoked", 0) >= 1, r.text)
r = c.post("/auth/refresh", json={"refresh_token": new_refresh})
check("退出后 refresh 失效 → 401", r.status_code == 401, r.text)

print("── 8. 登录限流（防爆破）──")
codes = []
for _ in range(12):
    rr = c.post("/auth/login", json={"phone": "13700003333", "password": "bad"})
    codes.append(rr.status_code)
check("连续失败登录触发 429", 429 in codes, "状态码序列: %s" % codes)

print()
print("════════════════════════════════")
print("  通过 %d 项，失败 %d 项" % (len(PASSED), len(FAILED)))
if FAILED:
    print("  失败项：")
    for f in FAILED:
        print("    - " + f)
print("════════════════════════════════")
_client.__exit__(None, None, None)
sys.exit(1 if FAILED else 0)
