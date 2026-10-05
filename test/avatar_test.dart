/// 头像功能测试（demo 版：只覆盖 3 条关键路径）
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhiguanjia/features/personal/avatar_store.dart';
import 'package:zhiguanjia/features/personal/personal_auth_service.dart';
import 'package:zhiguanjia/features/tabs/profile_tab.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String root;
  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

const String _phone = '13800138000';

/// 1x1 透明 PNG（保证 Image 解码成功）
final List<int> _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('avatar_test');
    PathProviderPlatform.instance = _FakePathProvider(tempRoot.path);
  });

  tearDown(() async {
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  /// 造一张「系统临时目录里的原图」（模拟 image_picker 返回）
  File sourceImage() =>
      File(p.join(tempRoot.path, 'picked.png'))..writeAsBytesSync(_png);

  test('头像文件：保存到私有目录，可移除', () async {
    final saved = await AvatarStore.save(
        phone: _phone, sourcePath: sourceImage().path);

    expect(saved, contains(p.join('avatars', _phone)));
    expect(await File(saved).exists(), isTrue);

    await AvatarStore.remove(_phone);
    expect(await File(saved).exists(), isFalse);
  });

  test('updateAvatar 同步用户档案与登录态', () async {
    SharedPreferences.setMockInitialValues({
      'zhiguanjia.personal.auth':
          jsonEncode({'token': 't', 'phone': _phone, 'name': '张三'}),
      'zhiguanjia.personal.users': jsonEncode([
        {'phone': _phone, 'password': '123456', 'name': '张三', 'createdAt': ''}
      ]),
    });

    final result = await PersonalAuthService.updateAvatar(
        phone: _phone, avatarPath: '/tmp/a.png');

    expect(result['ok'], isTrue);
    expect((await PersonalAuthService.getAuth())!.avatarPath, '/tmp/a.png');
  });

  testWidgets('点击头像弹出更换面板', (tester) async {
    SharedPreferences.setMockInitialValues({
      'zhiguanjia.personal.auth':
          jsonEncode({'token': 't', 'phone': _phone, 'name': '张三'}),
      'zhiguanjia.personal.users': jsonEncode([
        {'phone': _phone, 'password': '123456', 'name': '张三', 'createdAt': ''}
      ]),
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ProfileTab(avatarPicker: (_) async => null)),
    ));
    await tester.pumpAndSettle();

    // 默认无头像：显示默认图标与可更换角标
    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    // 点头像 → 弹出更换面板
    await tester.tap(find.byIcon(Icons.photo_camera));
    await tester.pumpAndSettle();

    expect(find.text('更换头像'), findsOneWidget);
    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('从相册选择'), findsOneWidget);
  });
}
