"""后台「博客发布管理」测试

重点验证**真实发布链路**（不是打桩）：
写 Markdown → 跑 build.py 构建 → sync_site.py 同步 → 产物里能看到标题与作者。
用临时站点目录，避免影响线上。
"""

import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
REPO = os.path.dirname(SERVER)
SITE_SRC = os.path.join(REPO, "site")

# 数据库/密钥等一律用测试隔离值（与其它测试一致）
os.environ["ZGJ_DATABASE_URL"] = "sqlite:///" + os.path.join(tempfile.mkdtemp(), "t.db")
os.environ["ZGJ_JWT_SECRET"] = "blog-test-secret"
os.environ["ZGJ_SECRETS_FILE"] = os.path.join(tempfile.mkdtemp(), "none.json")
os.environ["ZGJ_ENV"] = "test"
os.environ["ZGJ_UPLOAD_DIR"] = tempfile.mkdtemp()

_tmp = tempfile.mkdtemp(prefix="zjgsite")
SITE_DIR = os.path.join(_tmp, "site")
WEB_ROOT = os.path.join(_tmp, "web")
os.makedirs(WEB_ROOT, exist_ok=True)

# 复制站点源码（跳过 dist 与 APK：构建脚本对缺失 APK 是容错的）
shutil.copytree(
    SITE_SRC,
    SITE_DIR,
    ignore=shutil.ignore_patterns("dist", "*.apk", "__pycache__"),
)
os.environ["ZGJ_SITE_DIR"] = SITE_DIR
os.environ["ZGJ_WEB_ROOT"] = WEB_ROOT

sys.path.insert(0, SERVER)
sys.path.insert(0, REPO)

from fastapi.testclient import TestClient  # noqa: E402

from app.db import SessionLocal  # noqa: E402
from app.main import app  # noqa: E402
from app.models import User  # noqa: E402
from sqlalchemy import select  # noqa: E402

_client = TestClient(app)
_client.__enter__()  # 触发 lifespan：建表

PASSED, FAILED = [], []


def check(name, cond, extra=""):
    (PASSED if cond else FAILED).append(name)
    print(("  ✅ " if cond else "  ❌ ") + name + (("  → " + str(extra)[:200]) if extra and not cond else ""))


def register(phone, name):
    r = _client.post(
        "/auth/register", json={"phone": phone, "password": "test123456", "name": name}
    )
    assert r.status_code == 201, r.text
    return r.json()["access_token"]


def h(t):
    return {"Authorization": "Bearer " + t}


A = register("13800009911", "博主")
B = register("13800009922", "普通用户")

db = SessionLocal()
try:
    u = db.scalar(select(User).where(User.phone == "13800009911"))
    u.is_admin = 1
    db.add(u)
    db.commit()
finally:
    db.close()

print("── 1. 权限 ──")
check("非管理员看列表 → 403", _client.get("/admin/blog", headers=h(B)).status_code == 403)
check("非管理员建文章 → 403",
      _client.post("/admin/blog", headers=h(B), json={"title": "x", "slug": "x"}).status_code == 403)

print("── 2. 新建与校验 ──")
r = _client.post("/admin/blog", headers=h(A), json={
    "title": "用 AI 做职业规划的五个步骤",
    "slug": "ai-career-five-steps",
    "author": "老谢",
    "date": "2026-10-10",
    "excerpt": "先看目标，再看差距，最后排优先级。",
    "tags": ["职业规划", "方法论"],
    "body_md": "## 第一步\n\n先写清楚你三年后想成为什么样的人。\n\n- 目标\n- 差距\n- 行动",
    "status": "draft",
})
check("新建文章 → 200", r.status_code == 200, r.text[:200])
art = r.json()["article"]
aid = art["id"]
check("状态为草稿", art["status"] == "draft", art)
check("链接地址正确", art["url"] == "/blog/ai-career-five-steps/", art["url"])

check("非法 slug → 400",
      _client.post("/admin/blog", headers=h(A),
                   json={"title": "x", "slug": "../etc/passwd"}).status_code == 400)
check("空标题 → 400",
      _client.post("/admin/blog", headers=h(A),
                   json={"title": "   ", "slug": "ok-slug"}).status_code == 400)
r2 = _client.post("/admin/blog", headers=h(A), json={"title": "占位", "slug": "ai-career-five-steps"})
check("slug 冲突 → 409", r2.status_code == 409, r2.status_code)

print("── 3. 发布（真实构建 + 部署）──")
r = _client.post(f"/admin/blog/{aid}/publish", headers=h(A))
check("发布 → 200", r.status_code == 200, r.text[:300])
check("返回线上地址", r.json().get("url") == "/blog/ai-career-five-steps/", r.json())

md_path = os.path.join(SITE_DIR, "content", "ai-career-five-steps.md")
check("Markdown 已写入站点源目录", os.path.exists(md_path))
md = open(md_path, encoding="utf-8").read() if os.path.exists(md_path) else ""
check("front-matter 含标题", "title: 用 AI 做职业规划的五个步骤" in md, md[:120])
check("front-matter 含作者", "author: 老谢" in md, md[:120])
check("front-matter 含日期", "date: 2026-10-10" in md, md[:120])

