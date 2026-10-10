"""后台「内容审核」测试：说说巡检、下架（软删除）、恢复"""

import os
import sys
import tempfile

os.environ["ZGJ_DATABASE_URL"] = "sqlite:///" + os.path.join(tempfile.mkdtemp(), "t.db")
os.environ["ZGJ_JWT_SECRET"] = "content-test-secret"
os.environ["ZGJ_SECRETS_FILE"] = os.path.join(tempfile.mkdtemp(), "none.json")
os.environ["ZGJ_ENV"] = "test"
os.environ["ZGJ_SITE_DIR"] = tempfile.mkdtemp()
os.environ["ZGJ_UPLOAD_DIR"] = tempfile.mkdtemp()

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import select  # noqa: E402

from app.db import SessionLocal  # noqa: E402
from app.main import app  # noqa: E402
from app.models import BlogPost, User  # noqa: E402

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


ADM = register("13800007001", "管理员")
USR = register("13800007002", "普通用户")
db = SessionLocal()
try:
    a = db.scalar(select(User).where(User.phone == "13800007001"))
    a.is_admin = 1
    u = db.scalar(select(User).where(User.phone == "13800007002"))
    db.add(a)
    # 造两条说说：一条正常、一条含违规词
    db.add(BlogPost(id="p-ok", user_id=u.id, title="今天面试顺利", content="拿到 offer 了！",
                    author_phone=u.phone, author_name=u.name, created_at=1, seq=1))
    db.add(BlogPost(id="p-bad", user_id=u.id, title="广告", content="加微信卖证书，包过",
                    author_phone=u.phone, author_name=u.name, created_at=2, seq=2))
    db.commit()
    UID = u.id
finally:
    db.close()

print("── 1. 权限 ──")
check("非管理员看内容 → 403", _client.get("/admin/content", headers=h(USR)).status_code == 403)

print("── 2. 列表与检索 ──")
r = _client.get("/admin/content", headers=h(ADM))
check("列表 → 200", r.status_code == 200, r.text[:200])
d = r.json()
check("能看到两条说说", d["total"] == 2, d["total"])
check("带作者信息", all(i["author_phone"] for i in d["items"]), d["items"][0])
check("带统计（总数/已下架）", d["stats"]["all"] == 2 and d["stats"]["hidden"] == 0, d["stats"])
hit = _client.get("/admin/content?q=包过", headers=h(ADM)).json()
check("按内容关键词检索", hit["total"] == 1 and hit["items"][0]["id"] == "p-bad", hit["total"])

print("── 3. 下架（软删除，必须填原因）──")
check("不填原因 → 400",
      _client.post("/admin/content/p-bad/hide", headers=h(ADM), json={}).status_code == 400)
r = _client.post("/admin/content/p-bad/hide", headers=h(ADM), json={"reason": "违规广告"})
check("下架 → 200", r.status_code == 200, r.text[:200])
after = _client.get("/admin/content", headers=h(ADM)).json()
bad = [i for i in after["items"] if i["id"] == "p-bad"][0]
check("标记为已下架", bad["hidden"] is True, bad)
check("记录下架原因", bad["hidden_reason"] == "违规广告", bad)
check("统计随之更新", after["stats"]["hidden"] == 1, after["stats"])
check("只看已下架可筛出",
      [i["id"] for i in _client.get("/admin/content?only_hidden=true",
                                    headers=h(ADM)).json()["items"]] == ["p-bad"])

print("── 4. 数据是软删除（内容没丢，可恢复）──")
db = SessionLocal()
try:
    row = db.get(BlogPost, "p-bad")
    check("原内容仍在库里", row is not None and "包过" in row.content)
    check("deleted_at 已置位", row.deleted_at is not None)
finally:
    db.close()

print("── 5. 恢复 ──")
check("恢复 → 200", _client.post("/admin/content/p-bad/restore", headers=h(ADM)).status_code == 200)
back = [i for i in _client.get("/admin/content", headers=h(ADM)).json()["items"] if i["id"] == "p-bad"][0]
check("已恢复正常", back["hidden"] is False and back["hidden_reason"] == "", back)

print("── 6. 不存在的 id ──")
check("下架不存在的说说 → 404",
      _client.post("/admin/content/nope/hide", headers=h(ADM), json={"reason": "x"}).status_code == 404)

print("── 7. 审计留痕 ──")
logs = _client.get("/admin/audit?limit=20", headers=h(ADM)).json()
check("下架/恢复都进了审计",
      sum(1 for i in logs["items"] if i["action"] == "/admin/content/{id}/hide") >= 1
      and any("下架" in (i["target"] or "") for i in logs["items"]),
      [i["target"] for i in logs["items"]][:5])

print()
print("════════════════════════════════")
print("  通过 %d 项，失败 %d 项" % (len(PASSED), len(FAILED)))
print("════════════════════════════════")
sys.exit(1 if FAILED else 0)
