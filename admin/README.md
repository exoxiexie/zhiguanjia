# 职管家 · 后台管理系统

**这是一个独立产品**（面向运营/管理的 Web 后台），与 C 端 App、官网静态站同级。

## 目录

```
admin/
├─ web/                 前端源码（零依赖原生 JS，无构建依赖）
│   ├─ index.html       壳（登录视图 + 后台视图）
│   ├─ admin.js         壳逻辑：登录态 / 导航 / 路由 / API / 错误处理
│   ├─ admin.css        极简样式（与官网同一套视觉语言）
│   └─ modules/         各功能模块（一个模块 = 一个 js 文件 + 注册一行）
├─ build.py             构建：给资源打内容指纹 → dist/
├─ deploy.sh            构建并部署到服务器的 /admin/
└─ tests/smoke.js       前端冒烟测试（离线可跑，桩化后端）
```
后端在 `server/app/admin/`（同一进程，但目录/鉴权/测试自成一体）：

```
server/app/admin/
├─ deps.py       后台鉴权（权限边界唯一入口）
├─ stats.py      运营看板接口
├─ config.py     公告与配置（公告 / 强制更新 / 功能开关）
├─ release.py    版本发布（上传 APK → 写更新源 → 铺官网下载页）
├─ logs.py       操作审计查询 / audit.py 审计中间件
├─ blog.py       博客发布管理接口
├─ system.py     系统管理接口
├─ publisher.py  站点发布服务（构建 + 同步的唯一实现）
└─ router.py     聚合路由
```

## 约定（重要）

1. **加模块 = 加一个文件 + 注册一行**
   在 `web/modules/` 新建 `xxx.js`，调用 `ZGJ.registerModule({id,name,icon,render})`，
   再在 `index.html` 里加一行 `<script>`。壳负责导航/登录/刷新/错误提示，模块只管渲染。
2. **所有后台接口必须走 `Depends(require_admin)`**（`server/app/admin/deps.py`）。
3. **资源一律带内容指纹**（`build.py` 自动处理）：静态资源在服务器是 12 小时长缓存，
   不加指纹会出现"页面是新的、脚本还是旧的"（踩过）。
4. **HTML 必须 no-cache**：由服务器 nginx 对 `*.html` 下发
   `Cache-Control: no-cache, must-revalidate`（页面内容会随后台发布变化）。
5. **危险操作**（发布站点、删除）要有明确反馈且状态一定能恢复；
   请求加超时，避免按钮卡死。
6. **重构/替换代码时精确匹配 + 断言**：Dart/Python/JS 的 `replace` 静默失败过一次，
   导致"脚本报告成功但实际没改"。

## 开发与测试

```bash
# 前端构建（打指纹）
python3 admin/build.py

# 前端冒烟测试（离线，桩化后端；断言各模块渲染与无错误）
node admin/tests/smoke.js

# 后端接口测试（真实构建发布链路）
/tmp/zgj-venv/bin/python server/tests/test_admin_blog.py
/tmp/zgj-venv/bin/python server/tests/test_p5.py

# 部署前端（构建 + 同步到服务器 /admin/）
./admin/deploy.sh
```

## 部署铁律（踩过的坑）

**文章内容的真实来源是服务器**：`/www/wwwroot/zhiguanjia-site/content/*.md`
（后台「博客发布管理」写入与删除）。本地仓库的 `site/content/` 只留一份说明文件。

- ❌ 不要用裸 `tar` 把本地 `site/` 同步到服务器 —— 会把后台已删除的文章**复活**
  （2026-10-10 实际发生：删掉的文章随部署又回到线上）
- ✅ 官网部署一律用 `./site/deploy.sh`（已排除 `content/` 与 `dist/`，并负责构建+同步）
- ✅ 后台部署一律用 `./admin/deploy.sh`
- 两个脚本各自独立：官网重建不影响后台，后台发版不影响官网

## 安全现状

- 复用 App 账号体系（手机号 + 密码），管理员身份是 `users.is_admin` 标记
- 非管理员登录被拒（403）；令牌只存 sessionStorage，关标签页即失效
- 页面不进公开导航、`robots.txt` 禁止收录
- ⚠️ **开发期经 HTTP 登录**（密码明文过网）—— 备案完成切 HTTPS 后消除；
  后续计划：后台独立子域名 + IP 白名单 + 独立密码/二次验证（见 ROADMAP）
