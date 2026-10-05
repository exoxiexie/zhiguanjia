/// ProfileTab 刷新钩子测试（对应修复：实名认证后「我的」页不刷新）
///
/// 背景：「我的」页常驻在 ShellPage 的 IndexedStack 中，initState 只执行一次。
/// 用户在「数据」页完成实名认证后本页不会重建，必须由主框架触发 [ProfileTabState.refresh]，
/// 否则会出现「已认证但我的页仍显示未认证」。
///
/// 本测试验证：refresh() 能重新读取登录态并刷新界面。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhiguanjia/features/personal/personal_auth_service.dart';
import 'package:zhiguanjia/features/tabs/profile_tab.dart';

/// 构造一份登录态 JSON（未认证 / 已认证两态）
String authJson({required bool verified}) => jsonEncode({
      'token': 'mock-token',
      'phone': '13800138000',
      'name': '张三',
      'idCard': verified ? '110101199003077758' : '',
      'gender': verified ? '男' : '',
      'birthday': verified ? '1990-03-07' : '',
      'province': verified ? '北京市' : '',
      'verifiedAt': verified ? '2026-10-05T10:00:00.000' : '',
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const authKey = 'zhiguanjia.personal.auth';

  testWidgets('未认证 → 实名认证后调用 refresh()，页面切换为已认证', (tester) async {
    SharedPreferences.setMockInitialValues(
        {authKey: authJson(verified: false)});

    final key = GlobalKey<ProfileTabState>();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ProfileTab(key: key))),
    );
    await tester.pumpAndSettle();

    // 初始：未认证
    expect(find.text('未认证'), findsOneWidget, reason: '未认证账号进入本页应显示「未认证」');
    expect(find.text('已实名'), findsNothing);

    // 模拟：用户在「数据」页完成实名认证，登录态被更新
    SharedPreferences.setMockInitialValues({authKey: authJson(verified: true)});

    // 触发主框架切换 Tab 时调用的刷新钩子
    key.currentState!.refresh();
    await tester.pumpAndSettle();

    expect(find.text('已实名'), findsOneWidget,
        reason: 'refresh() 后应重新读取登录态并显示「已实名」');
    expect(find.text('未认证'), findsNothing);
  });

  testWidgets('refresh() 能重新读取登录态（PersonalAuthService 为唯一数据源）', (tester) async {
    SharedPreferences.setMockInitialValues(
        {authKey: authJson(verified: false)});

    final key = GlobalKey<ProfileTabState>();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ProfileTab(key: key))),
    );
    await tester.pumpAndSettle();

    expect(await PersonalAuthService.getAuth(), isNotNull);
    expect(key.currentState, isNotNull);

    // 清空登录态后刷新：不应抛异常（退出登录路径的健壮性）
    SharedPreferences.setMockInitialValues({});
    key.currentState!.refresh();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
