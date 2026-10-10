(function () {
  'use strict';

  /* 模块：公告与配置
   *
   * 管理**下发给 App 的配置** —— 不发版即可生效：
   *   公告（App 启动弹窗）· 强制更新（最低支持版本）· 功能开关（含测试入口灰度名单）
   *
   * 这些配置改错影响面极大（强制更新设错会把所有用户拦在门外），
   * 因此：每块单独保存、危险操作二次确认、界面写清"会发生什么"、
   * 并显示最后修改人。
   */
  ZGJ.registerModule({
    id: 'config',
    name: '公告与配置',
    icon: '📣',

    render: function (box, ctx) {
      load(box, ctx);
    }
  });

  function load(box, ctx, toast) {
    var el = ctx.el;
    box.innerHTML = '';
    box.appendChild(el('div', { class: 'loading', text: '加载中…' }));
    ctx.api.configGet().then(function (c) {
      box.innerHTML = '';
      if (toast) box.appendChild(el('div', { class: 'ok-box', text: toast }));

      box.appendChild(el('div', { class: 'section-title', text: '公告（App 启动时弹窗）' }));
      box.appendChild(announcementCard(el, ctx, c, box));

      box.appendChild(el('div', { class: 'section-title', text: '强制更新（低于该版本必须升级）' }));
      box.appendChild(minVersionCard(el, ctx, c, box));

      box.appendChild(el('div', { class: 'section-title', text: '功能开关' }));
      box.appendChild(flagsCard(el, ctx, c, box));

      box.appendChild(el('div', { class: 'muted', style: 'margin-top:16px;font-size:12.5px' , text:
        '最后修改：' + (c.updated_by ? c.updated_by + '　' : '')
        + (c.updated_at ? c.updated_at.replace('T', ' ').slice(0, 19) : '未知')
        + '（配置改动立即生效，App 下次启动读取）' }));
    }).catch(function (e) { ctx.fail(box, e); });
  }

  function field(el, label, hint) {
    return el('label', { class: 'field' }, [
      el('span', { text: label + (hint ? '　' + hint : '') }),
      el('input', { type: 'text' })
    ]);
  }
  function area(el, label, rows) {
    return el('label', { class: 'field' }, [
      el('span', { text: label }),
      el('textarea', { rows: rows || 4 })
    ]);
  }
  function inputOf(labelNode) { return labelNode.children[1]; }

  function save(el, ctx, box, payload, okText) {
    return ctx.api.configSave(payload).then(function () {
      load(box, ctx, okText);
    }).catch(function (e) {
      alert('保存失败：' + e.message);
    });
  }

  /* ── 公告 ── */
  function announcementCard(el, ctx, c, box) {
    var a = c.announcement || {};
    var on = el('input', { type: 'checkbox' });
    on.checked = !!a.enabled;
    var title = field(el, '标题');
    inputOf(title).value = a.title || '';
    var body = area(el, '正文', 5);
    body.children[1].value = a.body || '';

    return el('div', { class: 'card' }, [
      el('label', { class: 'check' }, [on, el('span', { text: '启用公告（App 启动时弹窗）' })]),
      title,
      body,
      el('div', { class: 'toolbar' }, [
        el('button', { class: 'btn primary', text: '保存公告', onclick: function () {
          save(el, ctx, box, { announcement: {
            enabled: on.checked, title: inputOf(title).value,
            body: body.children[1].value
          } }, '公告已保存（App 下次启动生效）');
        } }),
        el('button', { class: 'btn', text: '保存并让所有人再看一次', title:
          '会更换公告 ID：已看过这条公告的用户也会再次看到', onclick: function () {
          save(el, ctx, box, { reset_announcement_read: true, announcement: {
            enabled: on.checked, title: inputOf(title).value,
            body: body.children[1].value
          } }, '已保存，并让所有人重新看到这条公告');
        } }),
        el('span', { class: 'muted', text: '同一条公告用户只弹一次；改 ID 才会再次弹出' })
      ])
    ]);
  }

  /* ── 强制更新 ── */
  function minVersionCard(el, ctx, c, box) {
    var m = c.min_version || {};
    var rel = c.release || {};
    var code = field(el, '最低支持版本号（versionCode）', '数字；0 = 不强制');
    inputOf(code).value = m.version_code || 0;
    var name = field(el, '版本名', '展示给用户，如 1.0.49');
    inputOf(name).value = m.version_name || '';
    var url = field(el, '下载地址');
    inputOf(url).value = m.url || '';
    var note = area(el, '更新说明（弹窗里展示）', 3);
    note.children[1].value = m.note || '';

    return el('div', { class: 'card' }, [
      el('div', { class: 'warn-box', text:
        '只有「本机版本号 < 最低支持版本号」的用户会被拦下并要求升级；'
        + '填 0 表示不强制。' + (rel.version_name
          ? '　当前官网版本：' + rel.version_name + '（versionCode ' + rel.version_code + '）' : '') }),
      code, name, url, note,
      el('div', { class: 'toolbar' }, [
        rel.version_name ? el('button', { class: 'btn', text: '填入当前官网版本', onclick: function () {
          inputOf(code).value = rel.version_code;
          inputOf(name).value = rel.version_name;
          if (!inputOf(url).value) inputOf(url).value = rel.url || '';
          if (!note.children[1].value) note.children[1].value = rel.changelog || '';
        } }) : null,
        el('button', { class: 'btn primary', text: '保存强制更新', onclick: function () {
          var v = parseInt(inputOf(code).value, 10) || 0;
          if (v > 0 && !confirm('确认开启强制更新？\n\n版本号低于 ' + v + ' 的用户'
            + '将被拦下、必须升级才能继续使用。')) return;
          save(el, ctx, box, { min_version: {
            version_code: v, version_name: inputOf(name).value,
            url: inputOf(url).value, note: note.children[1].value
          } }, v > 0 ? '已开启强制更新' : '已关闭强制更新');
        } }),
        el('button', { class: 'btn', text: '关闭强制更新', onclick: function () {
          if (!confirm('关闭后所有版本都能继续使用，确认？')) return;
          inputOf(code).value = 0;
          save(el, ctx, box, { min_version: { version_code: 0 } }, '已关闭强制更新');
        } })
      ])
    ]);
  }

  /* ── 功能开关 ── */
  function flagsCard(el, ctx, c, box) {
    var flags = c.flags || {};
    var tester = el('input', { type: 'checkbox' });
    tester.checked = flags.test_panel === true;
    var phones = field(el, '灰度手机号', '逗号分隔；只有这些账号能看到「测试」入口');
    inputOf(phones).value = (flags.test_panel_phones || []).join(', ');

    var raw = area(el, '高级：全部开关（JSON）', 6);
    raw.children[1].value = JSON.stringify(flags, null, 2);

    return el('div', { class: 'card' }, [
      el('label', { class: 'check' }, [tester,
        el('span', { text: '测试入口对所有用户可见（内测期用；正式发布请保持不勾选）' })]),
      phones,
      el('div', { class: 'toolbar' }, [
        el('button', { class: 'btn primary', text: '保存开关', onclick: function () {
          var list = inputOf(phones).value.split(',').map(function (s) { return s.trim(); })
            .filter(Boolean);
          save(el, ctx, box, { flags: {
            test_panel: tester.checked, test_panel_phones: list
          } }, '功能开关已保存');
        } }),
        el('span', { class: 'muted', text: '改动立即生效，用户无需更新 App' })
      ]),
      el('details', { class: 'advanced' }, [
        el('summary', { text: '高级：直接编辑全部开关（JSON）' }),
        raw,
        el('div', { class: 'toolbar' }, [
          el('button', { class: 'btn', text: '保存 JSON', onclick: function () {
            var v;
            try { v = JSON.parse(raw.children[1].value || '{}'); }
            catch (err) { alert('JSON 格式不正确：' + err.message); return; }
            save(el, ctx, box, { flags: v }, '功能开关已保存（JSON）');
          } })
        ])
      ])
    ]);
  }
})();
