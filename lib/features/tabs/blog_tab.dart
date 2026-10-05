/// 博客 Tab（职管家 · 个人职业版）
///
/// 职业内容社区：行业文章 / 职业洞察 / 专栏。
/// 顶栏三个子 Tab：推荐 / 关注 / 我的；右下角浮动「＋」用于写博客。
/// 当前版本：
/// - 推荐 / 关注：占位（后续接智能推荐与关注关系）；
/// - 写博客 → 本地存储（[BlogStore]）→ 在「我的」中展示，为最小可用闭环。
library;

import 'package:flutter/material.dart';

import '../blog/blog_editor_page.dart';
import '../blog/blog_store.dart';

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

  /// 我发布的博客（本地）
  List<BlogPost> _myPosts = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _loadMyPosts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 供主框架在切到本页时调用刷新
  void refresh() {
    if (mounted) {
      _loadMyPosts();
      setState(() {});
    }
  }

  Future<void> _loadMyPosts() async {
    final posts = await BlogStore.loadMyPosts();
    if (mounted) setState(() => _myPosts = posts);
  }

  Future<void> _openEditor() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const BlogEditorPage()),
    );
    if (ok == true) {
      await _loadMyPosts();
      // 发布成功后切到「我的」，让用户立刻看到新文章
      _tabController.animateTo(2);
    }
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
        children: [
          const _BlogPlaceholder(
            icon: Icons.recommend_outlined,
            title: '推荐',
            desc: '结合你的职业画像与数据宇宙\n智能推荐行业文章与职业洞察',
          ),
          const _BlogPlaceholder(
            icon: Icons.people_alt_outlined,
            title: '关注',
            desc: '你关注的作者与专栏更新\n将在这里展示',
          ),
          _MyBlogsView(posts: _myPosts),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openEditor,
        backgroundColor: _kBrandOrange,
        foregroundColor: Colors.white,
        elevation: 4,
        tooltip: '写博客',
        child: const Icon(Icons.add, size: 30),
      ),
    );
  }
}

/// 推荐 / 关注 子 Tab 占位
class _BlogPlaceholder extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;

  const _BlogPlaceholder({
    required this.icon,
    required this.title,
    required this.desc,
  });

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
                child: Icon(icon, size: 36, color: _kBrandOrange),
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

/// 「我的」子 Tab：我发布的博客列表
class _MyBlogsView extends StatelessWidget {
  final List<BlogPost> posts;

  const _MyBlogsView({required this.posts});

  String _formatTime(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 110),
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
                  child: const Icon(Icons.edit_note,
                      size: 38, color: _kBrandOrange),
                ),
                const SizedBox(height: 16),
                const Text(
                  '还没有发布博客',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1B1C),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '点击右下角 ＋ 写第一篇博客',
                  style:
                      TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final post = posts[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                post.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1B1C),
                ),
              ),
              if (post.content.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  post.content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                _formatTime(post.createdAt),
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFFB5B9C0)),
              ),
            ],
          ),
        );
      },
    );
  }
}
