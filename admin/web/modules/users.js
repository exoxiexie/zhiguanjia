/* 模块：用户管理
 *
 * 面向客服与风控：检索用户 → 看详情（实名/设备/内容量）→ 停用或恢复、管理员开关、重置密码。
 * 停用与重置密码都会**立即吊销该用户所有令牌**（把人踢下线），不是等令牌自然过期。
 */
ZGJ.registerModule({
  id: 'users',
  name: '用户管理',
  icon: '👤',

  render: function (box, ctx) {
    listView(box, ctx);
  }
});

function listView(box, ctx, opts) {
  var el = ctx.el;
  opts = opts || {};
  box.innerHTML = '';
  box.appendChild(el('div', { class: 'loading', text: '加载中…' }));

  ctx.api.userList({ q: opts.q || '', onlyBanned: !!opts.onlyBanned, limit: 100 })
    .then(function (d) {
      box.innerHTML = '';
      var input = el('input', { type: 'text', placeholder: '搜索手机号或姓名' });
      input.value = opts.q || '';
      var banned = el('input', { type: 'checkbox' });
      banned.checked = !!opts.onlyBanned;

      function search() { listView(box, ctx, { q: input.value.trim(), onlyBanned: banned.checked }); }
      input.addEventListener('keydown', function (e) { if (e.key === 'Enter') search(); });
      banned.addEventListener('change', search);

      box.appendChild(el('div', { class: 'toolbar' }, [
        input,
        el('button', { class: 'btn', text: '搜索', onclick: search }),
        el('label', { class: 'check', style: 'margin:0' }, [banned, el('span', { text: '只看已停用' })]),
        el('span', { class: 'muted', text: '共 ' + d.total + ' 个用户' })
      ]));

      if (!d.items.length) {
        box.appendChild(el('div', { class: 'empty', text: '没有匹配的用户。' }));
        return;
      }

      var table = el('table', { class: 'table' });
      table.appendChild(el('thead', {}, [el('tr', {}, [
        el('th', { text: '手机号' }), el('th', { text: '姓名' }), el('th', { text: '状态' }),
        el('th', { text: '设备' }), el('th', { text: '内容' }), el('th', { text: '最近活跃' }),
        el('th', { text: '操作' })
      ])]));
      var tbody = el('tbody', {});
      d.items.forEach(function (u) {
        tbody.appendChild(el('tr', {}, [
          el('td', {}, [
            el('span', { class: 'mono', text: u.phone }),
            u.is_admin ? el('span', { class: 'badge on', style: 'margin-left:6px', text: '管理员' }) : null,
            u.verified ? el('span', { class: 'badge off', style: 'margin-left:6px', text: '已实名' }) : null
          ]),
          el('td', { text: u.name || '—' }),
          el('td', {}, [el('span', { class: 'badge ' + (u.status === 1 ? 'on' : 'off'),
            text: u.status === 1 ? '正常' : '已停用' })]),
          el('td', { text: String(u.devices || 0) }),
          el('td', { class: 'mono', text: '对话 ' + (u.conversations || 0) + ' · 消息 ' + (u.messages || 0) }),
          el('td', { text: (u.last_seen_at || '').replace('T', ' ').slice(0, 16) || '—' }),
          el('td', {}, [el('a', { href: '#', text: '详情', onclick: function (e) {
            e.preventDefault();
            detailView(box, ctx, u.id);
          } })])
        ]));
      });
      table.appendChild(tbody);
      box.appendChild(el('div', { class: 'card' }, [table]));
    }).catch(function (e) { ctx.fail(box, e); });
}

