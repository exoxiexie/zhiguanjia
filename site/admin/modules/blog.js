/* 模块：博客发布管理（内容管理）
 *
 * 官网是**纯静态站**，所以"发布"= 写 Markdown → 重新构建 → 同步上线。
 * 后台只负责编辑与触发，构建与同步都走站点脚本（与命令行部署同一条链路）。
 */
ZGJ.registerModule({
  id: 'blog',
  name: '博客发布管理',
  icon: '📝',

  render: function (box, ctx) {
    list(box, ctx); // 进入模块先看列表
  }
});

/* 待显示的提示：由动作设置、由 list() 渲染后清空。
   （曾用函数参数传递，渲染时未传 → 调用即抛异常，导致按钮永远停在"构建中"） */
var pendingToast = '';

/* 给可能很慢的请求加超时，保证按钮状态一定能恢复 */
function withTimeout(promise, ms, label) {
  return Promise.race([promise, new Promise(function (_, reject) {
    setTimeout(function () {
      reject(new Error(label + '超时（' + Math.round(ms / 1000) + '秒），请稍后刷新查看结果'));
    }, ms);
  })]);
}

/* ───────────── 列表 ───────────── */
function list(box, ctx) {
  var el = ctx.el;
  box.innerHTML = '';
  box.appendChild(el('div', { class: 'loading', text: '加载中…' }));

  ctx.api.blogList().then(function (data) {
    box.innerHTML = '';
    var items = data.items || [];

    var bar = el('div', { class: 'toolbar' }, [
      el('button', {
        class: 'btn primary', text: '＋ 新建文章',
        onclick: function () { editor(box, ctx, ''); }
      }),
      el('button', {
        class: 'btn', text: '发布站点',
        title: '把当前文章与页面重新构建后发布到官网。'
          + '日常发文用每篇的「保存并发布」即可，无需点它；'
          + '只有手工改过模板或样式后才需要点。',
        onclick: function (ev) {
          var b = ev.target;
          b.disabled = true; b.textContent = '构建中…';
          function restore() { b.disabled = false; b.textContent = '发布站点'; }
          withTimeout(ctx.api.blogRebuild(), 200000, '构建发布')
            .then(function (r) { pendingToast = r.message || '已重新发布'; })
            .catch(function (e) { pendingToast = '失败：' + e.message; })
            .then(function () { restore(); list(box, ctx); });
        }
      }),
      el('span', { class: 'muted', text: '共 ' + items.length + ' 篇' })
    ]);
    box.appendChild(bar);

    if (!data.site_dir_ready) {
      box.appendChild(el('div', { class: 'err-box', text:
        '服务器上还没部署站点源码目录（' + data.site_dir + '），发布功能不可用。' }));
    }
    if (pendingToast) {
      box.appendChild(el('div', { class: 'ok-box', text: pendingToast }));
      pendingToast = '';
    }

    if (!items.length) {
      box.appendChild(el('div', { class: 'empty', text: '还没有文章，点「新建文章」开始写吧。' }));
      return;
    }

    var table = el('table', { class: 'table' });
    table.appendChild(el('thead', {}, [
      el('tr', {}, [
        el('th', { text: '标题' }), el('th', { text: '链接' }),
        el('th', { text: '日期' }), el('th', { text: '状态' }),
        el('th', { text: '作者' }), el('th', { text: '操作' })
      ])
    ]));
    var tbody = el('tbody', {});
    items.forEach(function (a) {
      var actions = el('div', { class: 'row-actions' }, [
        el('a', { href: '#', text: '编辑', onclick: function (e) {
          e.preventDefault(); editor(box, ctx, a.id);
        } }),
        a.status === 'published'
          ? el('a', { href: a.url, target: '_blank', text: '查看' })
          : null,
        el('a', { href: '#', class: 'danger', text: '删除', onclick: function (e) {
          e.preventDefault();
          if (!confirm('删除《' + a.title + '》？已发布的会同时下线官网页面。')) return;
          ctx.api.blogDelete(a.id).then(function () {
            pendingToast = '已删除：' + a.title;
            list(box, ctx);
          }).catch(function (err) {
            pendingToast = '删除失败：' + err.message;
            list(box, ctx);
          });
        } })
      ]);
      tbody.appendChild(el('tr', {}, [
        el('td', { text: a.title || '(无标题)' }),
        el('td', { class: 'mono', text: '/blog/' + a.slug + '/' }),
        el('td', { text: a.date || '-' }),
        el('td', {}, [el('span', {
          class: 'badge ' + (a.status === 'published' ? 'on' : 'off'),
          text: a.status === 'published' ? '已发布' : '草稿'
        })]),
        el('td', { text: a.author || '-' }),
        el('td', {}, [actions])
      ]));
    });
    table.appendChild(tbody);
    box.appendChild(el('div', { class: 'card' }, [table]));
  }).catch(function (e) { ctx.fail(box, e); });
}

