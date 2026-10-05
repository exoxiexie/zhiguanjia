/// 发现 Tab（职管家 · 个人职业版）
///
/// 微信式发现页：通栏卡片分组，每行 = 图标 + 名称 + 右箭头，点开进入对应页面。
/// 第一批通栏模块三张卡片（**各自独立成卡**，互不同组），自上而下：
/// - 说说：原底栏「说说」Tab 的内容，折叠进本页；
/// - 学习：占位模块，功能后续开发；
/// - 招聘：原「发现」页的职位推荐流，折叠进本页。
library;

import 'package:flutter/material.dart';

import '../../contracts/agent_service.dart';
import '../../contracts/chat_service.dart';
import '../tabs/blog_tab.dart';
import 'learning_page.dart';
import 'recruit_page.dart';

/// 页面底色
const Color _kPageBg = Color(0xFFF5F5F5);

/// 通栏卡片行间分割线
const Color _kRowDivider = Color(0xFFEDEEF0);

/// 右箭头颜色
const Color _kChevron = Color(0xFFC4C8CE);

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
          _DiscoverGroup(
            entries: [
              _DiscoverEntry(
                icon: Icons.chat_bubble_outline,
                color: const Color(0xFFFD5C13),
                label: '说说',
                onTap: () => _open(context, const BlogTab(standalone: true)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DiscoverGroup(
            entries: [
              _DiscoverEntry(
                icon: Icons.menu_book_outlined,
                color: const Color(0xFF3B7CF6),
                label: '学习',
                onTap: () => _open(context, const LearningPage()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DiscoverGroup(
            entries: [
              _DiscoverEntry(
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

/// 一条通栏卡片的配置
class _DiscoverEntry {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _DiscoverEntry({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });
}

/// 一组通栏卡片（白底圆角，行间细分割线）
class _DiscoverGroup extends StatelessWidget {
  final List<_DiscoverEntry> entries;

  const _DiscoverGroup({required this.entries});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 56,
                color: _kRowDivider,
              ),
            _DiscoverRow(entry: entries[i]),
          ],
        ],
      ),
    );
  }
}

/// 单行：图标 + 名称 + 右箭头
class _DiscoverRow extends StatelessWidget {
  final _DiscoverEntry entry;

  const _DiscoverRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: entry.onTap,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(entry.icon, size: 24, color: entry.color),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    entry.label,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF1A1B1C),
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, size: 22, color: _kChevron),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
