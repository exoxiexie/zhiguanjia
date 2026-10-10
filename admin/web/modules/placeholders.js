(function () {
  'use strict';

  /* 管理后台 · 规划中模块（占位）
   *
   * 作用：把后台的**架构版图**先摆出来（谁在、边界在哪），
   * 但明确标注"规划中"，不假装已实现。
   * 每个模块落地时：删掉这里的注册，新建 modules/xxx.js 并按真实逻辑实现。
   */
    ZGJ.registerModule({
    id: 'feedback', name: '反馈处理', icon: '💬', planned: true,
    desc: '用户反馈与问题工单的收集、分派、跟进与归档。'
  });
})();
