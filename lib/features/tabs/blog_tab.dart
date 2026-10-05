/// 博客 Tab（职管家 · 个人职业版）
///
/// 职业内容社区：行业文章 / 职业洞察 / 专栏。
/// 顶栏三个子 Tab：推荐 / 关注 / 我的；右下角浮动「＋」用于写博客。
///
/// 当前版本：
/// - 发布博客 → 本地存储（[BlogStore]）→ **同时**出现在「推荐」流与「我的」列表；
///   两个列表均按发布时间倒序，新发布的一条即最新一条（推荐流第一条）；
/// - 卡片渲染规则统一由 [BlogPostCard] 提供，保证两个入口呈现一致
///   （无标题只显示正文，不显示占位标题与分隔线）；
/// - 「推荐」的智能推荐算法、「关注」的关注关系待后续接入（关注当前为空态占位）。
library;

import 'package:flutter/material.dart';

import '../blog/blog_editor_page.dart';
import '../blog/blog_post_card.dart';
import '../blog/blog_store.dart';

/// 品牌活力橙（与 App 图标主色一致）
const Color _kBrandOrange = Color(0xFFFD5C13);

/// 页面底色
const Color _kPageBg = Color(0xFFF5F5F5);

class BlogTab extends StatefulWidget {
  const BlogTab({super.key});

  @override
  State<BlogTab> createState() => _BlogTabState();
}

class _BlogTabState extends State<BlogTab> with SingleTickerProviderStateMixin {
  static const List<String> _tabs = ['推荐', '关注', '我的'];

  /// 「我的」子 Tab 下标（发布成功后跳转到此）
  static const int _mineTabIndex = 2;

  late final TabController _tabController;

  /// 我发布的博客（本地）；「推荐」流与「我的」列表共用同一份数据，
  /// 因此发布后两处同时可见，无需分别刷新。
  List<BlogPost> _myPosts = [];
  bool _loading = true;

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
    if (mounted) _loadMyPosts();
  }

  Future<void> _loadMyPosts() async {
    final posts = await BlogStore.loadMyPosts();
    if (mounted) {
      setState(() {
        _myPosts = posts;
        _loading = false;
      });
    }
  }

  Future<void> _openEditor() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const BlogEditorPage()),
    );
    if (ok == true) {
      await _loadMyPosts();
      // 发布成功后切到「我的」，让用户立刻看到新文章（推荐流同样已包含）
      _tabController.animateTo(_mineTabIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kPageBg,
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
              // 去掉 Material 3 为 TabBar 默认绘制的灰色分隔线
              // （即三个子 Tab 下方那根灰线；选中态的橙色下划线不受影响）
              dividerColor: Colors.transparent,
              dividerHeight: 0,
              tabs: [for (final t in _tabs) Tab(text: t)],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 推荐流：当前展示已发布的博客（倒序，最新一条在最前）；
          // 正式推荐逻辑（结合职业画像与数据宇宙）后续接入。
          _PostList(
            posts: _myPosts,
            loading: _loading,
            emptyIcon: Icons.recommend_outlined,
            emptyTitle: '推荐',
            emptyDesc: '你发布的博客会出现在这里\n结合职业画像与数据宇宙的智能推荐即将上线',
          ),
          const _BlogPlaceholder(
            icon: Icons.people_alt_outlined,
            title: '关注',
            desc: '你关注的作者与专栏更新\n将在这里展示',
            comingSoon: true,
          ),
          _PostList(
            posts: _myPosts,
            loading: _loading,
            emptyIcon: Icons.edit_note,
            emptyTitle: '还没有发布博客',
            emptyDesc: '点击右下角 ＋ 写第一篇博客',
          ),
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

/// 博客列表（「推荐」流与「我的」共用）
///
/// 只负责列表容器与空态；单条卡片的渲染规则统一交给 [BlogPostCard]。
class _PostList extends StatelessWidget {
  final List<BlogPost> posts;
  final bool loading;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyDesc;

  const _PostList({
    required this.posts,
    required this.loading,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyDesc,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (posts.isEmpty) {
      return _BlogPlaceholder(
        icon: emptyIcon,
        title: emptyTitle,
        desc: emptyDesc,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      itemCount: posts.length,
      itemBuilder: (context, index) => BlogPostCard(post: posts[index]),
    );
  }
}

/// 空态 / 未开放占位
///
/// [comingSoon] 仅在功能尚未开放时显示「即将上线」角标；
/// 列表为空（如「还没有发布博客」）不属于未开放，不显示角标。
class _BlogPlaceholder extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final bool comingSoon;

  const _BlogPlaceholder({
    required this.icon,
    required this.title,
    required this.desc,
    this.comingSoon = false,
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
              if (comingSoon) ...[
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
            ],
          ),
        ),
      ],
    );
  }
}
