/// 博客 Tab（职管家 · 个人职业版）
///
/// 职业内容社区：行业文章 / 职业洞察 / 专栏。
/// 顶栏三个子 Tab：推荐 / 关注 / 我的。
/// 当前版本仅搭建 Tab 结构与占位，具体内容与功能后续开发。
library;

import 'package:flutter/material.dart';

/// 品牌活力橙（与 App 图标主色一致）
const Color _kBrandOrange = Color(0xFFFD5C13);

class BlogTab extends StatefulWidget {
  const BlogTab({super.key});

  @override
  State<BlogTab> createState() => _BlogTabState();
}

class _BlogTabState extends State<BlogTab>
    with SingleTickerProviderStateMixin {
  static const List<String> _tabs = ['推荐', '关注', '我的'];
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 供主框架在切到本页时调用刷新（接口保留，占位期为空实现）
  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: Center(
          child: SizedBox(
            width: 240,
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF1A1B1C),
              unselectedLabelColor: const Color(0xFF9CA3AF),
              labelStyle:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              unselectedLabelStyle:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
              indicatorColor: _kBrandOrange,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.label,
              indicatorPadding: const EdgeInsets.only(bottom: 2),
              splashFactory: NoSplash.splashFactory,
              overlayColor: MaterialStateProperty.all(Colors.transparent),
              tabs: [for (final t in _tabs) Tab(text: t)],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _BlogPlaceholder(
            title: '推荐',
            desc: '精选行业文章与职业洞察\n将在这里为你推荐',
          ),
          _BlogPlaceholder(
            title: '关注',
            desc: '你关注的作者与专栏更新\n将在这里展示',
          ),
          _BlogPlaceholder(
            title: '我的',
            desc: '你的发布、收藏与浏览记录\n将在这里管理',
          ),
        ],
      ),
    );
  }
}

/// 子 Tab 内容占位
class _BlogPlaceholder extends StatelessWidget {
  final String title;
  final String desc;

  const _BlogPlaceholder({required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: _kBrandOrange.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.article_outlined,
                    size: 36, color: _kBrandOrange),
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
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF9CA3AF), height: 1.6),
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _kBrandOrange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '即将上线',
                  style: TextStyle(fontSize: 12, color: _kBrandOrange),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
