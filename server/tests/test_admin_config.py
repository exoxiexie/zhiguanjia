"""后台「公告与配置」测试：公告 / 强制更新 / 功能开关

重点：配置是**下发到所有客户端**的，改错影响面极大 ——
既要能改，也要防住明显错误，并留下"谁改的"。
"""

import os
import sys
import tempfile

os.environ["ZGJ_DATABASE_URL"] = "sqlite:///" + os.path.join(tempfile.mkdtemp(), "t.db")
os.environ["ZGJ_JWT_SECRET"] = "cfg-test-secret"
os.environ["ZGJ_SECRETS_FILE"] = os.path.join(tempfile.mkdtemp(), "none.json")
os.environ["ZGJ_ENV"] = "test"
os.environ["ZGJ_UPLOAD_DIR"] = tempfile.mkdtemp()
os.environ["ZGJ_SITE_DIR"] = tempfile.mkdtemp()   # release 信息读不到时返回空，不影响用例

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


A = register("13800002001", "运营")
B = register("13800002002", "普通用户")

db = SessionLocal()
try:
    u = db.scalar(select(User).where(User.phone == "13800002001"))
    u.is_admin = 1
    db.add(u)
    db.commit()
finally:
    db.close()

print("── 1. 权限 ──")
check("非管理员读配置 → 403", _client.get("/admin/config", headers=h(B)).status_code == 403)
check("非管理员写配置 → 403",
      _client.post("/admin/config", headers=h(B), json={"flags": {}}).status_code == 403)

print("── 2. 初始状态 ──")
r = _client.get("/admin/config", headers=h(A))
check("读取配置 → 200", r.status_code == 200, r.text[:200])
cfg = r.json()
check("含公告/强制更新/开关三块",
      {"announcement", "min_version", "flags"} <= set(cfg), list(cfg))
check("含当前线上版本参考（release）", "release" in cfg, list(cfg))
check("初始未启用公告", cfg["announcement"]["enabled"] is False, cfg["announcement"])
check("初始不强制更新", cfg["min_version"]["version_code"] == 0, cfg["min_version"])

print("── 3. 公告 ──")
r = _client.post("/admin/config", headers=h(A), json={
    "announcement": {"enabled": True, "title": "维护通知",
                     "body": "今晚 23:00-24:00 维护，期间可能短暂不可用。"}
})
check("发布公告 → 200", r.status_code == 200, r.text[:200])
aid1 = r.json()["config"]["announcement"]["id"]
check("公告 ID 自动生成（作者不必理解该机制）", len(aid1) > 0, aid1)
check("记录修改人", r.json()["config"]["updated_by"] == "13800002001",
      r.json()["config"]["updated_by"])

pub = _client.get("/app/config").json()
check("公开接口已生效（App 无需发版即可看到）",
      pub["announcement"]["enabled"] is True and "维护通知" == pub["announcement"]["title"],
      pub["announcement"])

# 重新弹一次：换 ID
r = _client.post("/admin/config", headers=h(A), json={
    "announcement": {"enabled": True, "title": "维护通知", "body": "再看一次"},
    "reset_announcement_read": True,
})
aid2 = r.json()["config"]["announcement"]["id"]
check("「重新弹一次」会换公告 ID（老用户也会再看到）", aid2 != aid1, (aid1, aid2))

r = _client.post("/admin/config", headers=h(A), json={
    "announcement": {"enabled": True, "title": "空", "body": "   "}})
check("启用公告但正文为空 → 400", r.status_code == 400, r.status_code)

r = _client.post("/admin/config", headers=h(A), json={
    "announcement": {"enabled": False, "title": "维护通知", "body": "已下线"}})
check("关闭公告 → 200", r.status_code == 200)
check("公开接口已关闭公告", _client.get("/app/config").json()["announcement"]["enabled"] is False)

print("── 4. 强制更新 ──")
r = _client.post("/admin/config", headers=h(A), json={
    "min_version": {"version_code": 50, "version_name": "1.0.49",
                    "url": "https://gitee.com/laoxie2076/zhiguanjia/releases/download/v1.0.49/zhiguanjia-v1.0.49.apk",
                    "note": "修复同步问题，必须升级"}})
check("设置强制更新 → 200", r.status_code == 200, r.text[:200])
pub = _client.get("/app/config").json()
check("公开接口已下发最低版本", pub["min_version"]["version_code"] == 50, pub["min_version"])
check("下载地址与说明已下发",
      pub["min_version"]["url"].endswith(".apk") and "必须升级" in pub["min_version"]["note"],
      pub["min_version"])

r = _client.post("/admin/config", headers=h(A), json={"min_version": {"version_code": -1}})
check("负数版本号被拒（422）", r.status_code == 422, r.status_code)

r = _client.post("/admin/config", headers=h(A), json={"min_version": {"version_code": 0}})
check("关闭强制更新（0）→ 200", r.status_code == 200)
check("公开接口已关闭强制", _client.get("/app/config").json()["min_version"]["version_code"] == 0)

print("── 5. 功能开关（含测试入口灰度）──")
r = _client.post("/admin/config", headers=h(A), json={
    "flags": {"test_panel": False, "test_panel_phones": ["13608074995"]}})
check("保存功能开关 → 200", r.status_code == 200, r.text[:200])
pub = _client.get("/app/config").json()
check("公开接口已下发开关",
      pub["flags"].get("test_panel_phones") == ["13608074995"], pub["flags"])
check("后端读取与写入一致",
      _client.get("/admin/config", headers=h(A)).json()["flags"]["test_panel"] is False)

r = _client.post("/admin/config", headers=h(A), json={"flags": ["不是对象"]})
check("开关必须是对象（422）", r.status_code == 422, r.status_code)

r = _client.post("/admin/config", headers=h(A), json={"flags": {"k": "x" * 9000}})
check("开关过大被拒（400）", r.status_code == 400, r.status_code)

print("── 6. 只改一块不影响其他 ──")
_client.post("/admin/config", headers=h(A), json={
    "announcement": {"enabled": True, "title": "A", "body": "公告内容"}})
r = _client.post("/admin/config", headers=h(A), json={
    "flags": {"test_panel": True}}).json()["config"]
check("只改开关后公告仍在", r["announcement"]["body"] == "公告内容", r["announcement"])

print()
print("════════════════════════════════")
print("  通过 %d 项，失败 %d 项" % (len(PASSED), len(FAILED)))
print("════════════════════════════════")
sys.exit(1 if FAILED else 0)
