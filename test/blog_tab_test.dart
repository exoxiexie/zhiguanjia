/// 博客 Tab 测试（覆盖本次「作者信息置顶 + 全站时间线」改造，及此前的回归点）
///
/// 覆盖点：
/// 1. 卡片排版：作者信息（头像/昵称/发布时间）在顶部，标题与正文在下；
/// 2. 推荐 / 关注：展示本机**所有作者**的博客时间线，按发布时间倒序；
/// 3. 我的：只展示当前登录账号的博客（租户隔离）；
/// 4. 无标题博客：不显示「无标题」占位与分隔线，直接显示正文；
/// 5. 历史数据（无作者字段）的作者昵称回填与兜底；
/// 6. 子 Tab 灰色分隔线已移除；损坏记录跳过。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhiguanjia/features/blog/blog_author_avatar.dart';
import 'package:zhiguanjia/features/blog/blog_post_card.dart';
import 'package:zhiguanjia/features/blog/blog_store.dart';
import 'package:zhiguanjia/features/tabs/blog_tab.dart';

const String _authKey = 'zhiguanjia.personal.auth';
const String _usersKey = 'zhiguanjia.personal.users';

/// 当前登录账号
const String _mePhone = '13800138000';
const String _meName = '张三';

/// 另一个作者（同一台设备上的其他账号）
const String _otherPhone = '13900139000';
const String _otherName = '李四';

String _authJson({String phone = _mePhone, String name = _meName}) =>
    jsonEncode({
      'token': 'mock-token',
      'phone': phone,
      'name': name,
    });

/// 用户表条目（注意：PersonalAuthService 用 setString 存整份 JSON 数组）
Map<String, dynamic> _userJson({required String phone, required String name}) => {
      'phone': phone,
      'password': '123456',
      'name': name,
      'createdAt': '2026-01-01T00:00:00.000',
    };

/// 博客 JSON；authorPhone/authorName 留空即模拟 v1.0.7/v1.0.8 的历史数据
String _postJson({
  required String id,
  String title = '',
  String content = '',
  required int createdAt,
  String authorPhone = '',
  String authorName = '',
}) =>
    jsonEncode({
      'id': id,
      'title': title,
      'content': content,
      'createdAt': createdAt,
      'authorPhone': authorPhone,
      'authorName': authorName,
    });

