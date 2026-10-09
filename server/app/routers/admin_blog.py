"""后台「博客发布管理」

设计前提：官网是**纯静态站**（`site/content/*.md` → `build.py` → 站点根目录）。
因此本模块的职责是：

1. **存库**：文章正文存在 `articles` 表（后台列表、编辑、草稿的基础）
2. **发布**：把文章写成 `content/{slug}.md`，调用 `build.py` 重新构建，
   再调用 `sync_site.py` 同步到站点根目录

构建与同步都走命令行脚本 —— **发布流程的唯一实现**，与人工部署完全一致，
不会出现"后台发出来和手发不一样"。

安全：
- 全部接口走 `require_admin`
- slug 严格校验（只允许小写字母/数字/连字符），杜绝路径穿越
"""

import datetime
import json
import os
import re
import subprocess
import sys
import threading

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..deps import get_db, require_admin
from ..errors import api_error
from ..models import Article, User, new_uuid, utcnow
from ..schemas import ArticleIn

router = APIRouter(tags=["admin-blog"])

SITE_DIR = os.environ.get("ZGJ_SITE_DIR", "/www/wwwroot/zhiguanjia-site")

# 构建必须**串行**：两次构建并发写同一个 dist/ 会互相覆盖，轻则产物错乱、
# 重则线上页面半新半旧。拿不到锁就直接告诉前端"正在构建"，而不是傻等或并行。
_build_lock = threading.Lock()
_SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")
_CST = datetime.timedelta(hours=8)


def _today() -> str:
    return (utcnow() + _CST).date().isoformat()


def _md(a: Article) -> str:
    """生成带 front-matter 的 Markdown（与 build.py 的解析格式一致）"""
    tags = ""
    try:
        parsed = json.loads(a.tags_json or "[]")
        if parsed:
            tags = "tags: " + ", ".join(str(t) for t in parsed) + "\n"
    except Exception:
        tags = ""
    return (
        "---\n"
        f"title: {a.title}\n"
        f"date: {a.date}\n"
        f"author: {a.author}\n"
        f"excerpt: {a.excerpt}\n"
        f"{tags}"
        "---\n\n"
        f"{a.body_md.strip()}\n"
    )


def _tail(text: str, n: int = 500) -> str:
    text = (text or "").strip()
    return text[-n:] if len(text) > n else text


def rebuild_and_deploy() -> dict:
    """重新构建并同步到站点根目录（后台发布与命令行部署共用同一条链路）"""
    if not os.path.isdir(SITE_DIR):
        return {"ok": False, "message": f"站点源码目录不存在：{SITE_DIR}"}
    if not _build_lock.acquire(blocking=False):
        return {"ok": False, "busy": True, "message": "另一个构建正在进行，请稍等几秒再试"}
    try:
        return _rebuild_locked()
    finally:
        _build_lock.release()


def _rebuild_locked() -> dict:
    for script, label in (("build.py", "构建"), ("sync_site.py", "部署")):
        try:
            proc = subprocess.run(
                [sys.executable, script],
                cwd=SITE_DIR,
                capture_output=True,
                text=True,
                timeout=180,
            )
        except Exception as exc:  # noqa: BLE001
            return {"ok": False, "message": f"{label}异常：{exc}"}
        if proc.returncode != 0:
            return {
                "ok": False,
                "message": f"{label}失败：{_tail(proc.stderr or proc.stdout)}",
            }
    return {"ok": True, "message": "已重新构建并发布到官网"}


def _serialize(a: Article, with_body: bool = False) -> dict:
    out = {
        "id": a.id,
        "slug": a.slug,
        "title": a.title,
        "author": a.author,
        "date": a.date,
        "excerpt": a.excerpt,
        "status": a.status,
        "url": f"/blog/{a.slug}/",
        "updated_at": (a.updated_at or utcnow()).isoformat(),
        "published_at": a.published_at.isoformat() if a.published_at else "",
    }
    if with_body:
        try:
            out["tags"] = json.loads(a.tags_json or "[]")
        except Exception:
            out["tags"] = []
        out["body_md"] = a.body_md
    return out


def _find(db: Session, article_id: str) -> Article:
    row = db.get(Article, article_id)
    if row is None:
        raise api_error(404, "not_found", "文章不存在")
    return row


