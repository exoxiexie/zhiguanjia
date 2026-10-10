"""后台「备份与恢复」测试

重点验证"救命绳"真的有效：
- 备份产物里含数据库 / 文章内容 / 上传文件 / 配置
- **删掉内容后能恢复回来**（这是它的全部意义）
- 恢复前会自动先备份一次当前状态（恢复错了还能再回来）
- 只保留最近 N 份、路径穿越被拒、非管理员 403
"""

import json
import os
import shutil
import sys
import tarfile
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SITE_SRC = os.path.join(REPO, "site")

_tmp = tempfile.mkdtemp(prefix="zgjbackup")
SITE_DIR = os.path.join(_tmp, "site")
WEB_ROOT = os.path.join(_tmp, "web")
BACKUP_DIR = os.path.join(_tmp, "backups")
UPLOAD_DIR = os.path.join(_tmp, "uploads")

os.environ["ZGJ_DATABASE_URL"] = "sqlite:///" + os.path.join(_tmp, "t.db")
os.environ["ZGJ_JWT_SECRET"] = "backup-test-secret"
os.environ["ZGJ_SECRETS_FILE"] = os.path.join(_tmp, "secrets.json")
os.environ["ZGJ_ENV"] = "test"
os.environ["ZGJ_SITE_DIR"] = SITE_DIR
os.environ["ZGJ_WEB_ROOT"] = WEB_ROOT
os.environ["ZGJ_UPLOAD_DIR"] = UPLOAD_DIR
os.environ["ZGJ_BACKUP_DIR"] = BACKUP_DIR
os.environ["ZGJ_BACKUP_KEEP"] = "2"

os.makedirs(WEB_ROOT, exist_ok=True)
os.makedirs(UPLOAD_DIR, exist_ok=True)
shutil.copytree(SITE_SRC, SITE_DIR,
                ignore=shutil.ignore_patterns("dist", "*.apk", "__pycache__", "content"))
os.makedirs(os.path.join(SITE_DIR, "content"), exist_ok=True)
open(os.path.join(SITE_DIR, "content", "keep-me.md"), "w", encoding="utf-8").write(
    "---\ntitle: 要保住的文章\ndate: 2026-10-01\nauthor: 老谢\n---\n\n正文。\n")
open(os.path.join(UPLOAD_DIR, "photo.jpg"), "wb").write(b"fake-image-bytes")
open(os.environ["ZGJ_SECRETS_FILE"], "w", encoding="utf-8").write('{"ZGJ_DB_USER":"x"}')

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


A = register("13800003001", "管理员")
B = register("13800003002", "普通用户")
db = SessionLocal()
try:
    u = db.scalar(select(User).where(User.phone == "13800003001"))
    u.is_admin = 1
    db.add(u)
    db.commit()
finally:
    db.close()

print("── 1. 权限与初始状态 ──")
check("非管理员看备份 → 403", _client.get("/admin/backup", headers=h(B)).status_code == 403)
check("非管理员备份 → 403", _client.post("/admin/backup", headers=h(B)).status_code == 403)
r = _client.get("/admin/backup", headers=h(A))
check("读取备份列表 → 200", r.status_code == 200, r.text[:200])
d = r.json()
check("初始没有备份", d["items"] == [], d["items"])
check("返回磁盘信息", d["disk"]["total"] > 0, d["disk"])
check("返回保留份数与内容项", d["keep"] == 2 and set(d["parts"]) == {"db", "content", "uploads", "etc"},
      (d["keep"], d["parts"]))

print("── 2. 创建备份 ──")
r = _client.post("/admin/backup", headers=h(A))
check("备份 → 200", r.status_code == 200, r.text[:200])
name1 = r.json()["backup"]["name"]
check("备份名含日期时间", len(name1) >= 15, name1)
arc = os.path.join(BACKUP_DIR, f"{name1}.tar.gz")
check("备份文件已生成", os.path.exists(arc))
with tarfile.open(arc) as tar:
    names = tar.getnames()