/// 预置数据并渲染博客页
Future<void> _pumpBlogTab(
  WidgetTester tester, {
  Map<String, List<String>> groupedPosts = const {},
  List<Map<String, dynamic>> users = const [],
  String? auth,
}) async {
  SharedPreferences.setMockInitialValues({
    _authKey: auth ?? _authJson(),
    if (users.isNotEmpty) _usersKey: jsonEncode(users),
    ...groupedPosts,
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

/// 作者存储键（键后缀即作者手机号）
String _key(String phone) => 'blog_posts_$phone';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('卡片排版：作者信息置顶', () {
    testWidgets('头像 / 昵称 / 发布时间在顶部，标题与正文在其下方', (tester) async {
      await _pumpBlogTab(tester, groupedPosts: {
        _key(_mePhone): [
          _postJson(
            id: '1',
            title: '我的职业洞察',
            content: '正文内容',
            createdAt: 1750000000000,
            authorPhone: _mePhone,
            authorName: _meName,
          ),
        ],
      });

      // 作者信息元素都在
      expect(find.byType(BlogAuthorAvatar), findsOneWidget);
      expect(find.text(_meName), findsOneWidget);
      expect(find.text(formatBlogTime(1750000000000)), findsOneWidget);
      expect(find.text('我的职业洞察'), findsOneWidget);
      expect(find.text('正文内容'), findsOneWidget);

      // 垂直顺序：头像 → 昵称 → 标题 → 正文
      double top(Finder f) => tester.getTopLeft(f).dy;
      final avatarY = top(find.byType(BlogAuthorAvatar));
      final nameY = top(find.text(_meName));
      final titleY = top(find.text('我的职业洞察'));
      final bodyY = top(find.text('正文内容'));

      expect(avatarY, lessThanOrEqualTo(nameY), reason: '头像与昵称同一行、位于顶部');
      expect(nameY, lessThan(titleY), reason: '作者昵称必须在标题上方');
      expect(titleY, lessThan(bodyY), reason: '标题必须在正文上方');
    });

    testWidgets('头像取昵称首字，且不同作者底色不同', (tester) async {
      await _pumpBlogTab(tester, groupedPosts: {
        _key(_otherPhone): [
          _postJson(
            id: '1',
            content: '正文',
            createdAt: 1,
            authorPhone: _otherPhone,
            authorName: '李四',
          ),
        ],
      });

      final avatar =
          tester.widget<BlogAuthorAvatar>(find.byType(BlogAuthorAvatar));
      expect(avatar.initial, '李');
      expect(avatar.seed, _otherPhone, reason: '取色种子应为作者手机号');
      expect(blogAvatarColor(_otherPhone), blogAvatarColor(_otherPhone),
          reason: '同一作者底色必须稳定');
      expect(blogAvatarColor(_otherPhone), isNot(blogAvatarColor(_mePhone)),
          reason: '不同作者应取到不同底色');
    });

    testWidgets('发布时间展示在作者昵称下方、标题上方', (tester) async {
      const ms = 1750000000000;
      await _pumpBlogTab(tester, groupedPosts: {
        _key(_mePhone): [
          _postJson(
            id: '1',
            title: '标题',
            content: '正文',
            createdAt: ms,
            authorPhone: _mePhone,
            authorName: _meName,
          ),
        ],
      });

      final timeFinder = find.text(formatBlogTime(ms));
      expect(timeFinder, findsOneWidget);
      expect(tester.getTopLeft(timeFinder).dy,
          greaterThan(tester.getTopLeft(find.text(_meName)).dy));
      expect(tester.getTopLeft(timeFinder).dy,
          lessThan(tester.getTopLeft(find.text('标题')).dy));
    });
  });

  group('推荐 / 关注：全站时间线', () {
    /// 三个作者的博客：我（最新）、其他作者（中间）、我（最早）
    Map<String, List<String>> multiAuthorPosts() => {
          _key(_mePhone): [
            _postJson(
              id: 'mine-new',
              title: '我最新的一篇',
              content: '正文A',
              createdAt: 1750000300000,
              authorPhone: _mePhone,
              authorName: _meName,
            ),
            _postJson(
              id: 'mine-old',
              title: '我最早的一篇',
              content: '正文B',
              createdAt: 1750000000000,
              authorPhone: _mePhone,
              authorName: _meName,
            ),
          ],
          _key(_otherPhone): [
            _postJson(
              id: 'other-mid',
              title: '别人中间的一篇',
              content: '正文C',
              createdAt: 1750000100000,
              authorPhone: _otherPhone,
              authorName: _otherName,
            ),
          ],
        };

    testWidgets('推荐：列出所有作者的博客，按时间倒序', (tester) async {
      await _pumpBlogTab(tester, groupedPosts: multiAuthorPosts());

      final cards =
          tester.widgetList<BlogPostCard>(find.byType(BlogPostCard)).toList();
      expect(cards.length, 3, reason: '推荐应聚合所有作者的博客');
      expect(
        cards.map((c) => c.post.title).toList(),
        ['我最新的一篇', '别人中间的一篇', '我最早的一篇'],
        reason: '必须按发布时间倒序（时间线顺序）',
      );

      // 其他作者的博客也出现在推荐里，且带作者信息
      expect(find.text(_otherName), findsOneWidget);
      expect(find.text(_meName), findsNWidgets(2));
    });

    testWidgets('关注：当前同样展示全站时间线（关注关系待接入）', (tester) async {
      await _pumpBlogTab(tester, groupedPosts: multiAuthorPosts());

      await _switchTab(tester, 1);
      final cards =
          tester.widgetList<BlogPostCard>(find.byType(BlogPostCard)).toList();
      expect(cards.length, 3);
      expect(cards.first.post.title, '我最新的一篇');
      expect(find.text(_otherName), findsOneWidget);
    });

    testWidgets('我的：只展示当前账号的博客（租户隔离）', (tester) async {
      await _pumpBlogTab(tester, groupedPosts: multiAuthorPosts());

      await _switchTab(tester, 2);
      final cards =
          tester.widgetList<BlogPostCard>(find.byType(BlogPostCard)).toList();
      expect(cards.length, 2, reason: '「我的」不应出现其他账号的博客');
      expect(cards.every((c) => c.post.authorPhone == _mePhone), isTrue);
      expect(find.text('别人中间的一篇'), findsNothing);
    });

    testWidgets('新发布的博客进入时间线第一条，同时进入我的', (tester) async {
      await _pumpBlogTab(tester, groupedPosts: {
        _key(_otherPhone): [
          _postJson(
            id: 'other',
            title: '别人的旧博客',
            content: '旧正文',
            createdAt: 1750000000000,
            authorPhone: _otherPhone,
            authorName: _otherName,
          ),
        ],
      });

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '我刚发布的博客');
      await tester.enterText(find.byType(TextField).last, '新正文');
      await tester.tap(find.text('发布'));
      await tester.pumpAndSettle();

      // 发布后停在「我的」
      var cards =
          tester.widgetList<BlogPostCard>(find.byType(BlogPostCard)).toList();
      expect(cards.length, 1);
      expect(cards.first.post.title, '我刚发布的博客');
      expect(cards.first.post.authorName, _meName, reason: '发布时应写入作者昵称');

      // 推荐流第一条即最新发布的这篇
      await _switchTab(tester, 0);
      cards =
          tester.widgetList<BlogPostCard>(find.byType(BlogPostCard)).toList();
      expect(cards.length, 2);
      expect(cards.first.post.title, '我刚发布的博客');
      expect(find.text(_meName), findsOneWidget);
      expect(find.text(_otherName), findsOneWidget);
    });
  });

  group('历史数据（无作者字段）兼容', () {
    testWidgets('作者昵称由存储键回填并在用户表补齐；查不到则显示「匿名用户」', (tester) async {
      await _pumpBlogTab(
        tester,
        users: [_userJson(phone: _otherPhone, name: _otherName)],
        groupedPosts: {
          // 历史数据：JSON 里没有 authorPhone / authorName
          _key(_otherPhone): [
            _postJson(
              id: 'legacy-known',
              title: '老数据-能查到作者',
              content: '正文',
              createdAt: 1750000200000,
            ),
          ],
          // 该手机号已不在用户表（例如账号记录被清）
          _key('13700137000'): [
            _postJson(
              id: 'legacy-unknown',
              title: '老数据-查不到作者',
              content: '正文',
              createdAt: 1750000100000,
            ),
          ],
        },
      );

      final cards =
          tester.widgetList<BlogPostCard>(find.byType(BlogPostCard)).toList();
      expect(cards.length, 2);
      expect(cards.first.post.authorName, _otherName,
          reason: '历史数据应由所属存储键回填手机号并在用户表补齐昵称');
      expect(find.text(_otherName), findsOneWidget);
      expect(cards.last.post.displayAuthor, BlogPost.anonymousAuthor,
          reason: '用户表查不到时兜底为匿名用户');
      expect(find.text(BlogPost.anonymousAuthor), findsOneWidget);
    });
  });

  group('无标题 / 有标题渲染', () {
    testWidgets('空标题：不显示「无标题」、无分隔线，直接显示正文', (tester) async {
      await _pumpBlogTab(tester, groupedPosts: {
        _key(_mePhone): [
          _postJson(
            id: '1',
            content: '这是一篇没有标题的博客正文',
            createdAt: 1750000000000,
            authorPhone: _mePhone,
            authorName: _meName,
          ),
        ],
      });

      expect(find.text('无标题'), findsNothing);
      expect(find.text('这是一篇没有标题的博客正文'), findsOneWidget);
      expect(find.byType(Divider), findsNothing);
    });

    testWidgets('历史 title=「无标题」按无标题处理', (tester) async {
      await _pumpBlogTab(tester, groupedPosts: {
        _key(_mePhone): [
          _postJson(
            id: '1',
            title: BlogPost.legacyUntitled,
            content: '历史版本写下的正文',
            createdAt: 1,
            authorPhone: _mePhone,
            authorName: _meName,
          ),
        ],
      });

      expect(find.text('无标题'), findsNothing);
      expect(find.text('历史版本写下的正文'), findsOneWidget);
    });

    testWidgets('有标题：标题与正文都显示，卡片内无分隔线', (tester) async {
      await _pumpBlogTab(tester, groupedPosts: {
        _key(_mePhone): [
          _postJson(
            id: '1',
            title: '我的第一篇职业洞察',
            content: '正文内容在这里',
            createdAt: 1,
            authorPhone: _mePhone,
            authorName: _meName,
          ),
        ],
      });

      expect(find.text('我的第一篇职业洞察'), findsOneWidget);
      expect(find.text('正文内容在这里'), findsOneWidget);
      expect(find.byType(Divider), findsNothing);
    });

    test('BlogPost.showTitle / displayAuthor 规则', () {
      BlogPost post(String title, {String author = ''}) => BlogPost(
            id: '1',
            title: title,
            content: 'c',
            createdAt: 0,
            authorName: author,
          );

      expect(post('我的标题').showTitle, isTrue);
      expect(post('').showTitle, isFalse);
      expect(post('   ').showTitle, isFalse);
      expect(post(BlogPost.legacyUntitled).showTitle, isFalse);
      expect(post('', author: '  ').displayAuthor, BlogPost.anonymousAuthor);
      expect(post('', author: '张三').displayAuthor, '张三');
    });
  });

  group('回归项', () {
    testWidgets('子 Tab 下方灰色分隔线已移除，橙色选中下划线保留', (tester) async {
      await _pumpBlogTab(tester);

      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabBar.dividerHeight, 0);
      expect(tabBar.dividerColor, Colors.transparent);
      expect(tabBar.indicatorColor, const Color(0xFFFD5C13));
      expect(tabBar.indicatorWeight, 3);
    });

    testWidgets('无内容时三个子 Tab 均为空态，且不出现「即将上线」', (tester) async {
      await _pumpBlogTab(tester);

      expect(find.text('还没有博客内容'), findsOneWidget); // 推荐
      expect(find.text('即将上线'), findsNothing);

      await _switchTab(tester, 1); // 关注
      expect(find.text('还没有博客内容'), findsOneWidget);

      await _switchTab(tester, 2); // 我的
      expect(find.text('还没有发布博客'), findsOneWidget);
      expect(find.text('即将上线'), findsNothing);
    });

    testWidgets('损坏记录被跳过，其余博客正常展示', (tester) async {
      await _pumpBlogTab(tester, groupedPosts: {
        _key(_mePhone): [
          '这不是合法 JSON',
          _postJson(
            id: '2',
            title: '正常的一篇',
            content: '正文',
            createdAt: 2,
            authorPhone: _mePhone,
            authorName: _meName,
          ),
        ],
      });

      expect(find.text('正常的一篇'), findsOneWidget);
      expect(find.byType(BlogPostCard), findsOneWidget);
    });
  });
}
