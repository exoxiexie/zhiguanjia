/// P5 App 侧测试：启动配置（公告/强制更新）、设备上报、注销本地清理
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhiguanjia/contracts/app_api.dart';
import 'package:zhiguanjia/contracts/auth_api.dart';
import 'package:zhiguanjia/features/app/app_config_service.dart';
import 'package:zhiguanjia/features/app/local_data_cleaner.dart';
import 'package:zhiguanjia/features/api/api_client.dart';
import 'package:zhiguanjia/features/app/device_report_state.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String root;
  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

class FakeAppApi implements AppApi {
  int configCalls = 0;
  int deviceCalls = 0;
  bool online = true;
  Map<String, dynamic> lastDevice = <String, dynamic>{};
  AppRemoteConfig config = const AppRemoteConfig();

  ApiError get _offline =>
      const ApiError(statusCode: 0, code: 'network', message: '离线');

  @override
  Future<ApiResult<AppRemoteConfig>> fetchConfig() async {
    configCalls++;
    if (!online) return ApiResult.failure(_offline);
    return ApiResult.success(config);
  }

  @override
  Future<ApiResult<bool>> reportDevice({
    required String deviceId,
    required String platform,
    required String osVersion,
    required String appVersion,
    required int versionCode,
    String brand = '',
    String model = '',
    String channel = '',
  }) async {
    deviceCalls++;
    if (!online) return ApiResult.failure(_offline);
    lastDevice = <String, dynamic>{
      'device_id': deviceId,
      'platform': platform,
      'app_version': appVersion,
      'version_code': versionCode,
    };
    return const ApiResult.success(true);
  }

  @override
  Future<ApiResult<Map<String, dynamic>>> exportMyData() async =>
      const ApiResult.success(<String, dynamic>{'account': 'x'});

  @override
  Future<ApiResult<bool>> deleteAccount() async =>
      const ApiResult.success(true);
}

