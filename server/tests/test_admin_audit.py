"""后台操作审计测试

审计的价值在于"**不漏记**"，所以重点验证：
- 所有 /admin 写操作都被记录（含**失败**与**未授权尝试**）
- 记录了操作者、对象、结果
- 只读请求不记（避免噪音）
- 超出上限自动清理
"""

import os
import sys
import tempfile

os.environ["ZGJ_DATABASE_URL"] = "sqlite:///" + os.path.join(tempfile.mkdtemp(), "t.db")
os.environ["ZGJ_JWT_SECRET"] = "audit-test-secret"
os.environ["ZGJ_SECRETS_FILE"] = os.path.join(tempfile.mkdtemp(), "none.json")
os.environ["ZGJ_ENV"] = "test"
os.environ["ZGJ_SITE_DIR"] = tempfile.mkdtemp()
os.environ["ZGJ_AUDIT_KEEP"] = "3"   # 便于验证自动清理

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import select  # noqa: E402

from app.admin.audit import KEEP, normalize_action  # noqa: E402
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


A = register("13800004001", "管理员")
B = register("13800004002", "普通用户")
db = SessionLocal()
try:
    u = db.scalar(select(User).where(User.phone == "13800004001"))
    u.is_admin = 1
    db.add(u)
    db.commit()
finally:
    db.close()

print("── 1. 动作归一化 ──")
check("路径参数被归一化",
      normalize_action("POST", "/admin/blog/abc-123-def/publish") == "/admin/blog/{id}/publish",
      normalize_action("POST", "/admin/blog/abc-123-def/publish"))
check("普通段保留",
      normalize_action("POST", "/admin/system/rebuild") == "/admin/system/rebuild")

print("── 2. 写操作被记录 ──")
r = _client.post("/admin/blog", headers=h(A),
                 json={"title": "审计验证文章", "body_md": "正文"})
aid = r.json()["article"]["id"]
_client.post(f"/admin/blog/{aid}/publish", headers=h(A))
_client.post("/admin/config", headers=h(A), json={"flags": {"test_panel": True}})

r = _client.get("/admin/audit", headers=h(A))
check("审计查询 → 200", r.status_code == 200, r.text[:200])
data = r.json()
check("按时间倒序（最新在前）",
      all(data["items"][i]["id"] > data["items"][i + 1]["id"] for i in range(len(data["items"]) - 1)),
      [i["id"] for i in data["items"]])
acts = {i["action"] for i in data["items"]}
check("记录了新建文章", "/admin/blog" in acts, acts)
check("记录了发布文章", "/admin/blog/{id}/publish" in acts, acts)
check("记录了配置修改", "/admin/config" in acts, acts)
check("记录了操作者", all(i["actor"] == "13800004001" for i in data["items"]), data["items"][0])
check("记录了人类可读对象",
      any("审计验证文章" in i["target"] for i in data["items"]),
      [i["target"] for i in data["items"]])
check("记录了 IP", all(i["ip"] for i in data["items"]), data["items"][0])

print("── 3. 只读请求不记（避免噪音）──")
before_total = _client.get("/admin/audit", headers=h(A)).json()["total"]
for _ in range(3):
    _client.get("/admin/blog", headers=h(A))
    _client.get("/admin/system/status", headers=h(A))
after_total = _client.get("/admin/audit", headers=h(A)).json()["total"]
check("GET 请求不产生日志", before_total == after_total, (before_total, after_total))

print("── 4. 失败与未授权尝试也要留痕 ──")
_client.post("/admin/blog", headers=h(A), json={"title": "非法", "slug": "../../etc/passwd"})
bad = _client.get("/admin/audit?only_failed=true", headers=h(A)).json()
check("失败的写操作被记录（ok=false）", bad["total"] >= 1, bad["total"])
check("失败记录带状态码", any(i["status"] == 400 for i in bad["items"]), bad["items"])

_client.post("/admin/blog", headers=h(B), json={"title": "越权", "slug": "x"})
all_log = _client.get("/admin/audit", headers=h(A)).json()
check("未授权尝试也被记录",
      any(i["status"] == 403 for i in all_log["items"]),
      [(i["action"], i["status"], i["actor"]) for i in all_log["items"]])

print("── 5. 筛选 ──")
only_cfg = _client.get("/admin/audit?action=/admin/config", headers=h(A)).json()
check("按动作筛选", all(i["action"] == "/admin/config" for i in only_cfg["items"]) and only_cfg["total"] >= 1,
      only_cfg["total"])
by_actor = _client.get("/admin/audit?actor=13800004002", headers=h(A)).json()
check("按操作者筛选", by_actor["total"] >= 1, by_actor["total"])
check("返回动作清单供筛选", isinstance(all_log["actions"], list) and all_log["actions"], all_log["actions"])

print("── 6. 超出上限自动清理 ──")
db = SessionLocal()
try:
    from app.models import AuditLog
    from sqlalchemy import func
    total = int(db.scalar(select(func.count()).select_from(AuditLog)) or 0)
finally:
    db.close()
check("记录数被限制在 keep + 少量余量内", total <= KEEP + 200, (total, KEEP))

print("── 7. 权限 ──")
check("非管理员看审计 → 403", _client.get("/admin/audit", headers=h(B)).status_code == 403)

print()
print("════════════════════════════════")
print("  通过 %d 项，失败 %d 项" % (len(PASSED), len(FAILED)))
print("════════════════════════════════")
sys.exit(1 if FAILED else 0)
