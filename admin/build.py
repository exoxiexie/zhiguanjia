"""后台前端构建：给静态资源打内容指纹，产出 dist/。

为什么要独立于官网的 build.py：
后台是**独立产品**，它的资源版本、缓存策略、部署节奏都不应与官网捆绑
（此前后台寄生在 site/build.py 里，改官网构建就可能带到后台）。
"""

import hashlib
import os
import shutil

ROOT = os.path.dirname(os.path.abspath(__file__))
WEB = os.path.join(ROOT, "web")
DIST = os.path.join(ROOT, "dist")


def stamp(*paths) -> str:
    """按文件内容算指纹：内容一变 URL 就变，长缓存下更新也必达"""
    h = hashlib.sha256()
    for p in paths:
        try:
            with open(p, "rb") as f:
                h.update(f.read())
        except OSError:
            pass
    return h.hexdigest()[:10]


def build() -> str:
    if os.path.exists(DIST):
        shutil.rmtree(DIST)
    shutil.copytree(WEB, DIST)

    mod_dir = os.path.join(WEB, "modules")
    mods = sorted(os.listdir(mod_dir)) if os.path.isdir(mod_dir) else []
    code = stamp(WEB + "/admin.js", WEB + "/admin.css",
                 *[os.path.join(mod_dir, m) for m in mods])

    idx = os.path.join(DIST, "index.html")
    html = open(idx, encoding="utf-8").read()
    for ref in ("admin.css", "admin.js"):
        html = html.replace('"%s"' % ref, '"%s?v=%s"' % (ref, code))
    for m in mods:
        html = html.replace('"modules/%s"' % m, '"modules/%s?v=%s"' % (m, code))
    open(idx, "w", encoding="utf-8").write(html)
    return code


if __name__ == "__main__":
    print("后台构建完成，资源指纹：%s" % build())
