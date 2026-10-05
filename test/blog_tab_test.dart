/// 博客 Tab 测试（对应本次三个修改点）
///
/// 1. 发布后同时出现在「推荐」流与「我的」列表，且推荐流第一条为最新一篇；
/// 2. 无标题博客不显示「无标题」占位、不显示分隔线，直接显示正文；
/// 3. 三个子 Tab 下方的灰色分隔线已移除（选中态橙色下划线不受影响）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhiguanjia/features/blog/blog_post_card.dart';
import 'package:zhiguanjia/features/blog/blog_store.dart';
import 'package:zhiguanjia/features/tabs/blog_tab.dart';

const String _authKey = 'zhiguanjia.personal.auth';
const String _phone = '13800138000';
const String _postsKey = 'blog_posts_$_phone';

/// 已登录态（博客按手机号做租户隔离）
String _authJson() => jsonEncode({
      'token': 'mock-token',
      'phone': _phone,
      'name': '张三',
    });

String _postJson({
  required String id,
  required String title,
  required String content,
  required int createdAt,
}) =>
    jsonEncode({
      'id': id,
      'title': title,
      'content': content,
      'createdAt': createdAt,
    });

/// 预置数据并渲染博客页
Future<void> _pumpBlogTab(
  WidgetTester tester, {
  List<String> posts = const [],
}) async {
  SharedPreferences.setMockInitialValues({
    _authKey: _authJson(),
    if (posts.isNotEmpty) _postsKey: posts,
  });
  await tester.pumpWidget(const MaterialApp(home: BlogTab()));
  await tester.pumpAndSettle();
}

