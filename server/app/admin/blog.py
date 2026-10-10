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
import secrets

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..deps import get_db
from .deps import require_admin
from ..errors import api_error
from ..models import Article, User, new_uuid, utcnow
from .publisher import SITE_DIR, rebuild_and_deploy
from ..schemas import ArticleIn

router = APIRouter(tags=["admin-blog"])

# 允许：小写字母、数字、连字符、以及**中日韩汉字**（中文链接可读、对国内搜索友好）
# 禁止：斜杠、点、空白、控制字符等一切可能造成路径穿越或 URL 歧义的字符
_SLUG_RE = re.compile(r"^[0-9a-z\u4e00-\u9fff][0-9a-z\u4e00-\u9fff-]{0,63}$")
_NOT_ALLOWED_RE = re.compile(r"[^0-9a-z\u4e00-\u9fff]+")
_CST = datetime.timedelta(hours=8)


def make_slug(title: str) -> str:
    """按标题自动生成链接标识（作者不必关心这个字段）

    - 中文标题 → 中文链接（可读、易分享、国内搜索友好）
    - 英文/数字 → 转小写并把空格标点收成连字符
    - 标题全是符号/emoji → 回退为「post-日期-随机」
    """
    text = (title or "").strip().lower()
    slug = _NOT_ALLOWED_RE.sub("-", text)
    slug = re.sub(r"-{2,}", "-", slug).strip("-")[:64].strip("-")
    if not slug:
        slug = "post-%s-%s" % (
            (utcnow() + _CST).strftime("%Y%m%d"),
            secrets.token_hex(2),
        )
    return slug


def _today() -> str:
    return (utcnow() + _CST).date().isoformat()


def _time_of(a: Article, at=None) -> str:
    """发布时间（HH:MM，中国时间）：取首次发布时刻，重复发布不覆盖

    [at] 供发布流程传入"本次将要记录的时间" —— 因为写 Markdown 在落库之前，
    不能依赖 a.published_at 已经写好了。
    """
    moment = at or a.published_at
    if not moment:
        return ""
    return (moment + _CST).strftime("%H:%M")


def _published_at_of(date_str: str, time_str: str):
    """把「日期 + 时间（中国时间）」换算成库里的 UTC 时间；不合法返回 None"""
    try:
        d = datetime.date.fromisoformat((date_str or "").strip())
        hh, mm = ((time_str or "").strip().split(":") + ["0", "0"])[:2]
        return datetime.datetime(d.year, d.month, d.day, int(hh), int(mm)) - _CST
    except Exception:  # noqa: BLE001
        return None


def _md(a: Article, at=None) -> str:
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
        + (f"time: {_time_of(a, at)}\n" if _time_of(a, at) else "")
        + f"author: {a.author}\n"
        f"excerpt: {a.excerpt}\n"
        f"{tags}"
        "---\n\n"
        f"{a.body_md.strip()}\n"
    )


