/* 模块：系统管理
 *
 * 定位：**站点级 / 系统级操作**的统一入口。
 * 内容模块（博客、用户、审核）只管内容；发布站点、备份、日志、权限、定时任务
 * 这类"作用于整个系统"的能力都收到这里。
 *
 * 加新功能的方式：在对应分区里加一行（真实功能）或一条 soon-row（规划中），
 * 不必新增一级菜单。
 */
ZGJ.registerModule({
  id: 'system',
  name: '系统管理',
  icon: '⚙️',

  render: function (box, ctx) {
    renderStatus(box, ctx);
  }
});

function renderStatus(box, ctx) {
  var el = ctx.el;
  box.innerHTML = '';
  box.appendChild(el('div', { class: 'loading', text: '加载中…' }));

  ctx.api.systemStatus().then(function (s) {
    box.innerHTML = '';

    /* ── 站点 ── */
    box.appendChild(el('div', { class: 'section-title', text: '站点' }));
    var lb = s.last_build;
    box.appendChild(el('div', { class: 'card' }, [
      row(el, '源码目录', s.site_dir, 'mono', s.site_dir_ready ? '就绪' : '缺失'),
      row(el, '站点根目录', s.web_root, 'mono', s.web_root_ready ? '就绪' : '缺失'),
      row(el, '文章', s.articles + ' 篇（已发布 ' + s.articles_published + '）'),
      row(el, '用户', s.users + ' 人'),
      row(el, '接口版本', s.api_version + '　服务器时间 ' + s.server_time),
      row(el, '最近一次发布',
        lb ? (lb.at + '　' + lb.message) : '本次服务启动后还没有发布过'),
      el('div', { class: 'toolbar', style: 'margin-top:12px' }, [
        el('button', {
          class: 'btn primary', text: '发布站点',
          onclick: function (ev) { doRebuild(box, ctx, ev.target); }
        }),
        el('span', { class: 'muted', text:
          '把当前文章与页面重新构建后发布到官网。日常发文用文章列表里的「保存并发布」即可，这里用于手动重发。' })
      ])
    ]));

    /* ── 数据 ── */
    box.appendChild(el('div', { class: 'section-title', text: '数据' }));
    box.appendChild(el('div', { class: 'card' }, [
      el('div', { class: 'toolbar', style: 'margin:0' }, [
        el('button', { class: 'btn', text: '备份与恢复',
          onclick: function () { backupView(box, ctx); } }),
        el('span', { class: 'muted', text: '备份数据库 / 文章内容 / 上传文件 / 配置；可回滚到某个时间点' })
      ])
    ]));

    box.appendChild(el('div', { class: 'section-title', text: '安全' }));
    box.appendChild(el('div', { class: 'card' }, [
      soon(el, '管理员与权限', '增删管理员、按模块分配权限、操作审计'),
      soon(el, '访问日志', '接口调用与异常日志检索')
    ]));

    box.appendChild(el('div', { class: 'section-title', text: '运维' }));
    box.appendChild(el('div', { class: 'card' }, [
      soon(el, '定时任务', '定时发布文章、定时备份、定时清理')
    ]));
  }).catch(function (e) { ctx.fail(box, e); });
}

function row(el, k, v, vClass, badge) {
  return el('div', { class: 'sys-row' }, [
    el('span', { class: 'k', text: k }),
    el('span', { class: 'v' + (vClass ? ' ' + vClass : ''), text: v }),
    badge ? el('span', { class: 'badge ' + (badge === '就绪' ? 'on' : 'off'), text: badge }) : null
  ]);
}

function soon(el, name, desc) {
  return el('div', { class: 'soon-row' }, [
    el('span', { text: name }),
    el('span', { class: 'badge off', text: '规划中' }),
    el('span', { class: 'muted', text: desc })
  ]);
}

function doRebuild(box, ctx, btn) {
  btn.disabled = true;
  btn.textContent = '构建中…';
  var timer = setTimeout(function () {
    btn.disabled = false; btn.textContent = '发布站点';
    alert('构建超时（可能仍在进行），请稍后刷新本页查看最近一次发布记录');
  }, 200000);
  ctx.api.systemRebuild().then(function (r) {
    clearTimeout(timer);
    btn.disabled = false; btn.textContent = '发布站点';
    alert(r.message || '已重新发布');
    renderStatus(box, ctx);
  }).catch(function (e) {
    clearTimeout(timer);
    btn.disabled = false; btn.textContent = '发布站点';
    alert('发布失败：' + e.message);
    renderStatus(box, ctx);
  });
}

/* ══════════════ 备份与恢复 ══════════════ */
function fmtSize(n) {
  if (!n) return '0 B';
  if (n < 1024) return n + ' B';
  if (n < 1048576) return (n / 1024).toFixed(1) + ' KB';
  if (n < 1073741824) return (n / 1048576).toFixed(1) + ' MB';
  return (n / 1073741824).toFixed(2) + ' GB';
}

