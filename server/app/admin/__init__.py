"""后台管理系统（独立产品边界）

目录职责：
- `deps.py`      后台鉴权（权限边界唯一入口）
- `stats.py`     运营看板接口
- `blog.py`      博客发布管理接口
- `system.py`    系统管理接口（站点状态 / 发布站点）
- `config.py`    公告与配置（公告 / 强制更新 / 功能开关）
- `config.py`    公告与配置（公告 / 强制更新 / 功能开关）
- `backup.py`    备份与恢复接口（实现在 backup_service.py）
- `audit.py`     操作审计中间件（自动捕获所有 /admin 写操作）
- `logs.py`      操作审计查询接口
- `release.py`   版本发布（上传 APK → 写更新源 → 铺官网下载页 → 重建发布）
- `users.py`     用户管理（检索 / 详情 / 停用恢复 / 管理员开关 / 重置密码）
- `content.py`   内容审核（说说巡检 / 下架与恢复；对话属私密不做批量巡检）
- `publisher.py` 站点发布服务（构建 + 同步的唯一实现）
- `router.py`    聚合三组路由，供 main.py 一次挂载

与业务 API 的关系：**刻意共用同一套账号体系与同一个数据库**
（避免重复实现认证与模型），但目录、鉴权、测试与文档都自成一体。
将来若要拆成独立服务或子域名（如备案后上 admin.域名），按此边界抽走即可。
"""

from .deps import require_admin
from .router import router

__all__ = ["router", "require_admin"]
