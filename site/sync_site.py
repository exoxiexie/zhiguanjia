"""把 dist/ 构建产物同步到站点根目录。

**发布流程的唯一实现**：后台「博客发布管理」与命令行部署都调用它，
避免出现两套同步逻辑（少一处漏改就少一次线上不一致）。

同步策略（安全优先）：
- **合并覆盖**，不先删目录 —— 既没有"目录短暂消失"的窗口，
  也避免因历史文件归属不同（root/www）而删除失败
- `blog/` 下已下线的文章目录会被清理（删文章后页面同步消失）
- 不从根目录删除未知文件，避免误删运维放置的东西

⚠️ 归属约定：站点根目录与源码目录都必须是 `www:www`（API 以 www 运行）。
若曾用 root 手工构建过，执行一次 `chown -R www:www <目录>` 即可。
"""

import os
import shutil
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "dist")
DST = os.environ.get("ZGJ_WEB_ROOT", "/www/wwwroot/zhidongni.com.cn")


def _sync_blog(src: str, dst: str) -> None:
    """博客目录：合并文章，并清掉源里已不存在的文章目录"""
    os.makedirs(dst, exist_ok=True)
    keep = set(os.listdir(src))
    for name in os.listdir(dst):
        if name not in keep and os.path.isdir(os.path.join(dst, name)):
            shutil.rmtree(os.path.join(dst, name), ignore_errors=True)
    for name in keep:
        s, d = os.path.join(src, name), os.path.join(dst, name)
        if os.path.isdir(s):
            shutil.copytree(s, d, dirs_exist_ok=True)  # 合并覆盖
        else:
            shutil.copy2(s, d)


def sync(src: str = SRC, dst: str = DST) -> None:
    if not os.path.isdir(src):
        raise RuntimeError(f"构建产物目录不存在：{src}")
    if not os.path.isdir(dst):
        raise RuntimeError(f"站点根目录不存在：{dst}")
    for name in os.listdir(src):
        s, d = os.path.join(src, name), os.path.join(dst, name)
        if os.path.isdir(s):
            if name == "blog":
                _sync_blog(s, d)
            else:
                shutil.copytree(s, d, dirs_exist_ok=True)  # 合并覆盖
        else:
            shutil.copy2(s, d)


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else DST
    sync(SRC, target)
    print(f"已同步：{SRC} → {target}")
