/// 发现 Tab（职管家 · 个人职业版）
///
/// 面向个人的职业机会发现：岗位 / 培训 / 证书 / 职业服务等 AI 推荐。
/// MVP 阶段先搭结构占位，后续对齐智懂你发现页的 AI 搜索 + 推荐流形态。
library;

import 'package:flutter/material.dart';

import '../../contracts/agent_service.dart';
import '../../contracts/chat_service.dart';

/// 发现页（职业机会发现，占位）
class DiscoverTab extends StatefulWidget {
  final ChatService? chatService;
  final AgentService? agentService;

  const DiscoverTab({super.key, this.chatService, this.agentService});

  @override
  State<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<DiscoverTab> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: const _ComingSoon(
          icon: Icons.explore_outlined,
          title: '职业机会发现',
          desc: '基于你的职业数据宇宙，千人千面推荐\n岗位、培训、证书与职业服务',
        ),
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