function detailView(box, ctx, id, toast) {
  var el = ctx.el;
  box.innerHTML = '';
  box.appendChild(el('div', { class: 'loading', text: '加载中…' }));
  ctx.api.userGet(id).then(function (u) {
    box.innerHTML = '';
    if (toast) box.appendChild(el('div', { class: 'ok-box', text: toast }));

    box.appendChild(el('div', { class: 'toolbar' }, [
      el('button', { class: 'btn', text: '← 返回列表',
        onclick: function () { listView(box, ctx); } }),
      el('span', { class: 'muted', text: u.phone + '（' + (u.name || '未填姓名') + '）' })
    ]));

    box.appendChild(el('div', { class: 'section-title', text: '账号' }));
    box.appendChild(el('div', { class: 'card' }, [
      kv(el, '手机号', u.phone),
      kv(el, '姓名', u.name || '—'),
      kv(el, '状态', u.status === 1 ? '正常' : ('已停用' + (u.banned_reason ? '：' + u.banned_reason : ''))),
      kv(el, '实名', u.verified ? ('已实名 ' + (u.id_card_masked || '')) : '未实名'),
      kv(el, '管理员', u.is_admin ? '是' : '否'),
      kv(el, '注册时间', (u.created_at || '').replace('T', ' ').slice(0, 19))
    ]));

    box.appendChild(el('div', { class: 'section-title', text: '使用情况' }));
    box.appendChild(el('div', { class: 'card' }, [
      kv(el, '设备数', String(u.devices || 0)),
      kv(el, '对话数', String(u.conversations || 0)),
      kv(el, '消息数', String(u.messages || 0) + '（今日 ' + (u.messages_today || 0) + '）'),
      kv(el, '最近活跃', (u.last_seen_at || '—').replace('T', ' ').slice(0, 19))
    ]));

    if ((u.device_list || []).length) {
      box.appendChild(el('div', { class: 'section-title', text: '登录设备' }));
      var dt = el('table', { class: 'table' });
      dt.appendChild(el('thead', {}, [el('tr', {}, [
        el('th', { text: '平台' }), el('th', { text: '机型' }),
        el('th', { text: '版本' }), el('th', { text: '最近活跃' })
      ])]));
      var tb = el('tbody', {});
      u.device_list.forEach(function (dv) {
        tb.appendChild(el('tr', {}, [
          el('td', { text: dv.platform || '—' }),
          el('td', { text: ((dv.brand || '') + ' ' + (dv.model || '')).trim() || '—' }),
          el('td', { text: dv.app_version ? ('v' + dv.app_version + '（' + dv.version_code + '）') : '—' }),
          el('td', { text: (dv.last_seen_at || '').replace('T', ' ').slice(0, 16) })
        ]));
      });
      dt.appendChild(tb);
      box.appendChild(el('div', { class: 'card' }, [dt]));
    }

    box.appendChild(el('div', { class: 'section-title', text: '操作' }));
    box.appendChild(el('div', { class: 'card' }, [
      el('div', { class: 'toolbar', style: 'margin:0' }, [
        u.status === 1
          ? el('button', { class: 'btn', text: '停用账号', onclick: function () {
              var reason = prompt('停用原因（会记录在日志里，并显示给用户）：', '');
              if (!reason) return;
              ctx.api.userStatus(u.id, 0, reason).then(function () {
                detailView(box, ctx, id, '已停用（该用户已被踢下线）');
              }).catch(function (e) { alert('停用失败：' + e.message); });
            } })
          : el('button', { class: 'btn', text: '恢复账号', onclick: function () {
              ctx.api.userStatus(u.id, 1, '').then(function () {
                detailView(box, ctx, id, '已恢复');
              }).catch(function (e) { alert('恢复失败：' + e.message); });
            } }),
        el('button', { class: 'btn', text: u.is_admin ? '取消管理员' : '设为管理员',
          onclick: function () {
            if (u.is_admin && !confirm('取消 ' + u.phone + ' 的管理员权限？')) return;
            ctx.api.userAdmin(u.id, !u.is_admin).then(function () {
              detailView(box, ctx, id, u.is_admin ? '已取消管理员' : '已设为管理员');
            }).catch(function (e) { alert('操作失败：' + e.message); });
          } }),
        el('button', { class: 'btn', text: '重置密码', onclick: function () {
          if (!confirm('重置 ' + u.phone + ' 的密码？\n\n将生成一次性临时密码，'
            + '并让其所有设备立即退出登录。')) return;
          ctx.api.userResetPassword(u.id).then(function (r) {
            alert('临时密码：' + r.temp_password + '\n\n' + r.note);
            detailView(box, ctx, id, '已重置密码（用户所有设备已退出登录）');
          }).catch(function (e) { alert('重置失败：' + e.message); });
        } })
      ])
    ]));
  }).catch(function (e) { ctx.fail(box, e); });
}

function kv(el, k, v) {
  return el('div', { class: 'sys-row' }, [
    el('span', { class: 'k', text: k }), el('span', { class: 'v', text: v })
  ]);
}
