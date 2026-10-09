/// 同步诊断页（排查多设备数据不一致）
///
/// 设计动机：同步失败原本**全部静默**，线上只能靠猜。本页把「本机有多少数据、
/// 有多少还没发出去、游标在哪、服务端有多少、上次失败原因」一次摊开，
/// 用户复制一段文字即可定位问题，不必连电脑抓日志。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../sync/sync_engine.dart';

class SyncDiagnosticsPage extends StatefulWidget {
  const SyncDiagnosticsPage({super.key});

  @override
  State<SyncDiagnosticsPage> createState() => _SyncDiagnosticsPageState();
}

class _SyncDiagnosticsPageState extends State<SyncDiagnosticsPage> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await SyncEngine.diagnose();
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    await SyncEngine.sync(force: true);
    if (!mounted) return;
    setState(() => _syncing = false);
    await _load();
  }

  String _report() {
    final d = _data ?? const <String, dynamic>{};
    return <String>[
      '职管家 · 同步诊断',
      '账号：${d['phone']}',
      '本机会话：${d['local_conversations']}   本机消息：${d['local_messages']}',
      '待发队列：${d['outbox_pending']}',
      '本机游标：${d['local_cursor']}',
      '服务端：${d['server_ok'] == true ? '可访问' : '不可访问 ${d['server_error']}'}',
      '服务端游标：${d['server_seq']}',
      '服务端会话：${d['server_conversations']}   服务端消息：${d['server_messages']}',
      '上次同步：${d['last_sync_at']}',
      '上次推送：${d['last_pushed']} 条   上次拉取：${d['last_pulled']} 条',
      '推送错误：${(d['last_push_error'] as String).isEmpty ? '无' : d['last_push_error']}',
      '拉取错误：${(d['last_pull_error'] as String).isEmpty ? '无' : d['last_pull_error']}',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final d = _data ?? const <String, dynamic>{};
    final pending = (d['outbox_pending'] as int?) ?? 0;
    final pushError = (d['last_push_error'] as String?) ?? '';
    final pullError = (d['last_pull_error'] as String?) ?? '';
    final serverOk = d['server_ok'] == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('同步诊断'),
        actions: <Widget>[
          IconButton(
            tooltip: '复制报告',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: _loading
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: _report()));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('诊断报告已复制，可粘贴发送')));
                  },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                if (pending > 0)
                  _banner(
                    color: const Color(0xFFFEF3C7),
                    icon: Icons.warning_amber_rounded,
                    title: '有 $pending 条变更还没发出去',
                    body: '说明推送这一步没成功。点下方「立即同步」重试；'
                        '若一直是这个数字，把报告发我排查。',
                  )
                else
                  _banner(
                    color: const Color(0xFFDCFCE7),
                    icon: Icons.check_circle_outline,
                    title: '发件箱已清空',
                    body: '本机所有变更都已推送成功。',
                  ),
                if (pushError.isNotEmpty)
                  _banner(
                    color: const Color(0xFFFEE2E2),
                    icon: Icons.cloud_off_outlined,
                    title: '推送失败原因',
                    body: pushError,
                  ),
                if (pullError.isNotEmpty)
                  _banner(
                    color: const Color(0xFFFEE2E2),
                    icon: Icons.download_for_offline_outlined,
                    title: '拉取失败原因',
                    body: pullError,
                  ),
                const SizedBox(height: 8),
                _section('本机', <String, String>{
                  '账号': '${d['phone']}',
                  '会话数': '${d['local_conversations']}',
                  '消息数': '${d['local_messages']}',
                  '待发队列': '$pending',
                  '同步游标': '${d['local_cursor']}',
                }),
                _section('服务端', <String, String>{
                  '连通性': serverOk ? '正常' : '不可访问（${d['server_error']}）',
                  '服务端游标': '${d['server_seq']}',
                  '会话数': '${d['server_conversations']}',
                  '消息数': '${d['server_messages']}',
                  '记忆数': '${d['server_memories']}',
                  '搜索沉淀': '${d['server_search_items']}',
                }),
                _section('最近一次同步', <String, String>{
                  '时间': '${(d['last_sync_at'] as String).isEmpty ? '未同步过' : d['last_sync_at']}',
                  '推送': '${d['last_pushed']} 条',
                  '拉取': '${d['last_pulled']} 条',
                }),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _syncing ? null : _syncNow,
                  icon: _syncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync),
                  label: Text(_syncing ? '同步中…' : '立即同步'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                ),
                const SizedBox(height: 12),
                const Text(
                  '提示：两台设备都看完这一页后，把两边的报告发我对比，'
                  '就能定位是"这台没发出去"还是"那台没拉下来"。',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF6B7280), height: 1.6),
                ),
              ],
            ),
    );
  }

  Widget _banner({
    required Color color,
    required IconData icon,
    required String title,
    required String body,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration:
            BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(body,
                    style: const TextStyle(fontSize: 12.5, height: 1.6)),
              ],
            ),
          ),
        ]),
      );

  Widget _section(String title, Map<String, String> rows) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFECEFF3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280))),
            const SizedBox(height: 8),
            for (final e in rows.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: <Widget>[
                  SizedBox(
                      width: 96,
                      child: Text(e.key,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF6B7280)))),
                  Expanded(
                      child: Text(e.value,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600))),
                ]),
              ),
          ],
        ),
      );
}
