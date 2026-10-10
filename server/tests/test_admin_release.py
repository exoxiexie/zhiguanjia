"""后台「版本发布」测试

验证"上传 → 发布"整条链路：
更新源（version.json）、官网下载页、站点重建、可选强制更新、历史归档。
"""

import json
import os
import shutil
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SITE_SRC = os.path.join(REPO, "site")

_tmp = tempfile.mkdtemp(prefix="zgjrelease")
SITE_DIR = os.path.join(_tmp, "site")
WEB_ROOT = os.path.join(_tmp, "web")
os.makedirs(WEB_ROOT, exist_ok=True)
shutil.copytree(SITE_SRC, SITE_DIR,
                ignore=shutil.ignore_patterns("dist", "*.apk", "__pycache__", "content"))
os.makedirs(os.path.join(SITE_DIR, "content"), exist_ok=True)
os.makedirs(os.path.join(SITE_DIR, "static"), exist_ok=True)
# 当前线上版本 = 1.0.49 / 50
json.dump({"versionName": "1.0.49", "versionCode": 50, "url": "http://x/old.apk",
           "changelog": "旧版本"}, open(os.path.join(SITE_DIR, "version.json"), "w"))

os.environ["ZGJ_DATABASE_URL"] = "sqlite:///" + os.path.join(_tmp, "t.db")
os.environ["ZGJ_JWT_SECRET"] = "release-test-secret"
os.environ["ZGJ_SECRETS_FILE"] = os.path.join(_tmp, "none.json")
os.environ["ZGJ_ENV"] = "test"
os.environ["ZGJ_SITE_DIR"] = SITE_DIR
os.environ["ZGJ_WEB_ROOT"] = WEB_ROOT
os.environ["ZGJ_SITE_URL"] = "http://test.local"

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


A = register("13800005001", "管理员")
B = register("13800005002", "普通用户")
db = SessionLocal()
try:
    u = db.scalar(select(User).where(User.phone == "13800005001"))
    u.is_admin = 1
    db.add(u)
    db.commit()
finally:
    db.close()

FAKE_APK = b"PK\x03\x04" + b"x" * 5000   # 不是真 APK，但足以走完流程


def upload(name="1.0.50", code=51, changelog="修复若干问题", force=False, filename=None, data=None):
    return _client.post(
        "/admin/release",
        headers=h(A),
        data={"version_name": name, "version_code": str(code),
              "changelog": changelog, "force_update": "true" if force else "false"},
        files={"file": (filename or f"zhiguanjia-v{name}.apk", data or FAKE_APK,
                        "application/vnd.android.package-archive")},
    )


print("── 1. 权限与初始状态 ──")
check("非管理员看列表 → 403", _client.get("/admin/release", headers=h(B)).status_code == 403)
r = _client.get("/admin/release", headers=h(A))
check("列表 → 200", r.status_code == 200, r.text[:200])
check("显示当前线上版本",
      r.json()["current"]["version_name"] == "1.0.49" and r.json()["current"]["version_code"] == 50,
      r.json()["current"])
check("初始没有发布记录", r.json()["items"] == [], r.json()["items"])

print("── 2. 上传校验 ──")
check("非 apk 被拒（400）", upload(filename="readme.txt").status_code == 400)
check("版本号不递增被拒（400）", upload(name="1.0.49", code=50).status_code == 400)
check("空文件被拒（400）", upload(data=b"PK").status_code == 400)

print("── 3. 上传成功（草稿，未生效）──")
r = upload()
check("上传 → 200", r.status_code == 200, r.text[:200])
rel = r.json()["release"]
rid = rel["id"]
check("记录了 sha256", len(rel["sha256"]) == 64, rel["sha256"])
check("记录了大小", rel["size"] == len(FAKE_APK), rel["size"])
check("状态为草稿", rel["status"] == "draft", rel["status"])
ver = json.load(open(os.path.join(SITE_DIR, "version.json")))
check("草稿未改动线上更新源", ver["versionName"] == "1.0.49", ver)

print("── 4. 发布 ──")
r = _client.post(f"/admin/release/{rid}/publish", headers=h(A))
check("发布 → 200", r.status_code == 200, r.text[:300])
ver = json.load(open(os.path.join(SITE_DIR, "version.json")))
check("更新源已更新为 1.0.50", ver["versionName"] == "1.0.50" and ver["versionCode"] == 51, ver)
check("下载地址指向我们自己的站点", ver["url"].startswith("http://test.local/"), ver["url"])
check("更新说明已写入", ver["changelog"] == "修复若干问题", ver)
check("安装包已铺到官网目录",
      os.path.exists(os.path.join(SITE_DIR, "static", "zhiguanjia-v1.0.50.apk")))
check("下载页已同步新版本名",
      "zhiguanjia-v1.0.50.apk" in open(os.path.join(WEB_ROOT, "zhiguanjia", "index.html"),
                                       encoding="utf-8").read()
      or "1.0.50" in open(os.path.join(WEB_ROOT, "index.html"), encoding="utf-8").read())
check("列表状态为已发布",
      [i for i in _client.get("/admin/release", headers=h(A)).json()["items"]
       if i["id"] == rid][0]["status"] == "published")

print("── 5. 强制更新 ──")
r = upload(name="1.0.51", code=52, changelog="紧急修复", force=True)
rid2 = r.json()["release"]["id"]
r = _client.post(f"/admin/release/{rid2}/publish", headers=h(A))
check("带强制更新发布 → 200", r.status_code == 200, r.text[:300])
check("返回 force_update", r.json()["force_update"] is True, r.json())
pub = _client.get("/app/config").json()
check("配置已下发强制更新（version_code=52）", pub["min_version"]["version_code"] == 52,
      pub["min_version"])
check("强制更新的下载地址与版本一致",
      pub["min_version"]["url"].endswith("zhiguanjia-v1.0.51.apk"), pub["min_version"])
old = [i for i in _client.get("/admin/release", headers=h(A)).json()["items"] if i["id"] == rid][0]
check("旧版本被归档", old["status"] == "archived", old["status"])

print("── 6. 删除 ──")
check("删除 → 200", _client.delete(f"/admin/release/{rid2}", headers=h(A)).status_code == 200)
check("安装包文件已删除",
      not os.path.exists(os.path.join(SITE_DIR, "static", "zhiguanjia-v1.0.51.apk")))

shutil.rmtree(_tmp, ignore_errors=True)
print()
print("════════════════════════════════")
print("  通过 %d 项，失败 %d 项" % (len(PASSED), len(FAILED)))
print("════════════════════════════════")
sys.exit(1 if FAILED else 0)