def _serialize(a: Article, with_body: bool = False) -> dict:
    out = {
        "id": a.id,
        "slug": a.slug,
        "title": a.title,
        "author": a.author,
        "date": a.date,
        "time": _time_of(a),
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


def _parse_front_matter(path: str) -> dict:
    """解析站点源文件里的 front-matter（与 site/build.py 保持同一种格式）"""
    meta: dict = {}
    try:
        raw = open(path, encoding="utf-8").read()
    except OSError:
        return meta
    body = raw
    if raw.startswith("---"):
        parts = raw.split("---", 2)
        if len(parts) >= 3:
            for line in parts[1].strip().split("\n"):
                if ":" in line:
                    k, v = line.split(":", 1)
                    meta[k.strip()] = v.strip()
            body = parts[2]
    meta["_body"] = body.strip()
    return meta


def sync_from_files(db: Session) -> int:
    """把站点源目录里**已存在但不在库里**的文章纳入后台。

    为什么需要：历史上（以及手工放置的）文章只存在于 `content/*.md`，
    后台列表看不到它们 —— 就出现"网站上有、后台里没有"的幽灵文章，
    既不能编辑也不能删除（用户真实反馈过"找不到删除的地方"）。
    以**文件为准**补录为已发布状态；文件不存在时静默跳过。
    """
    content_dir = os.path.join(SITE_DIR, "content")
    if not os.path.isdir(content_dir):
        return 0
    imported = 0
    try:
        names = [n for n in os.listdir(content_dir) if n.endswith(".md")]
    except OSError:
        return 0
    for name in names:
        slug = name[:-3]
        if db.scalar(select(Article).where(Article.slug == slug)) is not None:
            continue
        meta = _parse_front_matter(os.path.join(content_dir, name))
        row = Article(
            id=new_uuid(),
            slug=slug,
            title=(meta.get("title") or slug)[:200],
            author=(meta.get("author") or "老谢")[:64],
            date=(meta.get("date") or "")[:20],
            excerpt=(meta.get("excerpt") or "")[:500],
            tags_json=json.dumps(
                [t.strip() for t in (meta.get("tags") or "").split(",") if t.strip()],
                ensure_ascii=False,
            ),
            body_md=meta.get("_body", ""),
            status="published",
            created_at=utcnow(),
            updated_at=utcnow(),
            published_at=_published_at_of(meta.get("date", ""), meta.get("time", "")),
        )
        db.add(row)
        try:
            db.commit()
            imported += 1
        except IntegrityError:
            # 多 worker 并发导入同一篇文章时，先提交者胜出 —— 回滚即可，不该报错
            db.rollback()
    return imported


def _find_slug(db: Session, slug: str) -> Article:
    row = db.scalar(select(Article).where(Article.slug == slug))
    if row is None:
        raise api_error(404, "not_found", "文章不存在")
    return row


def _find(db: Session, article_id: str) -> Article:
    row = db.get(Article, article_id)
    if row is None:
        raise api_error(404, "not_found", "文章不存在")
    return row


@router.get("/admin/blog")
def list_articles(
    user: User = Depends(require_admin), db: Session = Depends(get_db)
) -> dict:
    """文章列表（不含正文，列表页够用且更快）

    开头会先做一次"文件 → 库"的补录：站点上真实存在的文章都要能在后台看见。
    """
    sync_from_files(db)
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
    title = (body.title or "").strip()
    if not title:
        raise api_error(400, "bad_title", "标题不能为空")

    provided = (body.slug or "").strip().lower()
    if provided:
        # 作者手动指定了链接：严格校验（防路径穿越/URL 歧义）
        if not _SLUG_RE.match(provided):
            raise api_error(
                400,
                "bad_slug",
                "自定义链接只能用「小写字母、数字、汉字、连字符」，且以字母/数字/汉字开头",
            )
        slug = provided
    else:
        # 未指定：按标题自动生成，作者完全不用关心
        slug = make_slug(title)

    # 唯一性：手动指定时冲突就报错；自动生成时顺延加 -2/-3
    def _taken(candidate: str) -> bool:
        row = db.scalar(select(Article).where(Article.slug == candidate))
        return row is not None and row.id != article_id

    if provided:
        if _taken(slug):
            raise api_error(409, "slug_taken", f"链接「{slug}」已被《{_find_slug(db, slug).title}》占用")
    else:
        base, n = slug, 1
        while _taken(slug) and n < 99:
            n += 1
            slug = f"{base}-{n}"

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
    # 作者显式填了时间 → 记为发布时间（补录历史文章用）；
    # 没填则留到首次发布时自动记录（重复发布不会改动它）
    explicit = _published_at_of(row.date, body.time)
    if explicit is not None:
        row.published_at = explicit

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

    # 先确定"本次发布时间"（首次发布=现在；已发布过则沿用原时间），
    # 因为 Markdown 要先写、构建成功后才落库 —— 顺序反了会导致
    # 首次发布的文件里没有时间（实测踩过）。
    publish_at = row.published_at or utcnow()

    path = os.path.join(SITE_DIR, "content", f"{row.slug}.md")
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(_md(row, publish_at))
    except Exception as exc:  # noqa: BLE001
        raise api_error(500, "write_failed", f"写入文章失败：{exc}")

    result = rebuild_and_deploy()
    if not result["ok"]:
        if result.get("busy"):
            raise api_error(409, "busy", result["message"])
        raise api_error(500, "publish_failed", result["message"])

    row.status = "published"
    row.published_at = publish_at
    row.updated_at = utcnow()
    db.add(row)
    db.commit()
    return {
        "ok": True,
        "message": result["message"],
        "url": f"/blog/{row.slug}/",
        "article": _serialize(row, with_body=True),
    }
