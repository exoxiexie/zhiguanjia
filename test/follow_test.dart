/// 关注关系与用户主页测试
///
/// 覆盖点：
/// 1. 关注关系按当前账号隔离存储；关注 / 取关幂等；不允许关注自己；
/// 2. 关注流只含**已关注作者**的说说，并按发布时间倒序（由近及远）；
/// 3. 点击卡片**作者信息栏**进入作者主页；点击正文区**不**跳转；
/// 4. 用户主页可关注 / 取关；自己的主页不显示关注按钮。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhiguanjia/features/blog/blog_post_card.dart';
import 'package:zhiguanjia/features/blog/follow_store.dart';
import 'package:zhiguanjia/features/blog/user_profile_page.dart';
import 'package:zhiguanjia/features/tabs/blog_tab.dart';

const String _authKey = 'zhiguanjia.personal.auth';
const String _usersKey = 'zhiguanjia.personal.users';

const String _mePhone = '13800138000';
const String _meName = '张三';

const String _otherPhone = '13900139000';
const String _otherName = '李四';

const String _thirdPhone = '13700137000';
const String _thirdName = '王五';

String _authJson({String phone = _mePhone, String name = _meName}) =>
    jsonEncode({'token': 'mock-token', 'phone': phone, 'name': name});

Map<String, dynamic> _userJson({required String phone, required String name}) =>
    {
      'phone': phone,
      'password': '123456',
      'name': name,
      'createdAt': '2026-01-01T00:00:00.000',
      'avatarPath': '',
    };

String _postJson({
  required String id,
  required String content,
  required int createdAt,
  required String authorPhone,
  required String authorName,
}) =>
    jsonEncode({
      'id': id,
      'title': '',
      'content': content,
      'createdAt': createdAt,
      'authorPhone': authorPhone,
      'authorName': authorName,
    });

/// 说说存储键（后缀即作者手机号）
String _postKey(String phone) => 'blog_posts_$phone';

/// 关注关系存储键（后缀即当前登录账号手机号）
String _followKey(String phone) => 'follows_$phone';

/// 三个作者各一条说说：王五最新、我中间、李四最早
Map<String, List<String>> _multiAuthorPosts() => {
      _postKey(_mePhone): [
        _postJson(
          id: 'm1',
          content: '我自己中间的一条',
          createdAt: 2000,
          authorPhone: _mePhone,
          authorName: _meName,
        ),
      ],
      _postKey(_otherPhone): [
        _postJson(
          id: 'o1',
          content: '李四最早的一条',
          createdAt: 1000,
          authorPhone: _otherPhone,
          authorName: _otherName,
        ),
      ],
      _postKey(_thirdPhone): [
        _postJson(
          id: 't1',
          content: '王五最新的一条',
          createdAt: 3000,
          authorPhone: _thirdPhone,
          authorName: _thirdName,
        ),
      ],
    };

/// 渲染说说列表页
Future<void> _pumpBlogTab(
  WidgetTester tester, {
  Map<String, List<String>> groupedPosts = const {},
  List<Map<String, dynamic>> users = const [],
  List<String> following = const [],
}) async {
  SharedPreferences.setMockInitialValues({
    _authKey: _authJson(),
    if (users.isNotEmpty) _usersKey: jsonEncode(users),
    if (following.isNotEmpty) _followKey(_mePhone): following,
    ...groupedPosts,
  });
  await tester.pumpWidget(const MaterialApp(home: BlogTab()));
  await tester.pumpAndSettle();
}