const String _phone = '13800138000';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late FakeAppApi api;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('appcfg_test');
    PathProviderPlatform.instance = _FakePathProvider(tempRoot.path);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    api = FakeAppApi();
    AppConfigService.apiForTest = api;
    // 本机版本 1.0.40 / versionCode 41
    PackageInfo.setMockInitialValues(
      appName: '职管家',
      packageName: 'com.zhiguanjia.zhiguanjia',
      version: '1.0.40',
      buildNumber: '41',
      buildSignature: '',
    );
  });

  tearDown(() async {
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  test('服务端未强制更新时不拦截', () async {
    api.config = const AppRemoteConfig(minVersionCode: 41);
    final r = await AppConfigService.check();
    expect(r.forceUpdate, isFalse);
    expect(r.currentVersionCode, 41);
  });

  test('最低版本高于本机 → 强制更新', () async {
    api.config = const AppRemoteConfig(
        minVersionCode: 42, minVersionName: '1.0.41', updateUrl: 'https://x/a.apk');
    final r = await AppConfigService.check();
    expect(r.forceUpdate, isTrue);
    expect(r.config?.minVersionName, '1.0.41');
  });

  test('未配置最低版本（0）永不强制', () async {
    api.config = const AppRemoteConfig();
    final r = await AppConfigService.check();
    expect(r.forceUpdate, isFalse);
  });

  test('公告：首次返回，标记已读后不再返回', () async {
    api.config = const AppRemoteConfig(
      announcementEnabled: true,
      announcementId: 'a1',
      announcementTitle: '维护通知',
      announcementBody: '今晚维护',
    );

    final first = await AppConfigService.check();
    expect(first.announcement, isNotNull);
    expect(first.announcement!.announcementTitle, '维护通知');

    await AppConfigService.markAnnouncementSeen('a1');

    final second = await AppConfigService.check();
    expect(second.announcement, isNull, reason: '同一条公告只弹一次');

    // 换一条公告 id → 应再次提示
    api.config = const AppRemoteConfig(
        announcementEnabled: true, announcementId: 'a2', announcementTitle: '新公告');
    final third = await AppConfigService.check();
    expect(third.announcement?.announcementTitle, '新公告');
  });

  test('公告未启用时不返回', () async {
    api.config = const AppRemoteConfig(
        announcementEnabled: false, announcementId: 'a1', announcementTitle: '标题');
    final r = await AppConfigService.check();
    expect(r.announcement, isNull);
  });

  test('网络失败：既不强制更新也不弹公告（不能让用户进不去）', () async {
    api.online = false;
    final r = await AppConfigService.check();
    expect(r.forceUpdate, isFalse);
    expect(r.announcement, isNull);
    expect(r.config, isNull);
  });

  test('设备上报：未登录不上报', () async {
    await AppConfigService.reportDevice();
    expect(api.deviceCalls, 0);
  });

  test('设备上报：已登录则上报版本与设备标识', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'zhiguanjia.api.accessToken': 'token-1',
      'zhiguanjia.api.deviceId': 'dev-abc',
    });

    await AppConfigService.reportDevice();

    expect(api.deviceCalls, 1);
    expect(api.lastDevice['device_id'], 'dev-abc');
    expect(api.lastDevice['app_version'], '1.0.40');
    expect(api.lastDevice['version_code'], 41);
  });

  test('设备上报失败不抛异常（不影响用户）', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'zhiguanjia.api.accessToken': 'token-1',
    });
    api.online = false;
    await AppConfigService.reportDevice(); // 不应抛出
    expect(api.deviceCalls, 1);
  });

  test('注销清理：该账号的本机数据被清除，其他账号不受影响', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'zhiguanjia.personal.users':
          '[{"phone":"$_phone","password":"","name":"我","createdAt":"2026-09-01T00:00:00.000"},'
              '{"phone":"13900000000","password":"","name":"别人","createdAt":"2026-09-01T00:00:00.000"}]',
      'blog_posts_$_phone': <String>['{"id":"p1"}'],
      'favorites_$_phone': <String>['{"id":"f1"}'],
      'follows_$_phone': <String>['13900000000'],
      'basic_info_$_phone': '{"province":"四川省"}',
      'blog_posts_13900000000': <String>['{"id":"other"}'],
    });

    await LocalDataCleaner.purgeAccount(_phone);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('blog_posts_$_phone'), isNull, reason: '该账号说说应清除');
    expect(prefs.getStringList('favorites_$_phone'), isNull, reason: '该账号收藏应清除');
    expect(prefs.getStringList('follows_$_phone'), isNull, reason: '该账号关注应清除');
    expect(prefs.getString('basic_info_$_phone'), isNull, reason: '该账号档案应清除');
    expect(prefs.getStringList('blog_posts_13900000000'), isNotNull,
        reason: '其他账号数据不得误删');
    expect(prefs.getString('zhiguanjia.personal.users'), isNot(contains(_phone)),
        reason: '本机用户表应移除该账号');
    expect(prefs.getString('zhiguanjia.personal.users'), contains('13900000000'),
        reason: '其他账号应保留');
  });

  test('注销清理：租户目录被删除', () async {
    final tenantDir = Directory('${tempRoot.path}/tenants/$_phone')
      ..createSync(recursive: true);
    File('${tenantDir.path}/database.db').writeAsStringSync('x');
    expect(tenantDir.existsSync(), isTrue);

    await LocalDataCleaner.purgeAccount(_phone);

    expect(tenantDir.existsSync(), isFalse, reason: '数据库/记忆/搜索沉淀目录应删除');
  });

  test('TokenStore：设备标识生成后保持稳定', () async {
    final id1 = await TokenStore.deviceId();
    final id2 = await TokenStore.deviceId();
    expect(id1, isNotEmpty);
    expect(id1, id2, reason: '同一设备标识必须稳定，否则装机量会被重复计数');
  });

  test('测试入口可见性：全局开关打开则所有人可见', () {
    const cfg = AppRemoteConfig(flags: <String, dynamic>{'test_panel': true});
    expect(AppConfigService.testPanelVisibleByFlags(cfg, '13800000000'), isTrue);
  });

  test('测试入口可见性：灰度名单内的手机号可见，名单外不可见', () {
    const cfg = AppRemoteConfig(flags: <String, dynamic>{
      'test_panel': false,
      'test_panel_phones': <String>['13608074995'],
    });
    expect(AppConfigService.testPanelVisibleByFlags(cfg, '13608074995'), isTrue,
        reason: '灰度账号应看到测试入口');
    expect(AppConfigService.testPanelVisibleByFlags(cfg, '13800000000'), isFalse,
        reason: '普通用户必须看不到（正式发布时靠它隐藏）');
  });

  test('测试入口可见性：没有配置 / 配置为空时一律隐藏', () {
    expect(AppConfigService.testPanelVisibleByFlags(null, '13608074995'), isFalse);
    expect(
        AppConfigService.testPanelVisibleByFlags(
            const AppRemoteConfig(), '13608074995'),
        isFalse);
  });

  // ── v1.0.53：上报结果不再静默（此前 catch 吞掉，坏了几个月无人知晓）──

  test('设备上报失败：记录原因（灰度面板可见），而不是完全静默', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'zhiguanjia.api.accessToken': 'token-1',
      'zhiguanjia.api.deviceId': 'dev-abc',
    });
    api.online = false;

    await AppConfigService.reportDevice();

    final snap = await DeviceReportState.load();
    expect(snap, isNotNull);
    expect(snap!.ok, isFalse);
    expect(snap.message, contains('离线'));
    expect(snap.at.isNotEmpty, isTrue);
  });

  test('设备上报成功：记录成功与设备信息', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'zhiguanjia.api.accessToken': 'token-1',
      'zhiguanjia.api.deviceId': 'dev-abc',
    });

    await AppConfigService.reportDevice();

    final snap = await DeviceReportState.load();
    expect(snap!.ok, isTrue);
    expect(snap.message, '上报成功');
    expect(snap.info['设备标识'], 'dev-abc');
    expect(snap.info.keys, contains('系统'));
  });

  test('未登录：不调接口，但记录原因（面板可解释为何没有装机数据）', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await AppConfigService.reportDevice();

    expect(api.deviceCalls, 0);
    final snap = await DeviceReportState.load();
    expect(snap!.ok, isFalse);
    expect(snap.message, contains('未登录'));
  });

  test('DeviceReportState 读写往返（唯一事实来源）', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await DeviceReportState.save(
        ok: true, message: 'ok', info: <String, String>{'平台': 'android'});
    final snap = await DeviceReportState.load();
    expect(snap!.ok, isTrue);
    expect(snap.info['平台'], 'android');

    await DeviceReportState.clear();
    expect(await DeviceReportState.load(), isNull);
  });
}