@router.get("/admin/blog")
def list_articles(
    user: User = Depends(require_admin), db: Session = Depends(get_db)
) -> dict:
    """文章列表（不含正文，列表页够用且更快）"""
    rows = db.scalars(
        select(Article).order_by(Article.date.desc(), Article.updated_at.desc())
    ).all()
    return {
        "items": [_serialize(a) for a in rows],
        "site_dir": SITE_DIR,
        "site_dir_ready": os.path.isdir(SITE_DIR),
    }


@router.get("/admin/blog/{article_id}")
def get_article(
    article_id: str,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
) -> dict:
    """单篇（含正文与标签），供编辑器回填"""
    return _serialize(_find(db, article_id), with_body=True)


@router.post("/admin/blog")
def save_article(
    body: ArticleIn,
    article_id: str = "",
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
) -> dict:
    """新建或更新（article_id 为空则新建）"""
    slug = (body.slug or "").strip().lower()
    if not _SLUG_RE.match(slug):
        raise api_error(
            400, "bad_slug", "链接标识只能用「小写字母、数字、连字符」，且以字母或数字开头"
        )
    title = (body.title or "").strip()
    if not title:
        raise api_error(400, "bad_title", "标题不能为空")

    # slug 唯一性（同一篇改 slug 允许；占用了别人的则拒绝）
    dup = db.scalar(select(Article).where(Article.slug == slug))
    if dup is not None and dup.id != article_id:
        raise api_error(409, "slug_taken", f"链接标识「{slug}」已被《{dup.title}》占用")

    row = _find(db, article_id) if article_id else None
    if row is None:
        row = Article(id=new_uuid(), slug=slug, created_at=utcnow())
        db.add(row)

    row.slug = slug
    row.title = title[:200]
    row.author = (body.author or "老谢").strip()[:64] or "老谢"
    row.date = (body.date or "").strip()[:20] or _today()
    row.excerpt = (body.excerpt or "").strip()[:500]
    row.tags_json = json.dumps([t for t in (body.tags or []) if t][:20], ensure_ascii=False)
    row.body_md = body.body_md or ""
    row.status = "published" if body.status == "published" else "draft"
    row.updated_at = utcnow()
    db.commit()  # 必须提交：否则 slug 冲突检测与后续发布都读不到这篇

    return {"ok": True, "article": _serialize(row, with_body=True)}


@router.delete("/admin/blog/{article_id}")
def delete_article(
    article_id: str,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
) -> dict:
    """删除文章；若已发布，同时删掉 Markdown 并重建（线上页面随之下线）"""
    row = _find(db, article_id)
    slug = row.slug
    was_published = row.status == "published"
    db.delete(row)
    db.commit()

    removed_md = False
    result = {"ok": True, "message": "已删除"}
    if was_published:
        md_path = os.path.join(SITE_DIR, "content", f"{slug}.md")
        if os.path.exists(md_path):
            os.remove(md_path)
            removed_md = True
        result = rebuild_and_deploy()
    return {
        "ok": True,
        "removed_markdown": removed_md,
        "rebuild": result,
    }


@router.post("/admin/blog/{article_id}/publish")
def publish_article(
    article_id: str,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
) -> dict:
    """发布：写 Markdown → 重新构建 → 同步上线"""
    row = _find(db, article_id)
    if not _SLUG_RE.match(row.slug):
        raise api_error(400, "bad_slug", "链接标识不合法，请先改成小写字母/数字/连字符")

    path = os.path.join(SITE_DIR, "content", f"{row.slug}.md")
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(_md(row))
    except Exception as exc:  # noqa: BLE001
        raise api_error(500, "write_failed", f"写入文章失败：{exc}")

    result = rebuild_and_deploy()
    if not result["ok"]:
        if result.get("busy"):
            raise api_error(409, "busy", result["message"])
        raise api_error(500, "publish_failed", result["message"])

    row.status = "published"
    row.published_at = utcnow()
    row.updated_at = utcnow()
    db.add(row)
    db.commit()
    return {
        "ok": True,
        "message": result["message"],
        "url": f"/blog/{row.slug}/",
        "article": _serialize(row, with_body=True),
    }


@router.post("/admin/blog/rebuild")
def rebuild_site(
    user: User = Depends(require_admin), db: Session = Depends(get_db)
) -> dict:
    """仅重新构建并部署（用于手工改过模板/内容后的重新上线）"""
    result = rebuild_and_deploy()
    if not result["ok"]:
        if result.get("busy"):
            raise api_error(409, "busy", result["message"])
        raise api_error(500, "rebuild_failed", result["message"])
    return {"ok": True, "message": result["message"]}
