/* 职管家管理后台 · 壳（零依赖）
 *
 * 架构约定（加新模块只需两步）：
 *   1. 新建 modules/xxx.js，调用 ZGJ.registerModule({id, name, icon, render})
 *   2. 在 index.html 里加一行 <script src="modules/xxx.js"></script>
 * 壳负责：登录态、导航、路由、刷新、错误提示；模块只管把数据画出来。
 */
window.ZGJ = (function () {
  'use strict';

  var API = location.origin + '/api';
  var TOKEN_KEY = 'zgj_admin_token';
  var ACCOUNT_KEY = 'zgj_admin_account';
  var modules = [];
  var current = null;

  /* ────────────── DOM 工具 ────────────── */
  function $(id) { return document.getElementById(id); }

  function el(tag, attrs, children) {
    var node = document.createElement(tag);
    if (attrs) {
      Object.keys(attrs).forEach(function (k) {
        if (k === 'class') node.className = attrs[k];
        else if (k === 'text') node.textContent = attrs[k];
        else if (k === 'html') node.innerHTML = attrs[k];
        else if (k.slice(0, 2) === 'on') node.addEventListener(k.slice(2), attrs[k]);
        else node.setAttribute(k, attrs[k]);
      });
    }
    (children || []).forEach(function (c) { if (c) node.appendChild(c); });
    return node;
  }

  function card(title, body) {
    return el('div', { class: 'card' }, [title ? el('h3', { text: title }) : null].concat(body || []));
  }

  /* ────────────── API ────────────── */
  function token() { return sessionStorage.getItem(TOKEN_KEY) || ''; }

  function request(method, path, opts) {
    opts = opts || {};
    var headers = { 'Content-Type': 'application/json' };
    if (opts.auth !== false && token()) headers['Authorization'] = 'Bearer ' + token();
    return fetch(API + path, {
      method: method,
      headers: headers,
      body: opts.body ? JSON.stringify(opts.body) : undefined
    }).then(function (res) {
      return res.text().then(function (raw) {
        var data = null;
        try { data = raw ? JSON.parse(raw) : null; } catch (e) { /* 非 JSON */ }
        if (!res.ok) {
          var msg = (data && data.error && data.error.message) || ('请求失败（HTTP ' + res.status + '）');
          var err = new Error(msg);
          err.status = res.status;
          throw err;
        }
        return data;
      });
    });
  }

  var api = {
    login: function (phone, password) {
      return request('POST', '/auth/login', { auth: false, body: { phone: phone, password: password } });
    },
    stats: function () { return request('GET', '/admin/stats'); },
    trend: function (days) { return request('GET', '/admin/trend?days=' + (days || 14)); },

    // ── 博客发布管理 ──
    blogList: function () { return request('GET', '/admin/blog'); },
    blogGet: function (id) { return request('GET', '/admin/blog/' + id); },
    blogSave: function (data, id) {
      return request('POST', '/admin/blog' + (id ? '?article_id=' + id : ''), { body: data });
    },
    blogDelete: function (id) { return request('DELETE', '/admin/blog/' + id); },
    blogPublish: function (id) { return request('POST', '/admin/blog/' + id + '/publish'); },
    // ── 公告与配置 ──
    configGet: function () { return request('GET', '/admin/config'); },
    configSave: function (data) { return request('POST', '/admin/config', { body: data }); },

    // ── 系统管理 ──
    systemStatus: function () { return request('GET', '/admin/system/status'); },
    backupList: function () { return request('GET', '/admin/backup'); },
    backupCreate: function () { return request('POST', '/admin/backup'); },
    backupRestore: function (name, parts) {
      return request('POST', '/admin/backup/' + name + '/restore?confirm=RESTORE&parts=' + parts);
    },
    backupDelete: function (name) { return request('DELETE', '/admin/backup/' + name); },
    systemRebuild: function () { return request('POST', '/admin/system/rebuild'); }
  };

  /* ────────────── 视图切换 ────────────── */
  function showLogin(errMsg) {
    $('app-view').hidden = true;
    $('login-view').hidden = false;
    var box = $('login-err');
    if (errMsg) { box.textContent = errMsg; box.hidden = false; } else { box.hidden = true; }
  }

  function showApp() {
    $('login-view').hidden = true;
    $('app-view').hidden = false;
    $('who').textContent = '当前账号：' + (sessionStorage.getItem(ACCOUNT_KEY) || '-');
    if (!modules.length) return;
    if (!current) current = modules[0].id;
    renderNav();
    route();
  }

  /* ────────────── 导航与路由 ────────────── */
  function renderNav() {
    var nav = $('nav');
    nav.innerHTML = '';
    modules.forEach(function (m) {
      var a = el('a', {
        href: '#/' + m.id,
        class: (m.id === current ? 'on ' : '') + (m.planned ? 'soon' : '')
      }, [
        el('span', { class: 'ico', text: m.icon || '·' }),
        el('span', { text: m.name }),
        m.planned ? el('span', { class: 'tag', text: '规划中' }) : null
      ]);
      nav.appendChild(a);
    });
  }

  function route() {
    var id = (location.hash || '').replace(/^#\/?/, '') || modules[0].id;
    var mod = modules.filter(function (m) { return m.id === id; })[0] || modules[0];
    current = mod.id;
    renderNav();
    $('page-title').textContent = mod.name;
    $('updated-at').textContent = '';
    var box = $('content');
    box.innerHTML = '';
    if (mod.planned) {
      box.appendChild(el('div', { class: 'planned' }, [
        el('div', { class: 'big', text: mod.name + ' · 规划中' }),
        el('div', { text: mod.desc || '该模块将在后续迭代中加入。' })
      ]));
      return;
    }
    try {
      mod.render(box, ctx());
    } catch (e) {
      // "xxx is not a function" 基本都是**浏览器缓存了旧脚本**（版本错配）：
      // 资源已加内容指纹，硬刷新一次即可；这里给可执行提示而不是原始报错。
      var stale = /is not a function/.test(e.message || '');
      box.appendChild(el('div', { class: 'err-box', text: stale
        ? '后台脚本版本不一致（多半是浏览器缓存了旧版）。请强制刷新一次：电脑按 Ctrl+Shift+R，手机可清除该站点缓存。'
        : '渲染失败：' + e.message }));
    }
  }

  function ctx() {
    return {
      api: api, el: el, card: card,
      setUpdated: function (iso) {
        // 兜底：无时区后缀的 ISO 按 UTC 解析，避免本地时区差 8 小时
        var d = iso
          ? new Date(/[zZ]|[+-]\d\d:?\d\d$/.test(iso) ? iso : iso + 'Z')
          : new Date();
        $('updated-at').textContent = '更新于 ' + pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds());
      },
      refresh: function () { route(); },
      fail: function (box, e) {
        box.innerHTML = '';
        var msg = e && e.status === 403 ? '该账号没有管理权限' :
          (e && e.status === 401 ? '登录已过期，请重新登录' : ('数据加载失败：' + (e ? e.message : '未知错误')));
        box.appendChild(el('div', { class: 'err-box', text: msg }));
        if (e && e.status === 401) { sessionStorage.removeItem(TOKEN_KEY); setTimeout(logout, 1200); }
      }
    };
  }

  function pad(n) { return (n < 10 ? '0' : '') + n; }

  /* ────────────── 登录 / 退出 ────────────── */
  function doLogin(phone, password) {
    var btn = $('login-btn');
    btn.disabled = true;
    btn.textContent = '登录中…';
    $('login-err').hidden = true;
    api.login(phone, password).then(function (r) {
      sessionStorage.setItem(TOKEN_KEY, r.access_token || '');
      sessionStorage.setItem(ACCOUNT_KEY, phone);
      return api.stats(); // 顺便校验管理员权限
    }).then(function () {
      showApp();
    }).catch(function (e) {
      sessionStorage.removeItem(TOKEN_KEY);
      showLogin(e.status === 403 ? '该账号没有管理权限（仅管理员可登录后台）'
        : (e.status === 401 || /密码|账号/.test(e.message) ? '手机号或密码不正确' : e.message));
    }).then(function () {
      btn.disabled = false;
      btn.textContent = '登录';
    });
  }

  function logout() {
    sessionStorage.removeItem(TOKEN_KEY);
    sessionStorage.removeItem(ACCOUNT_KEY);
    showLogin();
  }

  /* ────────────── 注册与启动 ────────────── */
  function registerModule(mod) { modules.push(mod); }

  function boot() {
    $('login-form').addEventListener('submit', function (ev) {
      ev.preventDefault();
      var phone = $('login-phone').value.trim();
      var pwd = $('login-password').value;
      if (!phone || !pwd) return;
      doLogin(phone, pwd);
    });
    $('logout-btn').addEventListener('click', logout);
    $('refresh-btn').addEventListener('click', function () { ctx().refresh(); });
    $('menu-btn').addEventListener('click', function () {
      $('sidebar').classList.toggle('open');
    });
    window.addEventListener('hashchange', function () {
      if ($('app-view').hidden) return;
      route();
      $('sidebar').classList.remove('open');
    });

    if (!token()) { showLogin(); return; }
    // 已有登录态：先校验权限，失败则回登录页
    api.stats().then(function () { showApp(); }).catch(function () {
      sessionStorage.removeItem(TOKEN_KEY);
      showLogin('登录已过期，请重新登录');
    });
  }

  return { registerModule: registerModule, boot: boot, api: api };
})();
