/// 测试面板（仅测试 / 灰度功能入口）
///
/// 定位：**面向大众用户时整块隐藏**，只对灰度用户开放（见 [AppConfigService.testPanelVisible]）。
/// 因此这里放的都是"诊断类、实验类"能力，不影响正式功能的观感。
///
/// 新增测试功能的做法：在下方 PlainGroup 里加一条即可，无需改「我的」页。
library;

import 'package:flutter/material.dart';

import '../common/plain_group.dart';
import 'sync_diagnostics_page.dart';

class TestPanelPage extends StatelessWidget {
  const TestPanelPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('测试')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: <Widget>[
          PlainGroup(entries: <PlainGroupEntry>[
            PlainGroupEntry(
              icon: Icons.sync_problem_outlined,
              color: const Color(0xFF7C3AED),
              label: '同步诊断',
              trailingText: '多设备不一致时用它',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const SyncDiagnosticsPage()),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '这里是测试功能入口：仅用于排查与灰度验证，'
              '正式发布时会对普通用户隐藏。',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF9CA3AF), height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}
