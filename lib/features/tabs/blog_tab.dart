/// 说说 Tab（职管家 · 个人职业版）
///
/// 职业内容社区：行业文章 / 职业洞察 / 专栏。
/// 顶栏三个子 Tab：推荐 / 关注 / 我的；右下角浮动「＋」用于写说说。
///
/// 当前版本：
/// - **推荐 / 关注**：展示本机所有作者发布的说说**时间线**（倒序，最新一条在最前）。
///   推荐规则与关注关系待后续接入，当前先以全量时间线解决内容过少的问题；
/// - **我的**：只展示当前登录账号发布的说说（按作者手机号隔离）；
/// - 发布后自动刷新，新文章同时出现在时间线与「我的」；
/// - 卡片渲染规则统一由 [BlogPostCard] 提供（作者信息置顶；无标题只显示正文）。
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

  /// 全站时间线：本机所有作者发布的说说（「推荐」「关注」共用）
  List<BlogPost> _feedPosts = [];

  /// 我发布的说说（本地，按作者手机号隔离）
  List<BlogPost> _myPosts = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _loadPosts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 供主框架在切到本页时调用刷新
  void refresh() {
    if (mounted) _loadPosts();
  }

  /// 一次读取两份数据：时间线（推荐/关注）与我的（我的）
  Future<void> _loadPosts() async {
    final feed = await BlogStore.loadFeed();
    final mine = await BlogStore.loadMyPosts();
    if (mounted) {
      setState(() {
        _feedPosts = feed;
        _myPosts = mine;
        _loading = false;
      });
    }
  }

  Future<void> _openEditor() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const BlogEditorPage()),
    );
    if (ok == true) {
      await _loadPosts();
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
          // 推荐：全量时间线（推荐算法接入前的过渡形态）
          _PostList(
            posts: _feedPosts,
            loading: _loading,
            emptyIcon: Icons.recommend_outlined,
            emptyTitle: '还没有说说内容',
            emptyDesc: '所有人发布的说说会按时间线出现在这里\n点击右下角 ＋ 发布第一篇',
          ),
          // 关注：关注关系接入前同样展示全量时间线，避免内容过少
          _PostList(
            posts: _feedPosts,
            loading: _loading,
            emptyIcon: Icons.people_alt_outlined,
            emptyTitle: '还没有说说内容',
            emptyDesc: '关注关系上线前，这里先展示全部说说时间线\n点击右下角 ＋ 发布第一篇',
          ),
          _PostList(
            posts: _myPosts,
            loading: _loading,
            emptyIcon: Icons.edit_note,
            emptyTitle: '还没有发布说说',
            emptyDesc: '点击右下角 ＋ 写第一篇说说',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openEditor,
        backgroundColor: _kBrandOrange,
        foregroundColor: Colors.white,
        elevation: 4,
        tooltip: '写说说',
        child: const Icon(Icons.add, size: 30),
      ),
    );
  }
}

/// 说说列表（「推荐」「关注」「我的」共用）
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
      return _BlogEmpty(
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

/// 列表空态
class _BlogEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;

  const _BlogEmpty({
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
            ],
          ),
        ),
      ],
    );
  }
}
