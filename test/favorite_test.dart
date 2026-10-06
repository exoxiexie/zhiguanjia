/// 收藏功能测试（职管家 · 个人职业版）
///
/// 覆盖点：
/// 1. 收藏数据层：新增 / 读回 / 计数 / 去重 / 取消收藏 / 按 id 删除；
/// 2. 时间线倒序、按账号隔离、损坏条目容错、JSON 往返；
/// 3. 气泡操作条：收藏写入、已收藏态切换、复制提示；
/// 4. 我的页「收藏」卡入口 + 收藏列表页空态与展示。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhiguanjia/features/chat/message_action_bar.dart';
import 'package:zhiguanjia/features/data/favorite_store.dart';
import 'package:zhiguanjia/features/data/favorites_page.dart';
import 'package:zhiguanjia/features/tabs/profile_tab.dart';

const String _authKey = 'zhiguanjia.personal.auth';
const String _mePhone = '13800138000';

String _authJson([String phone = _mePhone]) => jsonEncode({
      'token': 'mock-token',
      'phone': phone,
      'name': '张三',
    });

/// 指定账号的收藏存储键
String _key([String phone = _mePhone]) => 'favorites_$phone';

String _favJson(
  String id,
  String content, {
  int createdAt = 1,
  String source = '通用对话',
}) =>
    jsonEncode({
      'id': id,
      'content': content,
      'source': source,
      'createdAt': createdAt,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('收藏数据层', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({_authKey: _authJson()});
    });

    test('收藏后可读回、计数正确，按时间倒序', () async {
      await FavoriteStore.add(content: '第一条', source: '通用对话');
      await Future<void>.delayed(const Duration(milliseconds: 3));
      await FavoriteStore.add(content: '第二条', source: '学习');

      final list = await FavoriteStore.list();
      expect(list.length, 2);
      expect(list.first.content, '第二条', reason: '最近收藏的在最上面');
      expect(list.first.source, '学习');
      expect(await FavoriteStore.count(), 2);
    });

    test('同内容重复收藏不产生第二条', () async {
      expect(await FavoriteStore.add(content: '重复', source: '通用对话'), isTrue);
      expect(await FavoriteStore.add(content: '重复', source: '通用对话'), isFalse);
      expect(await FavoriteStore.count(), 1);
      expect(await FavoriteStore.contains('重复'), isTrue);
    });

    test('空内容不会入库', () async {
      expect(await FavoriteStore.add(content: '   ', source: '通用对话'), isFalse);
      expect(await FavoriteStore.count(), 0);
    });

    test('取消收藏按内容移除，删除按 id 移除', () async {
      await FavoriteStore.add(content: 'A', source: '通用对话');
      await FavoriteStore.add(content: 'B', source: '通用对话');
      await FavoriteStore.removeByContent('A');
      final list = await FavoriteStore.list();
      expect(list.map((e) => e.content).toList(), ['B']);

      await FavoriteStore.removeById(list.first.id);
      expect(await FavoriteStore.list(), isEmpty);
    });

    test('收藏按账号隔离', () async {
      SharedPreferences.setMockInitialValues({
        _authKey: _authJson('13900139000'),
        _key(): [_favJson('x', '别人的收藏')],
      });
      expect(await FavoriteStore.list(), isEmpty, reason: '不应读到其他账号的收藏');
    });

    test('损坏条目被跳过，不影响其他收藏', () async {
      SharedPreferences.setMockInitialValues({
        _authKey: _authJson(),
        _key(): ['这不是合法 JSON', _favJson('ok', '正常内容')],
      });
      final list = await FavoriteStore.list();
      expect(list.length, 1);
      expect(list.first.content, '正常内容');
    });

    test('JSON 往返不丢字段', () {
      const item = FavoriteItem(
        id: '1',
        content: '内容',
        source: '招聘',
        createdAt: 123,
      );
      final back = FavoriteItem.fromJson(jsonDecode(jsonEncode(item.toJson())));
      expect(back.id, '1');
      expect(back.content, '内容');
      expect(back.source, '招聘');
      expect(back.createdAt, 123);
    });
  });

  group('气泡操作条', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({_authKey: _authJson()});
      // 测试环境没有真实剪贴板实现，mock 掉 platform 通道让 Clipboard 调用成功
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('点「收藏」把内容写入收藏库并提示', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: MessageActionBar(content: 'AI 的一段回答', source: '通用对话'),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();

      expect(await FavoriteStore.contains('AI 的一段回答'), isTrue);
      expect(find.text('已收藏，可在「我的 · 收藏」查看'), findsOneWidget);
    });

    testWidgets('已收藏的内容再点变为取消收藏', (tester) async {
      SharedPreferences.setMockInitialValues({
        _authKey: _authJson(),
        _key(): [_favJson('1', '已回答')],
      });
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: MessageActionBar(content: '已回答', source: '通用对话'),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('已收藏'), findsOneWidget);
      await tester.tap(find.text('已收藏'));
      await tester.pumpAndSettle();

      expect(await FavoriteStore.contains('已回答'), isFalse);
    });

    testWidgets('点「复制」提示已复制', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: MessageActionBar(content: '待复制', source: '通用对话'),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('复制'));
      await tester.pumpAndSettle();
      expect(find.text('已复制'), findsOneWidget);
    });
  });

  group('我的页与收藏列表页', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({_authKey: _authJson()});
    });

    testWidgets('我的页出现「收藏」卡，点击进入收藏列表页', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: ProfileTab()));
      await tester.pumpAndSettle();

      expect(find.text('收藏'), findsOneWidget);
      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();
      expect(find.byType(FavoritesPage), findsOneWidget);
    });

    testWidgets('收藏列表页空态', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: FavoritesPage()));
      await tester.pumpAndSettle();
      expect(find.text('还没有收藏'), findsOneWidget);
    });

    testWidgets('收藏列表页展示已收藏内容与来源', (tester) async {
      SharedPreferences.setMockInitialValues({
        _authKey: _authJson(),
        _key(): [_favJson('1', '已收藏的回答', source: '学习')],
      });
      await tester.pumpWidget(const MaterialApp(home: FavoritesPage()));
      await tester.pumpAndSettle();

      expect(find.text('已收藏的回答'), findsOneWidget);
      expect(find.text('学习'), findsOneWidget);
    });
  });
}