/* ───────────── 编辑器 ───────────── */

function editor(box, ctx, id) {
  var el = ctx.el;
  box.innerHTML = '';
  box.appendChild(el('div', { class: 'loading', text: '加载中…' }));

  var load = id ? ctx.api.blogGet(id) : Promise.resolve({});
  load.then(function (a) {
    box.innerHTML = '';
    var f = {
      title: a.title || '',
      slug: a.slug || '',
      author: a.author || '老谢',
      date: a.date || '',
      excerpt: a.excerpt || '',
      tags: (a.tags || []).join(', '),
      body_md: a.body_md || ''
    };

    function field(label, key, opts) {
      opts = opts || {};
      var input = opts.multiline
        ? el('textarea', { rows: opts.rows || 16, placeholder: opts.placeholder || '' })
        : el('input', { type: 'text', placeholder: opts.placeholder || '' });
      input.value = f[key];
      input.addEventListener('input', function () { f[key] = input.value; });
      return el('label', { class: 'field' + (opts.half ? ' half' : '') }, [
        el('span', { text: label + (opts.hint ? '　' + opts.hint : '') }),
        input
      ]);
    }

    var head = el('div', { class: 'toolbar' }, [
      el('button', { class: 'btn', text: '← 返回列表',
        onclick: function () { list(box, ctx); } }),
      el('span', { class: 'muted', text: id ? ('编辑：' + f.title) : '新建文章' })
    ]);

    var form = el('div', { class: 'card' }, [
      el('div', { class: 'grid g2' }, [
        field('标题', 'title', { placeholder: '文章标题' }),
        field('链接标识（小写字母/数字/连字符）', 'slug', { placeholder: 'ai-career-five-steps' })
      ]),
      el('div', { class: 'grid g3' }, [
        field('作者', 'author', { placeholder: '老谢' }),
        field('日期', 'date', { placeholder: '2026-10-10（留空自动填今天）' }),
        field('标签（逗号分隔）', 'tags', { placeholder: '职业规划, 方法论' })
      ]),
      field('摘要', 'excerpt', { multiline: true, rows: 3, placeholder: '列表与搜索引擎展示的一句话' }),
      field('正文（Markdown）', 'body_md', { multiline: true, rows: 18, placeholder: '## 小标题\n\n正文…' })
    ]);

    var actions = el('div', { class: 'toolbar' }, [
      el('button', { class: 'btn', text: '保存草稿', onclick: function () { save('draft'); } }),
      el('button', { class: 'btn primary', text: '保存并发布', onclick: function () { save('published'); } }),
      el('span', { class: 'muted', text: '发布 = 写入站点 → 重新构建 → 同步上线（约几秒）' })
    ]);

    function save(status) {
      if (!f.title.trim()) { alert('请填写标题'); return; }
      if (!/^[a-z0-9][a-z0-9-]{0,63}$/.test(f.slug.trim())) {
        alert('链接标识只能用「小写字母、数字、连字符」，且以字母或数字开头');
        return;
      }
      var payload = {
        title: f.title, slug: f.slug.trim().toLowerCase(), author: f.author || '老谢',
        date: f.date, excerpt: f.excerpt,
        tags: f.tags.split(',').map(function (t) { return t.trim(); }).filter(Boolean),
        body_md: f.body_md, status: status
      };
      box.querySelectorAll('button').forEach(function (b) { b.disabled = true; });
      ctx.api.blogSave(payload, id).then(function (r) {
        var newId = r.article.id;
        if (status !== 'published') {
          pendingToast = '已保存草稿：' + f.title;
          list(box, ctx);
          return null;
        }
        return withTimeout(ctx.api.blogPublish(newId), 200000, '发布')
          .then(function (p) {
            pendingToast = '已发布上线：' + p.url;
            list(box, ctx);
          });
      }).catch(function (e) {
        box.querySelectorAll('button').forEach(function (b) { b.disabled = false; });
        pendingToast = '操作失败：' + e.message;
        list(box, ctx);
      });
    }

    box.appendChild(head);
    box.appendChild(form);
    box.appendChild(actions);
  }).catch(function (e) { ctx.fail(box, e); });
}
