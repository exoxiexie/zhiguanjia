/* 后台前端冒烟测试（离线可跑，不依赖服务器）
 *
 * 用极简 DOM 桩 + 桩化 fetch 把壳与各模块真跑一遍，
 * 断言：模块注册齐全、每个模块都能渲染出关键内容、不出现渲染失败。
 *
 * 运行：node admin/tests/smoke.js   （退出码 0 = 通过）
 */
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..', 'web');

/* ── DOM 桩 ── */
function makeEl(tag) {
  const n = {
    tagName: tag, children: [], _text: '', hidden: false, className: '', style: {},
    classList: { add() {}, remove() {}, toggle() {} },
    appendChild(c) { this.children.push(c); return c; },
    setAttribute(k, v) { this[k] = v; }, addEventListener() {}, removeEventListener() {},
    querySelectorAll() { return []; },
    set innerHTML(v) { this.children = []; this._html = v; },
    get innerHTML() { return this._html || ''; },
    set textContent(v) { this._text = String(v); this.children = []; },
    get textContent() { return this._text; }
  };
  n.getText = function () {
    return (this._text || '') + ' ' + this.children.map(c => (c.getText ? c.getText() : '')).join(' ');
  };
  return n;
}
const IDS = ['login-view', 'app-view', 'login-form', 'login-phone', 'login-password',
  'login-err', 'login-btn', 'logout-btn', 'refresh-btn', 'menu-btn', 'sidebar', 'who',
  'nav', 'page-title', 'updated-at', 'content'];
const dom = {};
IDS.forEach(i => { dom[i] = makeEl('div'); dom[i].value = ''; });
global.document = { getElementById: i => dom[i] || null, createElement: makeEl, addEventListener() {} };
global.window = { addEventListener() {}, ZGJ: null };
global.location = { origin: 'http://admin.test', hash: '#/dashboard', href: '' };
const store = {};
global.sessionStorage = {
  getItem: k => (k in store ? store[k] : null),
  setItem: (k, v) => { store[k] = String(v); }, removeItem: k => { delete store[k]; }
};

/* ── 桩化后端（固定数据，断言稳定）── */
const FIXTURES = {
  '/auth/login': { access_token: 'test-token' },
  '/admin/stats': {
    devices: { total: 12, active_1d: 5, active_7d: 8, active_30d: 10, new_1d: 1, new_7d: 4 },
    users: { total: 9, verified: 3, new_1d: 0, new_7d: 2 },
    versions: [{ version: '1.0.49', devices: 8, share: 66.7 }],
    platforms: [{ platform: 'android', devices: 12, share: 100 }],
    content: { conversations: 30, messages: 400, memories: 20, posts: 4, experiences: 6,
      favorites: 2, search_items: 5 },
    engagement: { users_with_conversations: 6, conversations_per_user: 5, messages_per_conversation: 13.3, conversion: 66.7 },
    generated_at: '2026-10-10T00:00:00+00:00'
  },
  '/admin/trend': { days: 3, items: [
    { date: '2026-10-08', new_devices: 1, new_users: 0, messages: 10, conversations: 2, posts: 0 },
    { date: '2026-10-09', new_devices: 2, new_users: 1, messages: 20, conversations: 3, posts: 1 },
    { date: '2026-10-10', new_devices: 0, new_users: 0, messages: 5, conversations: 1, posts: 0 }] },
  '/admin/blog': { items: [{ id: 'a1', slug: 'hello', title: '示例文章', author: '老谢',
    date: '2026-10-10', status: 'published', url: '/blog/hello/' }], site_dir: '/srv/site', site_dir_ready: true },
  '/admin/config': {
    announcement: { enabled: false, id: 'a1', title: '维护通知', body: '今晚维护' },
    min_version: { version_code: 0, version_name: '', url: '', note: '' },
    flags: { test_panel: false, test_panel_phones: ['13608074995'] },
    updated_by: '13608074995', updated_at: '2026-10-10T08:00:00',
    release: { version_name: '1.0.49', version_code: 50, url: 'https://x/a.apk', changelog: '修复同步' }
  },
  '/admin/release': { items: [{ id: 'r1', version_name: '1.0.50', version_code: 51,
      size: 10485760, sha256: 'a'.repeat(64), changelog: '修复', force_update: false,
      status: 'draft', created_at: '2026-10-10 10:00:00' }],
    current: { version_name: '1.0.49', version_code: 50, url: 'http://x/a.apk', changelog: '旧' },
    apk_dir: '/srv/site/static' },
  '/admin/audit': { items: [{ id: 2, actor: '13608074995', action: '/admin/blog/{id}/publish',
      method: 'POST', target: '文章《示例》', status: 200, ok: true, ip: '1.2.3.4',
      duration_ms: 320, created_at: '2026-10-10 09:30:00' }],
    total: 1, keep: 5000, actions: ['/admin/blog/{id}/publish'] },
  '/admin/backup': { items: [{ name: '20261010-090000-manual', size: 2048,
      created_at: '2026-10-10T09:00:00', parts: ['db.sql.gz', 'site-content.tar.gz'] }],
    dir: '/www/backups/zhiguanjia', keep: 10, parts: ['db', 'content', 'uploads', 'etc'],
    disk: { total: 42949672960, free: 31138512896, used: 11811160064 },
    last_auto: null, server_time: '2026-10-10T09:00:00' },
  '/admin/system/status': { api_version: '0.7.0', server_time: '2026-10-10T08:00:00',
    site_dir: '/srv/site', site_dir_ready: true, web_root: '/srv/web', web_root_ready: true,
    articles: 1, articles_published: 1, users: 9,
    last_build: { ok: true, message: '已重新构建并发布到官网', at: '2026-10-10T08:00:00' } }
};
global.fetch = (url, opts) => {
  // 去掉 origin 与 /api 前缀，落到固定桩数据上
  const u = String(url).replace(/^https?:\/\/[^/]+/, '').replace(/^\/api/, '');
  const key = u.split('?')[0];
  const body = FIXTURES[key] !== undefined ? FIXTURES[key] : (opts && opts.method !== 'GET' ? { ok: true } : {});
  return Promise.resolve({ ok: true, status: 200, text: () => Promise.resolve(JSON.stringify(body)) });
};

