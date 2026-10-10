"""后台「用户管理」测试

重点：停用/重置密码要**立刻生效**（不能等令牌自然过期），且不能把自己锁在门外。
"""

import os
import sys
import tempfile

os.environ["ZGJ_DATABASE_URL"] = "sqlite:///" + os.path.join(tempfile.mkdtemp(), "t.db")
os.environ["ZGJ_JWT_SECRET"] = "users-test-secret"
os.environ["ZGJ_SECRETS_FILE"] = os.path.join(tempfile.mkdtemp(), "none.json")
os.environ["ZGJ_ENV"] = "test"
os.environ["ZGJ_UPLOAD_DIR"] = tempfile.mkdtemp()
os.environ["ZGJ_SITE_DIR"] = tempfile.mkdtemp()

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import select  # noqa: E402

from app.db import SessionLocal  # noqa: E402
from app.main import app  # noqa: E402
from app.models import User  # noqa: E402

_client = TestClient(app)
_client.__enter__()
PASSED, FAILED = [], []


def check(name, cond, extra=""):
    (PASSED if cond else FAILED).append(name)
    print(("  ✅ " if cond else "  ❌ ") + name + (("  → " + str(extra)[:200]) if extra and not cond else ""))


def register(phone, name):
    r = _client.post("/auth/register",
                     json={"phone": phone, "password": "test123456", "name": name})
    assert r.status_code == 201, r.text
    return r.json()["access_token"]


def h(t):
    return {"Authorization": "Bearer " + t}


BOSS = register("13800006001", "老板")
A_TOKEN = register("13800006002", "客服")
U_TOKEN = register("13800006003", "张三")
db = SessionLocal()
try:
    boss = db.scalar(select(User).where(User.phone == "13800006001"))
    boss.is_admin = 1
    db.add(boss)
    db.commit()
    BOSS_ID = boss.id
    UID = db.scalar(select(User.id).where(User.phone == "13800006003"))
finally:
    db.close()

print("── 1. 权限 ──")
check("非管理员看用户列表 → 403", _client.get("/admin/users", headers=h(U_TOKEN)).status_code == 403)

print("── 2. 列表与检索 ──")
r = _client.get("/admin/users", headers=h(BOSS))
check("列表 → 200", r.status_code == 200, r.text[:200])
d = r.json()
check("至少 3 个用户", d["total"] >= 3, d["total"])
one = [i for i in d["items"] if i["phone"] == "13800006003"][0]
check("带设备与内容量概览", "devices" in one and "messages" in one, one)
check("显示实名状态", "verified" in one, one)
check("按手机号检索", [i["phone"] for i in
                    _client.get("/admin/users?q=1380000600", headers=h(BOSS)).json()["items"]] != [])
check("按姓名检索", any(i["name"] == "张三" for i in
                    _client.get("/admin/users?q=张三", headers=h(BOSS)).json()["items"]))
check("检索无结果", _client.get("/admin/users?q=不存在的名字", headers=h(BOSS)).json()["total"] == 0)

print("── 3. 详情 ──")
r = _client.get(f"/admin/users/{UID}", headers=h(BOSS))
check("详情 → 200", r.status_code == 200, r.text[:200])
check("详情含设备列表字段", "device_list" in r.json(), list(r.json()))
check("不存在的用户 → 404", _client.get("/admin/users/nope", headers=h(BOSS)).status_code == 404)

print("── 4. 停用（必须立刻生效）──")
check("停用未填原因 → 400",
      _client.post(f"/admin/users/{UID}/status", headers=h(BOSS),
                   json={"status": 0}).status_code == 400)
r = _client.post(f"/admin/users/{UID}/status", headers=h(BOSS),
                 json={"status": 0, "reason": "发布违规内容"})
check("停用 → 200", r.status_code == 200, r.text[:200])
check("状态已变", r.json()["user"]["status"] == 0, r.json()["user"])
check("记录了停用原因", r.json()["user"]["banned_reason"] == "发布违规内容", r.json()["user"])

login = _client.post("/auth/login", json={"phone": "13800006003", "password": "test123456"})
check("被封禁用户无法登录 → 403", login.status_code == 403, login.status_code)
check("登录提示带停用原因", "发布违规内容" in login.text, login.text)
_me = _client.get("/me", headers=h(U_TOKEN))
check("**停用后旧令牌立即被拒**（不用等过期）", _me.status_code == 403, _me.status_code)
check("旧令牌被拒时也说明原因", "发布违规内容" in _me.text, _me.text)
check("only_banned 筛选能查到",
      any(i["phone"] == "13800006003" for i in
          _client.get("/admin/users?only_banned=true", headers=h(BOSS)).json()["items"]))

print("── 5. 恢复 ──")
r = _client.post(f"/admin/users/{UID}/status", headers=h(BOSS), json={"status": 1})
check("恢复 → 200", r.status_code == 200, r.text[:200])
check("恢复后可以登录",
      _client.post("/auth/login", json={"phone": "13800006003",
                                        "password": "test123456"}).status_code == 200)
check("恢复后原因被清空", r.json()["user"]["banned_reason"] == "", r.json()["user"])

print("── 6. 管理员开关与防自锁 ──")
r = _client.post(f"/admin/users/{UID}/admin", headers=h(BOSS), json={"is_admin": True})
check("设为管理员 → 200", r.status_code == 200 and r.json()["user"]["is_admin"] is True, r.text[:200])
check("新管理员可访问后台接口",
      _client.get("/admin/users", headers=h(_client.post(
          "/auth/login", json={"phone": "13800006003", "password": "test123456"}
      ).json()["access_token"])).status_code == 200)
check("取消管理员 → 200",
      _client.post(f"/admin/users/{UID}/admin", headers=h(BOSS),
                   json={"is_admin": False}).json()["user"]["is_admin"] is False)
check("**不能取消自己的管理员**（防自锁）",
      _client.post(f"/admin/users/{BOSS_ID}/admin", headers=h(BOSS),
                   json={"is_admin": False}).status_code == 400)
check("**不能停用自己**",
      _client.post(f"/admin/users/{BOSS_ID}/status", headers=h(BOSS),
                   json={"status": 0, "reason": "手滑"}).status_code == 400)

print("── 7. 重置密码 ──")
r = _client.post(f"/admin/users/{UID}/reset-password", headers=h(BOSS))
check("重置 → 200", r.status_code == 200, r.text[:200])
temp = r.json()["temp_password"]
check("返回一次性临时密码", len(temp) >= 6, temp)
check("旧密码失效",
      _client.post("/auth/login", json={"phone": "13800006003",
                                        "password": "test123456"}).status_code == 401)
check("临时密码可登录",
      _client.post("/auth/login", json={"phone": "13800006003",
                                        "password": temp}).status_code == 200)

print("── 8. 操作都进了审计 ──")
logs = _client.get("/admin/audit?limit=50", headers=h(BOSS)).json()
actions = [i["action"] for i in logs["items"]]
check("停用/重置等写操作被审计记录",
      any("/admin/users" in a for a in actions), actions[:6])
check("审计里有可读对象",
      any("13800006003" in (i["target"] or "") for i in logs["items"]),
      [i["target"] for i in logs["items"]][:6])

print()
print("════════════════════════════════")
print("  通过 %d 项，失败 %d 项" % (len(PASSED), len(FAILED)))
print("════════════════════════════════")
sys.exit(1 if FAILED else 0)
