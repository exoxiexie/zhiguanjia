/// 发现 Tab（职管家 · 个人职业版）
///
/// 微信式发现页：通栏卡片分组，每行 = 图标 + 名称 + 右箭头，点开进入对应页面。
/// 通栏样式统一由 [PlainGroup] 提供（数据页的模块入口用的是同一个组件）。
/// 第一批通栏模块三张卡片（**各自独立成卡**，互不同组），自上而下：
/// - 职说：原底栏「说说」Tab 的内容，折叠进本页；
/// - 学习：占位模块，功能后续开发；
/// - 招聘：原「发现」页的职位推荐流，折叠进本页。
library;

import 'package:flutter/material.dart';

import '../../contracts/agent_service.dart';
import '../../contracts/chat_service.dart';
import '../common/plain_group.dart';
import '../tabs/blog_tab.dart';
import 'learning_page.dart';
import 'recruit_page.dart';

/// 页面底色
const Color _kPageBg = Color(0xFFF5F5F5);

/// 发现页（微信式通栏模块入口）
class DiscoverTab extends StatelessWidget {
  final ChatService? chatService;
  final AgentService? agentService;

  const DiscoverTab({super.key, this.chatService, this.agentService});

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kPageBg,
      appBar: AppBar(
        title: const Text('发现'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12),
        children: [
          // 三张模块卡片各自独立成卡，互不同组
          PlainGroup(
            entries: [
              PlainGroupEntry(
                icon: Icons.chat_bubble_outline,
                color: const Color(0xFFFD5C13),
                label: '职说',
                onTap: () => _open(context, const BlogTab(standalone: true)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          PlainGroup(
            entries: [
              PlainGroupEntry(
                icon: Icons.menu_book_outlined,
                color: const Color(0xFF3B7CF6),
                label: '学习',
                onTap: () => _open(context, const LearningPage()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          PlainGroup(
            entries: [
              PlainGroupEntry(
                icon: Icons.work_outline,
                color: const Color(0xFF16B89C),
                label: '招聘',
                onTap: () => _open(context, const RecruitPage()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
