/// 懂你 Tab · 占位页（职管家 · 个人职业版）
///
/// **定位**：底栏第 3 格的独立 Tab，与「对话」分开 ——
/// 「对话」负责与 AI 交互完成任务，本页将来负责「真正懂你」这件事
/// （职业画像、成长洞察、数据解读等），当前先占位。
/// 由 [ShellPage] 承载，顶栏由本页自行提供。
library;

import 'package:flutter/material.dart';

/// 懂你页（占位）
class InsightTab extends StatelessWidget {
  const InsightTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('懂你'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lightbulb_outline, size: 56, color: Color(0xFFC4C8CE)),
            SizedBox(height: 16),
            Text(
              '功能建设中',
              style: TextStyle(fontSize: 16, color: Color(0xFF6B7280)),
            ),
            SizedBox(height: 8),
            Text(
              '功能陆续开放，敬请期待',
              style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
      ),
    );
  }
}
