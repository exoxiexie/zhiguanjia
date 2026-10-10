/// 设备上报诊断（**灰度**：入口只出现在「设置 → 测试」里，普通用户看不到）
///
/// 为什么需要它：`AppConfigService.reportDevice()` 以前是 `catch (_) {}` 完全静默，
/// 服务端连续 30 次返回 422 坏了几个月都没人发现 —— 唯一信号是后台"设备数恒为 0"。
/// 这里把每次上报的结果显示出来，并提供「立即上报」，让失败**当场可见**。
library;

import 'package:flutter/material.dart';

import 'app_config_service.dart';
import 'device_report_state.dart';

class DeviceReportPage extends StatefulWidget {
  const DeviceReportPage({super.key});

  @override
  State<DeviceReportPage> createState() => _DeviceReportPageState();
}

class _DeviceReportPageState extends State<DeviceReportPage> {
  DeviceReportSnapshot? _snapshot;
  bool _loading = true;
  bool _reporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snap = await DeviceReportState.load();
    if (!mounted) return;
    setState(() {
      _snapshot = snap;
      _loading = false;
    });
  }

  Future<void> _reportNow() async {
    setState(() => _reporting = true);
    await AppConfigService.reportDevice(); // 内部会把结果写入 DeviceReportState
    await _load();
    if (!mounted) return;
    setState(() => _reporting = false);
    final snap = _snapshot;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(snap == null
          ? '已发起上报'
          : (snap.ok ? '上报成功' : '上报失败：${snap.message}')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('设备上报诊断')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: <Widget>[
                _card(
                  title: '最近一次上报',
                  children: <Widget>[
                    _row('结果', snap == null ? '还没有记录' : (snap.ok ? '成功' : '失败'),
                        valueColor: snap == null
                            ? null
                            : (snap.ok
                                ? const Color(0xFF059669)
                                : const Color(0xFFD05656))),
                    _row('时间', snap?.at.isNotEmpty == true ? snap!.at : '—'),
                    if (snap != null && !snap.ok) _row('原因', snap.message),
                  ],
                ),
                const SizedBox(height: 12),
                _card(
                  title: '上报内容（设备信息）',
                  children: <Widget>[
                    if (snap == null || snap.info.isEmpty)
                      _row('—', '尚无数据（点下方按钮立即上报）')
                    else
                      for (final e in snap.info.entries) _row(e.key, e.value),
                  ],
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: FilledButton(
                    onPressed: _reporting ? null : _reportNow,
                    child: Text(_reporting ? '上报中…' : '立即上报'),
                  ),
                ),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    '说明：上报用于装机量与版本分布统计，失败不影响任何功能，'
                    '但会体现在后台「用户管理 → 设备 / 最近活跃」里。\n'
                    '常见失败原因：未登录、网络不可用、服务端字段校验变化。',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF9CA3AF), height: 1.6),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _card({required String title, required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _row(String key, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 76,
            child: Text(key,
                style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13.5, height: 1.5, color: valueColor ?? const Color(0xFF1F2937))),
          ),
        ],
      ),
    );
  }
}
