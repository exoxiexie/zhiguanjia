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

    /* ── 规划中（把版图摆出来，不假装已实现）── */
    box.appendChild(el('div', { class: 'section-title', text: '数据' }));
    box.appendChild(el('div', { class: 'card' }, [
      soon(el, '备份与恢复', '一键备份数据库与站点文件，支持回滚到某个时间点')
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
