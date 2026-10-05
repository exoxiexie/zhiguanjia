/// 学习页（职管家 · 个人职业版）
///
/// 由「发现」页的「学习」通栏卡片进入。
/// 当前为占位页，功能后续开发。
library;

import 'package:flutter/material.dart';

/// 学习页（占位）
class LearningPage extends StatelessWidget {
  const LearningPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('学习'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0,
      ),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 56, color: Color(0xFFC4C8CE)),
            SizedBox(height: 16),
            Text(
              '学习模块建设中',
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
