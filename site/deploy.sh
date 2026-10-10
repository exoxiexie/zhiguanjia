#!/usr/bin/env bash
# 官网部署：同步站点源码 → 服务器上构建 → 同步到站点根目录
#
# ⚠️ 关键：**排除 content/ 与 dist/**
#   content/ 是文章正文，真实来源是服务器（后台「博客发布管理」写入/删除）。
#   若把本地 content/ 覆盖上去，会把后台已删除的文章"复活" —— 2026-10-10 踩过，
#   因此这里显式排除，并由本脚本统一负责部署（不要再用裸 tar 命令）。
set -euo pipefail
cd "$(dirname "$0")"

HOST="${ZGJ_SSH:-zhiguanjia}"
DEST="${ZGJ_SITE_DIR:-/www/wwwroot/zhiguanjia-site}"
PY="${ZGJ_PY:-/www/wwwroot/zhiguanjia-api/venv/bin/python}"

# 站点源码（不含 content / dist）
tar czf - --exclude dist --exclude content --exclude '__pycache__' . | ssh "$HOST" "set -e
  mkdir -p $DEST/content
  tar xzf - -C $DEST
  chown -R www:www $DEST"

# 版本信息（后台「强制更新」里会显示"当前官网版本"）
scp -q "$(cd .. && pwd)/version.json" "$HOST:$DEST/version.json"
ssh "$HOST" "chown www:www $DEST/version.json"

# 构建 + 发布（与后台「发布站点」同一条链路）
ssh "$HOST" "set -e
  cd $DEST
  sudo -u www $PY build.py >/dev/null
  sudo -u www $PY sync_site.py"