/// 渲染用户主页
Future<void> _pumpProfile(
  WidgetTester tester,
  String phone, {
  String name = '',
  List<Map<String, dynamic>> users = const [],
  Map<String, List<String>> groupedPosts = const {},
  List<String> following = const [],
}) async {
  SharedPreferences.setMockInitialValues({
    _authKey: _authJson(),
    if (users.isNotEmpty) _usersKey: jsonEncode(users),
    if (following.isNotEmpty) _followKey(_mePhone): following,
    ...groupedPosts,
  });
  await tester.pumpWidget(
    MaterialApp(home: UserProfilePage(phone: phone, name: name)),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('关注关系存储', () {
    test('关注 / 取关幂等，且不允许关注自己', () async {
      SharedPreferences.setMockInitialValues({_authKey: _authJson()});

      expect(await FollowStore.isFollowing(_otherPhone), isFalse);

      // 关注
      expect(await FollowStore.toggleFollow(_otherPhone), isTrue);
      expect(await FollowStore.loadFollowing(), {_otherPhone});

      // 重复关注不产生重复项
      await FollowStore.setFollow(_otherPhone, true);
      expect((await FollowStore.loadFollowing()).length, 1);

      // 取关
      expect(await FollowStore.toggleFollow(_otherPhone), isFalse);
      expect(await FollowStore.loadFollowing(), isEmpty);

      // 不能关注自己
      await FollowStore.setFollow(_mePhone, true);
      expect(await FollowStore.isFollowing(_mePhone), isFalse);
    });

    test('关注关系按账号隔离：换账号看不到上一个账号的关注', () async {
      SharedPreferences.setMockInitialValues({_authKey: _authJson()});
      await FollowStore.setFollow(_otherPhone, true);
      expect(await FollowStore.loadFollowing(), {_otherPhone});

      // 切换到另一个账号
      SharedPreferences.setMockInitialValues({
        _authKey: _authJson(phone: _thirdPhone, name: _thirdName),
      });
      expect(await FollowStore.loadFollowing(), isEmpty);
    });

    test('关注流只含已关注作者的说说，按时间倒序（由近及远）', () async {
      SharedPreferences.setMockInitialValues({
        _authKey: _authJson(),
        // 已关注：李四、王五（不含自己）
        _followKey(_mePhone): [_thirdPhone, _otherPhone],
        ..._multiAuthorPosts(),
      });

      final feed = await FollowStore.loadFollowingFeed();
      expect(
        feed.map((p) => p.content).toList(),
        ['王五最新的一条', '李四最早的一条'],
        reason: '必须是已关注作者的内容，且按发布时间由近及远',
      );
      expect(feed.any((p) => p.authorPhone == _mePhone), isFalse,
          reason: '自己未在关注列表内，不应出现');
    });
  });

  group('作者信息栏点击进入用户主页', () {
    testWidgets('点击作者栏 → 打开该作者主页，主页展示其说说', (tester) async {
      await _pumpBlogTab(tester, groupedPosts: _multiAuthorPosts());

      await tester.tap(find.text(_otherName));
      await tester.pumpAndSettle();

      expect(find.byType(UserProfilePage), findsOneWidget);
      expect(find.text('李四最早的一条'), findsOneWidget);
    });

    testWidgets('点击正文区 → 不跳转（正文不在作者栏点击范围内）', (tester) async {
      await _pumpBlogTab(tester, groupedPosts: _multiAuthorPosts());

      await tester.tap(find.text('李四最早的一条'));
      await tester.pumpAndSettle();

      expect(find.byType(UserProfilePage), findsNothing);
      expect(find.byType(BlogTab), findsOneWidget);
    });
  });

  group('用户主页关注', () {
    testWidgets('点「关注」变「已关注」，再点取关', (tester) async {
      await _pumpProfile(
        tester,
        _otherPhone,
        name: _otherName,
        users: [_userJson(phone: _otherPhone, name: _otherName)],
      );

      // 未关注：橙色实心「关注」
      expect(find.widgetWithText(FilledButton, '关注'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '关注'));
      await tester.pumpAndSettle();

      // 已关注：灰描边「已关注」
      expect(find.widgetWithText(OutlinedButton, '已关注'), findsOneWidget);
      expect(await FollowStore.isFollowing(_otherPhone), isTrue);

      // 再点取关
      await tester.tap(find.widgetWithText(OutlinedButton, '已关注'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, '关注'), findsOneWidget);
      expect(await FollowStore.isFollowing(_otherPhone), isFalse);
    });

    testWidgets('自己的主页不显示关注按钮', (tester) async {
      await _pumpProfile(
        tester,
        _mePhone,
        name: _meName,
        users: [_userJson(phone: _mePhone, name: _meName)],
      );

      expect(find.widgetWithText(FilledButton, '关注'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '已关注'), findsNothing);
    });

    testWidgets('主页关注后返回列表，「关注」子 Tab 出现该作者的说说', (tester) async {
      await _pumpBlogTab(tester, groupedPosts: _multiAuthorPosts());

      // 进入李四主页并关注
      await tester.tap(find.text(_otherName));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '关注'));
      await tester.pumpAndSettle();

      // 返回列表
      await tester.pageBack();
      await tester.pumpAndSettle();

      // 切到「关注」子 Tab
      await tester.tap(find.byType(Tab).at(1));
      await tester.pumpAndSettle();

      final cards =
          tester.widgetList<BlogPostCard>(find.byType(BlogPostCard)).toList();
      expect(cards.length, 1);
      expect(cards.first.post.authorPhone, _otherPhone);
      expect(find.text('李四最早的一条'), findsOneWidget);
    });
  });
}
