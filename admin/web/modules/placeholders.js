/* 管理后台 · 规划中模块（占位）
 *
 * 作用：把后台的**架构版图**先摆出来（谁在、边界在哪），
 * 但明确标注"规划中"，不假装已实现。
 * 每个模块落地时：删掉这里的注册，新建 modules/xxx.js 并按真实逻辑实现。
 */
ZGJ.registerModule({
  id: 'users', name: '用户管理', icon: '👤', planned: true,
  desc: '用户列表与检索、实名状态、设备与登录情况、封禁/解封、代运营操作。'
});
ZGJ.registerModule({
  id: 'content', name: '内容审核', icon: '📝', planned: true,
  desc: '用户说说与对话内容的巡检、举报处理、违规内容下架（含审计日志）。'
    + '官网博客的发布管理见「博客发布管理」。'
});
ZGJ.registerModule({
  id: 'config', name: '公告与配置', icon: '📣', planned: true,
  desc: '公告下发、强制更新版本、功能开关（含测试入口灰度名单）—— 目前由接口与数据库直接维护，将图形化。'
});
ZGJ.registerModule({
  id: 'feedback', name: '反馈处理', icon: '💬', planned: true,
  desc: '用户反馈与问题工单的收集、分派、跟进与归档。'
});
