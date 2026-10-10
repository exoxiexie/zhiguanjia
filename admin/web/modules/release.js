/* 模块：版本发布
 *
 * 分工：APK 在本地编译（服务器没有 Flutter/Android SDK），
 * 上传到这里后由后台完成**分发侧的一切**：
 * 写更新源 → 铺官网下载页 → 重建发布 → 可选强制更新 → 留发布历史。
 */
ZGJ.registerModule({
  id: 'release',
  name: '版本发布',
  icon: '🚀',

  render: function (box, ctx) {
    load(box, ctx);
  }
});

function fmtMB(n) { return (n / 1048576).toFixed(1) + ' MB'; }

function load(box, ctx, toast) {
  var el = ctx.el;
  box.innerHTML = '';
  box.appendChild(el('div', { class: 'loading', text: '加载中…' }));
  ctx.api.releaseList().then(function (d) {
    box.innerHTML = '';
    if (toast) box.appendChild(el('div', { class: 'ok-box', text: toast }));

    var cur = d.current || {};
    box.appendChild(el('div', { class: 'section-title', text: '当前线上版本' }));
    box.appendChild(el('div', { class: 'card' }, [
      el('div', { class: 'sys-row' }, [
        el('span', { class: 'k', text: '版本' }),
        el('span', { class: 'v', text: 'v' + (cur.version_name || '-')
          + '（versionCode ' + (cur.version_code || 0) + '）' })
      ]),
      el('div', { class: 'sys-row' }, [
        el('span', { class: 'k', text: '更新说明' }),
        el('span', { class: 'v', text: cur.changelog || '—' })
      ]),
      el('div', { class: 'sys-row' }, [
        el('span', { class: 'k', text: '下载地址' }),
        el('span', { class: 'v mono', text: cur.url || '—' })
      ])
    ]));

    /* ── 上传新版本 ── */
    box.appendChild(el('div', { class: 'section-title', text: '上传新版本' }));
    var fileInput = el('input', { type: 'file', accept: '.apk' });
    var vname = el('input', { type: 'text', placeholder: '如 1.0.50（不要带 v）' });
    var vcode = el('input', { type: 'text', placeholder: '如 51（必须大于 ' + (cur.version_code || 0) + '）' });
    var note = el('textarea', { rows: 3, placeholder: '更新说明（会显示在 App 的更新弹窗里）' });
    var force = el('input', { type: 'checkbox' });
    var bar = el('div', { class: 'bar' }, [el('i', { style: 'width:0%' })]);
    var status = el('span', { class: 'muted', text: '' });

    box.appendChild(el('div', { class: 'card' }, [
      el('div', { class: 'warn-box', text:
        '安装包需在本地用 Flutter 构建（服务器没有 Android 构建环境）。'
        + '上传后先存为草稿，点列表里的「发布」才真正生效 —— 可先上传、择机发布。' }),
      el('label', { class: 'field' }, [el('span', { text: 'APK 文件' }), fileInput]),
      el('div', { class: 'grid g2' }, [
        el('label', { class: 'field' }, [el('span', { text: '版本名' }), vname]),
        el('label', { class: 'field' }, [el('span', { text: '版本号 versionCode' }), vcode])
      ]),
      el('label', { class: 'field' }, [el('span', { text: '更新说明' }), note]),
      el('label', { class: 'check' }, [force,
        el('span', { text: '发布时同时开启强制更新（低于此版本的用户必须升级才能用）' })]),
      el('div', { class: 'toolbar' }, [
        el('button', { class: 'btn primary', text: '上传安装包', onclick: function (ev) {
          var f = fileInput.files && fileInput.files[0];
          if (!f) { alert('请选择 APK 文件'); return; }
          if (!vname.value.trim() || !parseInt(vcode.value, 10)) {
            alert('请填写版本名与版本号'); return;
          }
          var fd = new FormData();
          fd.append('file', f);
          fd.append('version_name', vname.value.trim());
          fd.append('version_code', String(parseInt(vcode.value, 10)));
          fd.append('changelog', note.value);
          fd.append('force_update', force.checked ? 'true' : 'false');
          var btn = ev.target;
          btn.disabled = true; btn.textContent = '上传中…';
          bar.hidden = false; bar.children[0].style.width = '0%';
          ctx.api.releaseUpload(fd, function (p) {
            status.textContent = '已上传 ' + Math.round(p * 100) + '%';
            bar.children[0].style.width = Math.round(p * 100) + '%';
          }).then(function (r) {
            load(box, ctx, '上传成功（草稿）：v' + r.release.version_name
              + '，' + fmtMB(r.release.size) + '　请到列表点「发布」');
          }).catch(function (e) {
            btn.disabled = false; btn.textContent = '上传安装包';
            bar.hidden = true; status.textContent = '';
            alert('上传失败：' + e.message);
          });
        } }),
        bar,
        status
      ])
    ]));

    /* ── 发布历史 ── */
    box.appendChild(el('div', { class: 'section-title', text: '发布记录' }));
    if (!d.items.length) {
      box.appendChild(el('div', { class: 'empty', text: '还没有上传过版本。' }));
      return;
    }
    var table = el('table', { class: 'table' });
    table.appendChild(el('thead', {}, [el('tr', {}, [
      el('th', { text: '版本' }), el('th', { text: '大小' }), el('th', { text: 'sha256' }),
      el('th', { text: '状态' }), el('th', { text: '上传时间' }), el('th', { text: '操作' })
    ])]));
    var tbody = el('tbody', {});
    d.items.forEach(function (r) {
      var badge = r.status === 'published' ? 'on' : (r.status === 'draft' ? 'off' : 'off');
      tbody.appendChild(el('tr', {}, [
        el('td', {}, [
          el('span', { text: 'v' + r.version_name }),
          el('span', { class: 'muted', text: '　code ' + r.version_code }),
          r.force_update ? el('span', { class: 'badge off', style: 'margin-left:6px', text: '强制更新' }) : null
        ]),
        el('td', { text: fmtMB(r.size) }),
        el('td', { class: 'mono', text: r.sha256.slice(0, 12) + '…' }),
        el('td', {}, [el('span', { class: 'badge ' + badge, text:
          r.status === 'published' ? '已发布' : (r.status === 'draft' ? '草稿' : '已归档') })]),
        el('td', { text: r.created_at }),
        el('td', {}, [el('div', { class: 'row-actions' }, [
          r.status === 'published' ? el('a', { href: '/zhiguanjia/zhiguanjia-v' + r.version_name + '.apk',
            target: '_blank', text: '下载' }) : null,
          r.status !== 'published' ? el('a', { href: '#', text: '发布', onclick: function (e) {
            e.preventDefault();
            if (!confirm('发布 v' + r.version_name + '（code ' + r.version_code + '）？\\n\\n'
              + '将更新 App 的更新源、铺到官网下载页并重建站点。'
              + (r.force_update ? '\\n\\n⚠️ 同时开启强制更新：低于此版本的用户必须升级。' : ''))) return;
            ctx.api.releasePublish(r.id).then(function (res) {
              load(box, ctx, '已发布 v' + r.version_name + '：' + res.message
                + (res.force_update ? '（已开启强制更新）' : ''));
            }).catch(function (err) { alert('发布失败：' + err.message); });
          } }) : null,
          el('a', { href: '#', class: 'danger', text: '删除', onclick: function (e) {
            e.preventDefault();
            if (!confirm('删除 v' + r.version_name + ' 的记录与安装包？'
              + (r.status === 'published' ? '\\n\\n注意：这是当前线上版本！' : ''))) return;
            ctx.api.releaseDelete(r.id).then(function () {
              load(box, ctx, '已删除 v' + r.version_name);
            }).catch(function (err) { alert('删除失败：' + err.message); });
          } })
        ])])
      ]));
    });
    table.appendChild(tbody);
    box.appendChild(el('div', { class: 'card' }, [table]));
  }).catch(function (e) { ctx.fail(box, e); });
}
