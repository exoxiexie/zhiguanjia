/// 数据 Tab（职管家 · 个人职业版）
///
/// 个人职业数据宇宙：对话记忆 / 本地私有 / 外接应用等多源数据沉淀。
/// MVP 阶段先搭结构占位，后续对齐智懂你数据页的标签/来源/任务三视图。
library;

import 'package:flutter/material.dart';

class DatabaseTab extends StatefulWidget {
  const DatabaseTab({super.key});

  @override
  State<DatabaseTab> createState() => DatabaseTabState();
}

class DatabaseTabState extends State<DatabaseTab> {
  /// 供主框架在切到本页时调用刷新（接口保留，占位期为空实现）
  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('数据'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: const Color(0xFFF5F5F5),
        foregroundColor: const Color(0xFF1A1B1C),
      ),
      body: const _ComingSoon(
        icon: Icons.dataset_outlined,
        title: '职业数据宇宙',
        desc: '对话记忆、简历、证书、作品与职业资料\n将在这里按标签结构化沉淀',
      ),
    );
  }
}

/// “建设中”占位
class _ComingSoon extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;

  const _ComingSoon({
    required this.icon,
    required this.title,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF5B7FD4).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: const Color(0xFF5B7FD4)),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1B1C),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              desc,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF), height: 1.6),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF5B7FD4).withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '即将上线',
                style: TextStyle(fontSize: 12, color: Color(0xFF5B7FD4)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
