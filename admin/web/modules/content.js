(function () {
  'use strict';

  /* 模块：内容审核
   *
   * 审核对象是**公开内容（说说）**；一对一对话属私密，不做批量巡检（隐私优先）。
   * 下架是软删除：App 下次拉取即同步消失，误下架可一键恢复，数据不丢。
   */
  ZGJ.registerModule({
    id: 'content',
    name: '内容审核',
    icon: '🔍',

    render: function (box, ctx) {
      view(box, ctx);
    }
  });

  function view(box, ctx, opts) {
    var el = ctx.el;
    opts = opts || {};
    box.innerHTML = '';
    box.appendChild(el('div', { class: 'loading', text: '加载中…' }));

    ctx.api.contentList({ q: opts.q || '', onlyHidden: !!opts.onlyHidden })
      .then(function (d) {
        box.innerHTML = '';
        var input = el('input', { type: 'text', placeholder: '搜索内容 / 作者手机号' });
        input.value = opts.q || '';
        var hidden = el('input', { type: 'checkbox' });
        hidden.checked = !!opts.onlyHidden;
        function search() { view(box, ctx, { q: input.value.trim(), onlyHidden: hidden.checked }); }
        input.addEventListener('keydown', function (e) { if (e.key === 'Enter') search(); });
        hidden.addEventListener('change', search);

        box.appendChild(el('div', { class: 'toolbar' }, [
          input,
          el('button', { class: 'btn', text: '搜索', onclick: search }),
          el('label', { class: 'check', style: 'margin:0' }, [hidden, el('span', { text: '只看已下架' })]),
          el('span', { class: 'muted', text: '共 ' + d.stats.all + ' 条 · 已下架 ' + d.stats.hidden + ' 条' })
        ]));
        box.appendChild(el('p', { class: 'muted', style: 'font-size:12.5px;margin:0 0 12px', text:
          '说明：这里只审**公开的说说**；一对一对话属私密内容，不做批量巡检。'
          + '下架为软删除，可随时恢复。' }));

        if (!d.items.length) {
          box.appendChild(el('div', { class: 'empty', text: '没有匹配的内容。' }));
          return;
        }

        d.items.forEach(function (p) {
          var actions = el('div', { class: 'toolbar', style: 'margin:10px 0 0' }, [
            p.hidden
              ? el('button', { class: 'btn', text: '恢复', onclick: function () {
                  ctx.api.contentRestore(p.id).then(function () {
                    view(box, ctx, opts);
                  }).catch(function (e) { alert('恢复失败：' + e.message); });
                } })
              : el('button', { class: 'btn', text: '下架', onclick: function () {
                  var reason = prompt('下架原因（会记录在日志里）：', '违规内容');
                  if (!reason) return;
                  ctx.api.contentHide(p.id, reason).then(function () {
                    view(box, ctx, opts);
                  }).catch(function (e) { alert('下架失败：' + e.message); });
                } }),
            el('button', { class: 'btn', text: '查看作者', onclick: function () {
              if (window.ZGJ_GOTO_USER) { window.ZGJ_GOTO_USER(p.author_id); return; }
              location.hash = '#/users';
            } }),
            el('span', { class: 'muted', text: '创建时间 ' + new Date(p.created_at).toLocaleString() })
          ]);
          box.appendChild(el('div', { class: 'card' }, [
            el('div', { class: 'sys-row' }, [
              el('span', { class: 'k', text: '作者' }),
              el('span', { class: 'v', text: (p.author_name || '—') + '　' + p.author_phone
                + (p.author_hidden ? '　（该用户已停用）' : '') }),
              el('span', { class: 'badge ' + (p.hidden ? 'off' : 'on'),
                text: p.hidden ? '已下架' : '正常' })
            ]),
            p.title ? el('div', { class: 'sys-row' }, [
              el('span', { class: 'k', text: '标题' }), el('span', { class: 'v', text: p.title })
            ]) : null,
            el('div', { style: 'padding:10px 0;font-size:13.5px;line-height:1.7;white-space:pre-wrap',
              text: p.content || '（无正文）' }),
            p.images ? el('div', { class: 'muted', text: '含 ' + p.images + ' 张图片' }) : null,
            p.hidden && p.hidden_reason
              ? el('div', { class: 'muted', text: '下架原因：' + p.hidden_reason + '（' + p.hidden_at + '）' })
              : null,
            actions
          ]));
        });
      }).catch(function (e) { ctx.fail(box, e); });
  }
})();