check("含数据库导出", "db.sql.gz" in names, names)
check("含文章内容", "site-content.tar.gz" in names, names)
check("含上传文件", "uploads.tar.gz" in names, names)
check("含配置密钥", "etc.tar.gz" in names, names)
check("含清单", "MANIFEST.json" in names, names)
with tarfile.open(arc) as tar:
    man = json.loads(tar.extractfile("MANIFEST.json").read().decode())
check("清单记录了各部分大小", len(man.get("sizes", {})) >= 4, man)
with tarfile.open(arc) as tar:
    inner = tar.extractfile("site-content.tar.gz")
    with tarfile.open(fileobj=inner) as t2:
        check("文章内容包里有那篇文章",
              any(n.endswith("keep-me.md") for n in t2.getnames()), t2.getnames())

print("── 3. 删掉内容后恢复（救命绳的核心）──")
os.remove(os.path.join(SITE_DIR, "content", "keep-me.md"))
os.makedirs(os.path.join(SITE_DIR, "content"), exist_ok=True)
shutil.rmtree(UPLOAD_DIR)
os.makedirs(UPLOAD_DIR, exist_ok=True)
check("内容已被人为删除（前置条件）",
      not os.path.exists(os.path.join(SITE_DIR, "content", "keep-me.md")))

check("恢复未确认 → 400",
      _client.post(f"/admin/backup/{name1}/restore", headers=h(A)).status_code == 400)
r = _client.post(f"/admin/backup/{name1}/restore?confirm=RESTORE&parts=content,uploads",
                 headers=h(A))
check("恢复 → 200", r.status_code == 200, r.text[:300])
res = r.json()
check("恢复了内容与上传", set(res["restored"]) == {"content", "uploads"}, res)
check("文章回来了", os.path.exists(os.path.join(SITE_DIR, "content", "keep-me.md")))
check("上传文件回来了", os.path.exists(os.path.join(UPLOAD_DIR, "photo.jpg")))
check("恢复前自动保存了现场（可再恢复回来）",
      res["safety_backup"].endswith("prerestore") and
      os.path.exists(os.path.join(BACKUP_DIR, f"{res['safety_backup']}.tar.gz")),
      res["safety_backup"])
check("内容恢复后会重建站点", "rebuild" in res, list(res))
check("线上页面已按恢复后的内容生成",
      os.path.exists(os.path.join(WEB_ROOT, "blog", "keep-me", "index.html")))

print("── 4. 只保留最近 N 份 ──")
for i in range(4):
    _client.post("/admin/backup", headers=h(A))
items = _client.get("/admin/backup", headers=h(A)).json()["items"]
check("超出保留份数后自动清理（keep=2）", len(items) == 2, len(items))
check("留下的都是最新的",
      items[0]["name"] > items[1]["name"] if len(items) == 2 else False,
      [i["name"] for i in items])

print("── 5. 删除与安全 ──")
keep_name = items[0]["name"]
check("删除备份 → 200", _client.delete(f"/admin/backup/{keep_name}", headers=h(A)).status_code == 200)
check("文件已删除", not os.path.exists(os.path.join(BACKUP_DIR, f"{keep_name}.tar.gz")))
check("删除不存在的备份 → 404",
      _client.delete("/admin/backup/20200101-000000", headers=h(A)).status_code == 404)
check("路径穿越恢复被拒（400）",
      _client.post("/admin/backup/..%2F..%2Fetc%2Fpasswd/restore?confirm=RESTORE",
                   headers=h(A)).status_code in (400, 404, 405))

shutil.rmtree(_tmp, ignore_errors=True)
print()
print("════════════════════════════════")
print("  通过 %d 项，失败 %d 项" % (len(PASSED), len(FAILED)))
print("════════════════════════════════")
sys.exit(1 if FAILED else 0)