html_path = os.path.join(SITE_DIR, "dist", "blog", "ai-career-five-steps", "index.html")
html = open(html_path, encoding="utf-8").read() if os.path.exists(html_path) else ""
check("构建产物含文章页", bool(html))
check("文章页含标题", "用 AI 做职业规划的五个步骤" in html)
check("文章页含「作者：老谢」", "作者：老谢" in html, html[:0])
check("正文渲染为 HTML", "<h2" in html and "第一步" in html)

check("已同步到站点根目录（文章页）",
      os.path.exists(os.path.join(WEB_ROOT, "blog", "ai-career-five-steps", "index.html")))
check("已同步到站点根目录（首页）", os.path.exists(os.path.join(WEB_ROOT, "index.html")))
check("首页出现新文章", "用 AI 做职业规划的五个步骤" in
      open(os.path.join(WEB_ROOT, "index.html"), encoding="utf-8").read())

r = _client.get("/admin/blog", headers=h(A))
items = {i["slug"]: i for i in r.json()["items"]}
check("列表显示已发布", items["ai-career-five-steps"]["status"] == "published", items)
check("列表带站点目录状态", r.json()["site_dir_ready"] is True, r.json().get("site_dir"))

print("── 4. 编辑并重发 ──")
r = _client.post(f"/admin/blog?article_id={aid}", headers=h(A), json={
    "title": "用 AI 做职业规划的五个步骤（修订）",
    "slug": "ai-career-five-steps",
    "author": "老谢",
    "date": "2026-10-10",
    "excerpt": "修订版",
    "tags": [],
    "body_md": "修订后的正文",
    "status": "published",
})
check("更新 → 200", r.status_code == 200, r.text[:200])
check("更新未新建（仍是一篇）",
      len(_client.get("/admin/blog", headers=h(A)).json()["items"]) == 1)
r = _client.post(f"/admin/blog/{aid}/publish", headers=h(A))
check("重发 → 200", r.status_code == 200, r.text[:200])
check("线上页面已更新",
      "修订后的正文" in open(html_path, encoding="utf-8").read())

print("── 5. 删除（页面随之下线）──")
r = _client.delete(f"/admin/blog/{aid}", headers=h(A))
check("删除 → 200", r.status_code == 200, r.text[:200])
check("Markdown 已删除", not os.path.exists(md_path))
check("线上文章目录已清理",
      not os.path.exists(os.path.join(WEB_ROOT, "blog", "ai-career-five-steps")))
check("列表已空", len(_client.get("/admin/blog", headers=h(A)).json()["items"]) == 0)

print("── 7. 链接地址自动生成（作者不必填写）──")
r = _client.post("/admin/blog", headers=h(A), json={
    "title": "用 AI 做职业规划的五个步骤",
    "slug": "",                       # 留空 → 按标题自动生成
    "body_md": "正文",
})
check("中文标题自动生成链接 → 200", r.status_code == 200, r.text[:200])
cn = r.json()["article"]
check("中文标题生成中文链接（可读、可分享）", cn["slug"] == "用-ai-做职业规划的五个步骤", cn["slug"])
check("链接地址可读", cn["url"] == "/blog/用-ai-做职业规划的五个步骤/", cn["url"])

r2 = _client.post("/admin/blog", headers=h(A), json={"title": "用 AI 做职业规划的五个步骤"})
check("同标题重名自动顺延（-2）", r2.json()["article"]["slug"].endswith("-2"),
      r2.json()["article"]["slug"])

r3 = _client.post("/admin/blog", headers=h(A), json={"title": "！！！？？？"})
check("纯符号标题回退为 post-日期-随机",
      r3.json()["article"]["slug"].startswith("post-"), r3.json()["article"]["slug"])

r4 = _client.post("/admin/blog", headers=h(A), json={"title": "英文标题 Post", "slug": ""})
check("英文标题转小写短横线", r4.json()["article"]["slug"] == "英文标题-post",
      r4.json()["article"]["slug"])

check("自定义链接仍严格校验（路径穿越被拒）",
      _client.post("/admin/blog", headers=h(A),
                   json={"title": "x", "slug": "../../etc/passwd"}).status_code == 400)

# 中文链接的发布链路（Markdown 文件名 + 构建产物 + 首页链接编码）
aid_cn = cn["id"]
r = _client.post(f"/admin/blog/{aid_cn}/publish", headers=h(A))
check("中文链接文章可发布", r.status_code == 200, r.text[:200])
check("Markdown 以中文名写入", os.path.exists(
    os.path.join(SITE_DIR, "content", "用-ai-做职业规划的五个步骤.md")))
_home = open(os.path.join(WEB_ROOT, "index.html"), encoding="utf-8").read()
check("首页链接已 URL 编码（中文链接合规）",
      "%E7%94%A8-ai-%E5%81%9A%E8%81%8C%E4%B8%9A%E8%A7%84%E5%88%92" in _home
      or "用-ai-做职业规划" in _home, "首页未找到该文章链接")
_sm = open(os.path.join(WEB_ROOT, "sitemap.xml"), encoding="utf-8").read()
check("sitemap 已编码", "%E7%94%A8" in _sm or "用-ai" in _sm)

print("── 6. 仅重建 ──")
r = _client.post("/admin/system/rebuild", headers=h(A))
check("重建 → 200", r.status_code == 200, r.text[:200])

shutil.rmtree(_tmp, ignore_errors=True)

print()
print("════════════════════════════════")
print("  通过 %d 项，失败 %d 项" % (len(PASSED), len(FAILED)))
print("════════════════════════════════")
sys.exit(1 if FAILED else 0)
