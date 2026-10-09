#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""职管家官网 · 静态站构建脚本

零依赖（只用 Python 标准库）：把 content/*.md 渲染成 dist/ 下的纯静态 HTML。
服务器上不需要 Python、不需要数据库，Nginx 直出 dist/ 即可。

用法：
    python3 site/build.py          # 构建到 site/dist/
    python3 site/build.py --serve  # 构建并起本地预览（http://127.0.0.1:8080）
"""

import html
import os
import re
import shutil
import sys
import datetime
import http.server
import socketserver

ROOT = os.path.dirname(os.path.abspath(__file__))
DIST = os.path.join(ROOT, "dist")
TPL = os.path.join(ROOT, "templates")
CONTENT = os.path.join(ROOT, "content")
STATIC = os.path.join(ROOT, "static")

# ── 站点常量（换域名时只改这一处）──
SITE_URL = "http://8.137.71.241"
SITE_NAME = "职管家"
SITE_DESC = "每个人，都值得一个终身陪伴的 AI 职业管家。职业规划、简历优化、求职面试、技能成长、薪酬谈判、职场法律。"
APP_VERSION = "v1.0.45"
APP_APK = "zhiguanjia-v1.0.45.apk"
LATEST_ON_HOME = 3

# 备案期间保持 False（搜索引擎不收录 IP 地址）；域名上线后改成 True 即可
ALLOW_INDEX = False


# ────────────────────────── Markdown 子集渲染 ──────────────────────────
def _inline(s):
    s = html.escape(s, quote=False)
    s = re.sub(r"!\[([^\]]*)\]\(([^)]+)\)", r'<img src="\2" alt="\1">', s)
    s = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    return s


def md_to_html(md):
    lines = md.split("\n")
    out, i = [], 0
    while i < len(lines):
        line = lines[i].rstrip()
        if not line.strip():
            i += 1
            continue
        m = re.match(r"^(#{1,6})\s+(.*)$", line)
        if m:
            lv, txt = len(m.group(1)), m.group(2)
            out.append("<h%d>%s</h%d>" % (lv, _inline(txt), lv))
            i += 1
            continue
        if line.startswith("> "):
            buf = []
            while i < len(lines) and lines[i].startswith("> "):
                buf.append(lines[i][2:])
                i += 1
            out.append("<blockquote>%s</blockquote>" % _inline(" ".join(buf)))
            continue
        if re.match(r"^[-*]\s+", line):
            items = []
            while i < len(lines) and re.match(r"^[-*]\s+", lines[i]):
                items.append(_inline(re.sub(r"^[-*]\s+", "", lines[i])))
                i += 1
            out.append("<ul>%s</ul>" % "".join("<li>%s</li>" % x for x in items))
            continue
        if re.match(r"^\d+\.\s+", line):
            items = []
            while i < len(lines) and re.match(r"^\d+\.\s+", lines[i]):
                items.append(_inline(re.sub(r"^\d+\.\s+", "", lines[i])))
                i += 1
            out.append("<ol>%s</ol>" % "".join("<li>%s</li>" % x for x in items))
            continue
        buf = []
        while i < len(lines) and lines[i].strip() and not re.match(
            r"^(#{1,6}\s|[-*]\s|\d+\.\s|>\s)", lines[i]
        ):
            buf.append(lines[i].strip())
            i += 1
        out.append("<p>%s</p>" % _inline(" ".join(buf)))
    return "\n".join(out)


def cn_date(iso):
    try:
        d = datetime.date.fromisoformat(iso)
    except ValueError:
        return iso
    return "%d 年 %d 月 %d 日" % (d.year, d.month, d.day)


def parse_post(path):
    raw = open(path, encoding="utf-8").read()
    meta, body = {}, raw
    if raw.startswith("---"):
        parts = raw.split("---", 2)
        if len(parts) >= 3:
            for line in parts[1].strip().split("\n"):
                if ":" in line:
                    k, v = line.split(":", 1)
                    meta[k.strip()] = v.strip()
            body = parts[2]
    slug = os.path.splitext(os.path.basename(path))[0]
    meta.setdefault("title", slug)
    meta.setdefault("date", "")
    meta.setdefault("excerpt", "")
    return slug, meta, body.strip()


# ────────────────────────── 渲染 ──────────────────────────
def tpl(name):
    return open(os.path.join(TPL, name), encoding="utf-8").read()


def page(title, desc, body, home_on="", blog_on=""):
    robots = "" if ALLOW_INDEX else '<meta name="robots" content="noindex, nofollow">'
    return (
        tpl("base.html")
        .replace("{{ROBOTS_META}}", robots)
        .replace("{{TITLE}}", title)
        .replace("{{DESC}}", desc)
        .replace("{{BODY}}", body)
        .replace("{{HOME_ON}}", home_on)
        .replace("{{BLOG_ON}}", blog_on)
    )


def post_card(p):
    slug, meta, _ = p
    excerpt = meta["excerpt"] or ""
    return (
        '<a class="post-item" href="/blog/%s/">\n'
        "  <h3>%s</h3>\n"
        "  <time>%s</time>\n"
        "  <p>%s</p>\n"
        '  <span class="more">阅读全文 →</span>\n'
        "</a>" % (slug, html.escape(meta["title"]), cn_date(meta["date"]), html.escape(excerpt))
    )


def write(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


def build():
    if os.path.exists(DIST):
        shutil.rmtree(DIST)
    os.makedirs(DIST)

    # 静态资源
    assets = os.path.join(DIST, "assets")
    os.makedirs(assets)
    for f in ("style.css", "icon.png", "qr.png"):
        shutil.copy(os.path.join(STATIC, f), os.path.join(assets, f))

    # 文章
    posts = sorted(
        (parse_post(os.path.join(CONTENT, f))
         for f in os.listdir(CONTENT) if f.endswith(".md")),
        key=lambda p: p[1]["date"], reverse=True,
    )

    # 首页
    home = tpl("home.html")
    home = home.replace("{{VERSION}}", APP_VERSION)
    home = home.replace("{{APK}}", APP_APK)
    ak = os.path.join(STATIC, APP_APK)
    size = "%.1f MB" % (os.path.getsize(ak) / 1048576.0) if os.path.exists(ak) else "-"
    home = home.replace("{{SIZE}}", size)
    home = home.replace("{{LATEST_POSTS}}", "\n".join(post_card(p) for p in posts[:LATEST_ON_HOME]))
    write(os.path.join(DIST, "index.html"), page(SITE_NAME + " · AI 职业管家", SITE_DESC, home, home_on=' class="on"'))

    # 博客列表
    blog = tpl("blog.html").replace("{{POSTS}}", "\n".join(post_card(p) for p in posts) or "<p>还没有文章。</p>")
    write(os.path.join(DIST, "blog", "index.html"),
          page("博客 · " + SITE_NAME, "职管家的职业内容阵地：" + SITE_DESC, blog, blog_on=' class="on"'))

    # 文章页
    for slug, meta, body in posts:
        art = tpl("post.html")
        art = art.replace("{{TITLE}}", html.escape(meta["title"]))
        art = art.replace("{{DATE}}", cn_date(meta["date"]))
        art = art.replace("{{CONTENT}}", md_to_html(body))
        write(os.path.join(DIST, "blog", slug, "index.html"),
              page(meta["title"] + " · " + SITE_NAME, meta["excerpt"] or SITE_DESC, art, blog_on=' class="on"'))

    # 下载页（保持 /zhiguanjia/ 路径不变，二维码长期有效）
    dl = os.path.join(DIST, "zhiguanjia")
    os.makedirs(dl)
    src_page = os.path.join(ROOT, "download", "index.html")
    if os.path.exists(src_page):
        shutil.copy(src_page, os.path.join(dl, "index.html"))
    shutil.copy(os.path.join(STATIC, "qr.png"), os.path.join(dl, "qr.png"))
    if os.path.exists(ak):
        shutil.copy(ak, os.path.join(dl, APP_APK))

    # 404 页
    write(os.path.join(DIST, "404.html"),
          page("页面不存在 · " + SITE_NAME, "页面不存在", tpl("404.html")))

    # robots.txt（备案期间禁止收录；ALLOW_INDEX=True 时放行）
    if ALLOW_INDEX:
        robots_txt = "User-agent: *\nDisallow: /wp-admin/\nAllow: /\n\nSitemap: %s/sitemap.xml\n" % SITE_URL
    else:
        robots_txt = "User-agent: *\nDisallow: /\n"
    write(os.path.join(DIST, "robots.txt"), robots_txt)

    # sitemap / rss
    urls = [("/", ""), ("/blog/", "weekly")]
    for slug, meta, _ in posts:
        urls.append(("/blog/%s/" % slug, meta["date"]))
    sm = ['<?xml version="1.0" encoding="UTF-8"?>',
          '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">']
    for u, d in urls:
        sm.append("  <url><loc>%s%s</loc>%s</url>" % (
            SITE_URL, u, ("<lastmod>%s</lastmod>" % d) if re.match(r"^\d{4}-", d or "") else ""))
    sm.append("</urlset>")
    write(os.path.join(DIST, "sitemap.xml"), "\n".join(sm))

    items = []
    for slug, meta, _ in posts[:20]:
        try:
            rfc = datetime.datetime.fromisoformat(meta["date"]).strftime("%a, %d %b %Y 00:00:00 +0800")
        except ValueError:
            rfc = ""
        items.append(
            "<item><title>%s</title><link>%s/blog/%s/</link><guid>%s/blog/%s/</guid><pubDate>%s</pubDate>"
            "<description>%s</description></item>"
            % (html.escape(meta["title"]), SITE_URL, slug, SITE_URL, slug, rfc, html.escape(meta["excerpt"]))
        )
    write(os.path.join(DIST, "rss.xml"),
          '<?xml version="1.0" encoding="UTF-8"?>\n<rss version="2.0"><channel>'
          "<title>%s</title><link>%s/</link><description>%s</description>%s</channel></rss>"
          % (SITE_NAME, SITE_URL, SITE_DESC, "".join(items)))

    n = sum(len(fs) for _, _, fs in os.walk(DIST))
    print("构建完成 → %s" % DIST)
    print("  页面/文件数: %d   文章数: %d   首页最新文章: %d" % (n, len(posts), min(len(posts), LATEST_ON_HOME)))
    print("  下载页: /zhiguanjia/   APK: %s (%s)" % (APP_APK, size))


def serve():
    os.chdir(DIST)
    handler = http.server.SimpleHTTPRequestHandler
    with socketserver.TCPServer(("127.0.0.1", 8080), handler) as s:
        print("本地预览: http://127.0.0.1:8080/  (Ctrl+C 结束)")
        s.serve_forever()


if __name__ == "__main__":
    build()
    if "--serve" in sys.argv:
        serve()
