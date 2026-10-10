/* 模块：运营看板（管理后台第一条模块）
 *
 * 设计原则（极简 + 决策有用）：
 *  1. 先给"一眼判断"的 4 个数字：装机、活跃、用户、真在使用
 *  2. 再给结构：版本分布、平台分布、内容量、使用深度
 *  3. 最后给趋势：新增装机与内容产出（只展示真实可算的口径）
 *  4. 快照先渲染、趋势后填充 —— 打开即见，不必等两个请求
 */
ZGJ.registerModule({
  id: 'dashboard',
  name: '运营看板',
  icon: '📊',

  render: function (box, ctx) {
    var el = ctx.el;
    var snapshot = null;

    function kpi(label, value, unit, sub) {
      return el('div', { class: 'card kpi' }, [
        el('h3', { text: label }),
        el('div', { class: 'v' }, [
          el('span', { text: String(value) }),
          unit ? el('span', { class: 'u', text: unit }) : null
        ]),
        el('div', { class: 's', html: sub || '' })
      ]);
    }

    function bars(title, items, alt) {
      var max = Math.max.apply(null, items.map(function (i) { return i.value; }).concat([1]));
      var body = items.length
        ? items.map(function (i) {
            return el('div', { class: 'row' }, [
              el('div', { class: 'row-top' }, [
                el('span', { text: i.label }),
                el('span', { class: 'n', text: i.note })
              ]),
              el('div', { class: 'bar' + (alt ? ' alt' : '') }, [
                el('i', { style: 'width:' + Math.max(2, Math.round(i.value * 100 / max)) + '%' })
              ])
            ]);
          })
        : [el('div', { class: 'muted', text: '暂无数据' })];
      return ctx.card(title, body);
    }

    function chart(title, items, field, note) {
      var max = Math.max.apply(null, items.map(function (i) { return i[field]; }).concat([1]));
      var today = items.length ? items[items.length - 1].date : '';
      var cols = items.map(function (i, idx) {
        var h = Math.round(i[field] * 100 / max);
        var label = idx % 3 === 0 || idx === items.length - 1 ? i.date.slice(5) : '';
        return el('div', { class: 'col' + (i.date === today ? ' today' : '') }, [
          el('div', { class: 'b', style: 'height:' + Math.max(2, h) + '%', title: i.date + '：' + i[field] }),
          el('div', { class: 'x', text: label })
        ]);
      });
      var total = items.reduce(function (s, i) { return s + i[field]; }, 0);
      return ctx.card(title, [
        el('div', { class: 'chart' }, cols),
        el('div', { class: 'chart-legend', text: '近 ' + items.length + ' 天合计 ' + total + ' 条' + (note || '') })
      ]);
    }

    function renderSnapshot(s) {
      snapshot = s;

      box.appendChild(el('div', { class: 'grid g4' }, [
        kpi('装机设备', s.devices.total, '台',
          '今日新增 <b>' + s.devices.new_1d + '</b> · 近 7 日 <b>' + s.devices.new_7d + '</b>'),
        kpi('活跃设备', s.devices.active_1d, '台',
          '近 7 日 <b>' + s.devices.active_7d + '</b> · 近 30 日 <b>' + s.devices.active_30d + '</b>'),
        kpi('用户', s.users.total, '人',
          '已实名 <b>' + s.users.verified + '</b> · 今日新增 <b>' + s.users.new_1d + '</b>'),
        kpi('真在使用', s.engagement.users_with_conversations, '人',
          '产生过对话的用户，占 <b>' + s.engagement.conversion + '%</b>')
      ]));

      var versionItems = (s.versions || []).slice(0, 8).map(function (v) {
        return { label: v.version, value: v.devices, note: v.devices + ' 台 · ' + v.share + '%' };
      });
      var platformItems = (s.platforms || []).map(function (p) {
        return { label: p.platform, value: p.devices, note: p.devices + ' 台 · ' + p.share + '%' };
      });
      box.appendChild(el('div', { class: 'grid g2' }, [
        bars('版本分布', versionItems, false),
        bars('平台分布', platformItems, true)
      ]));

      var c = s.content;
      var contentCard = ctx.card('内容量', [
        el('div', { class: 'kv' }, [
          kv('对话', c.conversations), kv('消息', c.messages), kv('记忆', c.memories),
          kv('说说', c.posts), kv('经历', c.experiences), kv('收藏', c.favorites),
          kv('搜索沉淀', c.search_items)
        ])
      ]);
      var depthCard = ctx.card('使用深度', [
        el('div', { class: 'kv' }, [
          kv('人均对话', s.engagement.conversations_per_user),
          kv('人均消息/对话', s.engagement.messages_per_conversation),
          kv('对话转化率', s.engagement.conversion + '%')
        ])
      ]);
      box.appendChild(el('div', { class: 'grid g2' }, [contentCard, depthCard]));

      var trendBox = el('div', {});
      box.appendChild(trendBox);
      ctx.setUpdated(s.generated_at);

      // 趋势后加载，不阻塞首屏
      ctx.api.trend(14).then(function (t) {
        trendBox.innerHTML = '';
        trendBox.appendChild(el('div', { class: 'grid g2' }, [
          chart('近 14 天新增装机', t.items, 'new_devices'),
          chart('近 14 天消息产出', t.items, 'messages',
            '（每日"活跃设备"需快照表支持，暂不提供，避免口径误导）')
        ]));
      }).catch(function (e) {
        trendBox.appendChild(el('div', { class: 'err-box', text: '趋势加载失败：' + e.message }));
      });
    }

    function kv(k, v) {
      return el('div', { class: 'item' }, [
        el('div', { class: 'k', text: k }),
        el('div', { class: 'v', text: String(v) })
      ]);
    }

    box.appendChild(el('div', { class: 'loading', text: '加载中…' }));
    ctx.api.stats().then(function (s) {
      box.innerHTML = '';
      renderSnapshot(s);
    }).catch(function (e) {
      ctx.fail(box, e);
    });
  }
});
