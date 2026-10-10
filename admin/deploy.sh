#!/usr/bin/env bash
# 后台前端部署：本地构建（打资源指纹）→ 同步到服务器站点根目录 /admin/
#
# 与官网部署解耦：后台自己构建、自己发布，官网站点重建不会碰这里。
set -euo pipefail
cd "$(dirname "$0")"

HOST="${ZGJ_SSH:-zhiguanjia}"
WEB="${ZGJ_WEB_ROOT:-/www/wwwroot/zhidongni.com.cn}"

python3 build.py
tar czf - -C dist . | ssh "$HOST" "set -e
  D=$WEB/admin
  mkdir -p \$D
  find \$D -mindepth 1 -delete
  tar xzf - -C \$D
  chown -R www:www \$D
  chmod 755 \$D && find \$D -type f -exec chmod 644 {} \\;
  echo '  已部署后台前端 → '\$D"