/// 切换到指定子 Tab（0 推荐 / 1 关注 / 2 我的）
///
/// 用 Tab 组件定位而非文本，避免与空态标题中的同名文字冲突。
Future<void> _switchTab(WidgetTester tester, int index) async {
  await tester.tap(find.byType(Tab).at(index));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('修改点 3：子 Tab 下方灰色分隔线已移除', () {
    testWidgets('TabBar 分隔线被禁用，橙色选中下划线保留', (tester) async {
      await _pumpBlogTab(tester);

      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabBar.dividerHeight, 0, reason: '灰色分隔线高度应为 0');
      expect(tabBar.dividerColor, Colors.transparent, reason: '分隔线颜色应为透明');
      // 选中态橙色下划线不受影响
      expect(tabBar.indicatorColor, const Color(0xFFFD5C13));
      expect(tabBar.indicatorWeight, 3);
    });
  });

  group('修改点 2：无标题博客只显示正文', () {
    testWidgets('空标题：不显示「无标题」、不显示分隔线，直接显示正文', (tester) async {
      await _pumpBlogTab(tester, posts: [
        _postJson(
          id: '1',
          title: '',
          content: '这是一篇没有标题的博客正文',
          createdAt: 1750000000000,
        ),
      ]);

      expect(find.text('无标题'), findsNothing, reason: '不应出现占位标题');
      expect(find.text('这是一篇没有标题的博客正文'), findsOneWidget, reason: '正文应直接展示');
      expect(find.byType(Divider), findsNothing, reason: '卡片内不应有分隔线');
    });

    testWidgets('历史数据 title=「无标题」同样按无标题处理', (tester) async {
      await _pumpBlogTab(tester, posts: [
        _postJson(
          id: '1',
          title: BlogPost.legacyUntitled,
          content: '历史版本写下的正文',
          createdAt: 1750000000000,
        ),
      ]);

      expect(find.text('无标题'), findsNothing);
      expect(find.text('历史版本写下的正文'), findsOneWidget);
    });

    testWidgets('纯空白标题视为无标题', (tester) async {
      await _pumpBlogTab(tester, posts: [
        _postJson(id: '1', title: '   ', content: '空白标题的正文', createdAt: 1),
      ]);

      expect(find.text('   '), findsNothing);
      expect(find.text('空白标题的正文'), findsOneWidget);
    });

    testWidgets('有标题：标题与正文都显示，且卡片内无分隔线', (tester) async {
      await _pumpBlogTab(tester, posts: [
        _postJson(
          id: '1',
          title: '我的第一篇职业洞察',
          content: '正文内容在这里',
          createdAt: 1750000000000,
        ),
      ]);

      expect(find.text('我的第一篇职业洞察'), findsOneWidget);
      expect(find.text('正文内容在这里'), findsOneWidget);
      expect(find.byType(Divider), findsNothing);
    });

    testWidgets('BlogPost.showTitle 规则', (tester) async {
      BlogPost post(String title) =>
          BlogPost(id: '1', title: title, content: 'c', createdAt: 0);

      expect(post('我的标题').showTitle, isTrue);
      expect(post('').showTitle, isFalse);
      expect(post('   ').showTitle, isFalse);
      expect(post(BlogPost.legacyUntitled).showTitle, isFalse);
    });
  });

  group('修改点 1：发布后推荐流与我的列表同时可见', () {
    testWidgets('两个列表都展示已发布博客，推荐流第一条为最新一篇', (tester) async {
      await _pumpBlogTab(tester, posts: [
        _postJson(
          id: '1',
          title: '较早的一篇',
          content: '旧正文',
          createdAt: 1750000000000,
        ),
        _postJson(
          id: '2',
          title: '最新的一篇',
          content: '新正文',
          createdAt: 1750000600000,
        ),
      ]);

      // 推荐流（默认子 Tab）
      final recommendCards =
          tester.widgetList<BlogPostCard>(find.byType(BlogPostCard)).toList();
      expect(recommendCards.length, 2, reason: '推荐流应展示两篇博客');
      expect(recommendCards.first.post.title, '最新的一篇',
          reason: '推荐流第一条必须是最新发布的一篇');

      // 我的列表
      await _switchTab(tester, 2);
      final mineCards =
          tester.widgetList<BlogPostCard>(find.byType(BlogPostCard)).toList();
      expect(mineCards.length, 2, reason: '我的列表应展示同样的两篇');
      expect(mineCards.first.post.title, '最新的一篇');
    });

    testWidgets('走完整发布流程：编辑器发布后，推荐流与我的列表都出现该博客', (tester) async {
      await _pumpBlogTab(tester); // 初始为空

      // 空态下不应有卡片
      expect(find.byType(BlogPostCard), findsNothing);

      // 点右下角 ＋ 写博客
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '新发布的职业洞察');
      await tester.enterText(find.byType(TextField).last, '发布流程验证正文');
      await tester.tap(find.text('发布'));
      await tester.pumpAndSettle();

      // 发布后自动停在「我的」
      final mineCards =
          tester.widgetList<BlogPostCard>(find.byType(BlogPostCard)).toList();
      expect(mineCards.length, 1);
      expect(mineCards.first.post.title, '新发布的职业洞察');

      // 切到推荐流：同样能看到，且是最新一条
      await _switchTab(tester, 0);
      final recommendCards =
          tester.widgetList<BlogPostCard>(find.byType(BlogPostCard)).toList();
      expect(recommendCards.length, 1, reason: '推荐流应同步出现新发布的博客');
      expect(recommendCards.first.post.title, '新发布的职业洞察');
      expect(recommendCards.first.post.content, '发布流程验证正文');
    });

    testWidgets('无标题发布：正文进入推荐流，且不出现「无标题」', (tester) async {
      await _pumpBlogTab(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '只写了正文的一篇');
      await tester.tap(find.text('发布'));
      await tester.pumpAndSettle();

      // 存储层不再填充「无标题」占位
      final stored = await BlogStore.loadMyPosts();
      expect(stored.length, 1);
      expect(stored.first.title, '', reason: '不应写入「无标题」占位文字');

      await _switchTab(tester, 0);
      expect(find.text('无标题'), findsNothing);
      expect(find.text('只写了正文的一篇'), findsOneWidget);
    });
  });

  group('空态语义', () {
    testWidgets('推荐 / 我的 空态不显示「即将上线」，关注仍显示', (tester) async {
      await _pumpBlogTab(tester);

      // 推荐空态
      expect(find.text('即将上线'), findsNothing);

      // 我的空态
      await _switchTab(tester, 2);
      expect(find.text('还没有发布博客'), findsOneWidget);
      expect(find.text('即将上线'), findsNothing);

      // 关注：功能未开放，显示角标
      await _switchTab(tester, 1);
      expect(find.text('即将上线'), findsOneWidget);
    });
  });

  group('存储层健壮性', () {
    testWidgets('损坏记录被跳过，其余博客正常展示', (tester) async {
      await _pumpBlogTab(tester, posts: [
        '这不是合法 JSON',
        _postJson(id: '2', title: '正常的一篇', content: '正文', createdAt: 2),
      ]);

      expect(find.text('正常的一篇'), findsOneWidget);
      expect(find.byType(BlogPostCard), findsOneWidget);
    });
  });
}