/* ── 加载前端 ── */
const pass = [], fail = [];
function check(name, cond, extra) {
  (cond ? pass : fail).push(name);
  console.log((cond ? '  ✅ ' : '  ❌ ') + name + (!cond && extra ? '  → ' + String(extra).slice(0, 160) : ''));
}

eval(fs.readFileSync(path.join(ROOT, 'admin.js'), 'utf8'));
global.ZGJ = window.ZGJ;
const html = fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8');
const mods = [...html.matchAll(/src="(modules\/[^"?]+)/g)].map(m => m[1]);
mods.forEach(m => eval(fs.readFileSync(path.join(ROOT, m), 'utf8')));

(async () => {
  store['zgj_admin_token'] = 'test-token';
  store['zgj_admin_account'] = '13900000000';
  window.ZGJ.boot();
  await new Promise(r => setTimeout(r, 300));

  const nav = dom['nav'].getText().replace(/\s+/g, ' ');
  check('侧栏含全部模块（' + mods.length + ' 个模块文件）',
    ['运营看板', '博客发布管理', '系统管理'].every(n => nav.includes(n)), nav);

  async function visit(hash, expect) {
    global.location.hash = hash;
    window.ZGJ.boot();          // 重新进入（等价于刷新后首次渲染）
    await new Promise(r => setTimeout(r, 300));
    const t = dom['content'].getText().replace(/\s+/g, ' ');
    const bad = /渲染失败|加载失败|is not a function|版本不一致/.test(t);
    check('模块 ' + hash + ' 渲染出关键内容',
      expect.every(e => t.includes(e)) && !bad, t.slice(0, 200));
  }
  await visit('#/dashboard', ['装机设备', '活跃设备', '真在使用', '版本分布', '使用深度']);
  await visit('#/blog', ['新建文章', '示例文章', '已发布']);
  await visit('#/config', ['公告', '强制更新', '功能开关', '灰度手机号', '保存公告']);
  await visit('#/release', ['当前线上版本', '上传新版本', '发布记录', '上传安装包']);
  // 三栏：中栏分类卡片 + 右栏功能内容
  await visit('#/system', ['站点与发布', '备份与恢复', '操作审计', '规划中', '源码目录']);

  console.log('');
  console.log('  通过 ' + pass.length + ' 项，失败 ' + fail.length + ' 项');
  process.exit(fail.length ? 1 : 0);
})();