function backupView(box, ctx, toast) {
  var el = ctx.el;
  box.innerHTML = '';
  box.appendChild(el('div', { class: 'loading', text: '加载中…' }));

  ctx.api.backupList().then(function (d) {
    box.innerHTML = '';
    box.appendChild(el('div', { class: 'toolbar' }, [
      el('button', { class: 'btn', text: '← 返回系统管理',
        onclick: function () { renderStatus(box, ctx); } }),
      el('button', { class: 'btn primary', text: '＋ 立即备份',
        onclick: function (ev) { doBackup(box, ctx, ev.target); } }),
      el('span', { class: 'muted', text:
        '磁盘剩余 ' + fmtSize(d.disk.free) + '（共 ' + fmtSize(d.disk.total) + '）'
        + '　·　自动保留最近 ' + d.keep + ' 份' })
    ]));
    if (toast) box.appendChild(el('div', { class: 'ok-box', text: toast }));

    box.appendChild(el('div', { class: 'warn-box', text:
      '备份目录：' + d.dir + '（在站点根目录之外，公网无法下载）'
      + '　自动备份：' + (d.last_auto
        ? '最近一次 ' + d.last_auto.created_at.replace('T', ' ')
        : '暂无（未配置定时任务）')
      + '　恢复前系统会**自动先备份当前状态**，恢复错了还能再恢复回来。' }));

    if (!d.items.length) {
      box.appendChild(el('div', { class: 'empty', text: '还没有备份，点「立即备份」创建第一份。' }));
      return;
    }

    var table = el('table', { class: 'table' });
    table.appendChild(el('thead', {}, [el('tr', {}, [
      el('th', { text: '备份' }), el('th', { text: '时间' }),
      el('th', { text: '大小' }), el('th', { text: '包含' }), el('th', { text: '操作' })
    ])]));
    var tbody = el('tbody', {});
    d.items.forEach(function (b) {
      var isAuto = /-auto$/.test(b.name);
      tbody.appendChild(el('tr', {}, [
        el('td', {}, [
          el('span', { class: 'mono', text: b.name }),
          el('span', { class: 'badge ' + (isAuto ? 'off' : 'on'),
            style: 'margin-left:8px', text: isAuto ? '自动' : '手动' })
        ]),
        el('td', { text: (b.created_at || '').replace('T', ' ') }),
        el('td', { text: fmtSize(b.size) }),
        el('td', { class: 'mono', text: (b.parts || []).join(' ') }),
        el('td', {}, [el('div', { class: 'row-actions' }, [
          el('a', { href: '#', text: '恢复内容', title: '只恢复文章内容与上传文件（不动数据库）',
            onclick: function (e) {
              e.preventDefault();
              confirmRestore(b, 'content,uploads', '文章内容与上传文件');
            } }),
          el('a', { href: '#', text: '完全恢复', class: 'danger',
            title: '恢复数据库 + 内容 + 上传 + 配置（会覆盖当前数据）',
            onclick: function (e) {
              e.preventDefault();
              confirmRestore(b, 'db,content,uploads,etc', '数据库、文章内容、上传文件与配置');
            } }),
          el('a', { href: '#', text: '删除', class: 'danger', onclick: function (e) {
            e.preventDefault();
            if (!confirm('删除备份 ' + b.name + '？')) return;
            ctx.api.backupDelete(b.name).then(function () {
              backupView(box, ctx, '已删除备份 ' + b.name);
            }).catch(function (err) { alert('删除失败：' + err.message); });
          } })
        ])])
      ]));
    });
    table.appendChild(tbody);
    box.appendChild(el('div', { class: 'card' }, [table]));

    function confirmRestore(b, parts, what) {
      if (!confirm('恢复备份 ' + b.name + '？\n\n将覆盖：' + what
        + '\n\n恢复前会自动备份当前状态；恢复后站点会重新构建。')) return;
      ctx.api.backupRestore(b.name, parts).then(function (r) {
        backupView(box, ctx, '已恢复：' + (r.restored || []).join('、')
          + '；恢复前已自动备份为 ' + r.safety_backup
          + (r.rebuild ? '（站点已重新构建发布）' : ''));
      }).catch(function (err) { alert('恢复失败：' + err.message); });
    }
  }).catch(function (e) { ctx.fail(box, e); });
}

function doBackup(box, ctx, btn) {
  btn.disabled = true; btn.textContent = '备份中…';
  var timer = setTimeout(function () {
    btn.disabled = false; btn.textContent = '＋ 立即备份';
    alert('备份耗时较长（可能仍在进行），请稍后刷新查看');
  }, 300000);
  ctx.api.backupCreate().then(function (r) {
    clearTimeout(timer);
    backupView(box, ctx, '备份完成：' + r.backup.name + '（' + fmtSize(r.backup.size) + '）');
  }).catch(function (e) {
    clearTimeout(timer);
    btn.disabled = false; btn.textContent = '＋ 立即备份';
    alert('备份失败：' + e.message);
  });
}
