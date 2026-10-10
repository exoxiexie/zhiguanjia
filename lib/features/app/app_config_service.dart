/// 启动检查服务（P5-b）：服务端下发配置 + 设备上报
///
/// 设计要点：
/// - **配置接口无需登录**：公告与强制更新必须在登录页也能生效
///   （某个版本有严重缺陷时要能拦在登录之前）。
/// - 任何失败都静默：配置拿不到就按"无公告、不强制"处理，
///   绝不能让网络问题把用户挡在 App 之外。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_report_state.dart';

import '../../contracts/app_api.dart';
import '../api/api_client.dart';
import '../api/app_api_impl.dart';

/// 启动检查结果
class StartupCheck {
  /// 是否必须升级才能继续使用
  final bool forceUpdate;

  /// 需要弹给用户看的公告（已按"看过就不再弹"过滤）
  final AppRemoteConfig? announcement;

  /// 服务端配置（拿不到为 null）
  final AppRemoteConfig? config;

  /// 当前安装版本
  final String currentVersionName;
  final int currentVersionCode;

  const StartupCheck({
    this.forceUpdate = false,
    this.announcement,
    this.config,
    this.currentVersionName = '',
    this.currentVersionCode = 0,
  });
}

class AppConfigService {
  static AppApi _api = const HttpAppApi();

  /// 最近一次拿到的服务端配置（进程内缓存）
  ///
  /// 「我的」页需要**同步**判断测试入口是否显示，因此启动检查的结果必须留一份。
  /// 拿不到时保持 null，界面按"隐藏"处理（正式用户默认看不到测试入口）。
  static AppRemoteConfig? cachedConfig;

  /// 测试注入口
  @visibleForTesting
  static set apiForTest(AppApi value) => _api = value;

  /// 已读公告 id（同一条公告只弹一次）
  @visibleForTesting
  static const String seenAnnouncementKey = 'zhiguanjia.announcement.seen';

  static const Duration _timeout = Duration(seconds: 8);

  /// 启动检查：读配置 → 判断强制更新 / 公告
  static Future<StartupCheck> check() async {
    String versionName = '';
    int versionCode = 0;
    try {
      final info = await PackageInfo.fromPlatform();
      versionName = info.version;
      versionCode = int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      // 取不到版本号：退化为"不强制更新"
    }

    try {
      final res = await _api.fetchConfig().timeout(_timeout);
      if (!res.ok || res.data == null) {
        return StartupCheck(
            currentVersionName: versionName, currentVersionCode: versionCode);
      }
      final cfg = res.data!;
      final forceUpdate = cfg.minVersionCode > 0 &&
          versionCode > 0 &&
          versionCode < cfg.minVersionCode;

      AppRemoteConfig? announcement;
      if (cfg.announcementEnabled && cfg.announcementId.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final seen = prefs.getString(seenAnnouncementKey);
        if (seen != cfg.announcementId) announcement = cfg;
      }

      cachedConfig = cfg;
      return StartupCheck(
        forceUpdate: forceUpdate,
        announcement: announcement,
        config: cfg,
        currentVersionName: versionName,
        currentVersionCode: versionCode,
      );
    } catch (_) {
      return StartupCheck(
          currentVersionName: versionName, currentVersionCode: versionCode);
    }
  }

  /// 「测试」入口是否显示
  ///
  /// 规则（服务端可随时调整，无需发版）：
  /// 1. `flags.test_panel == true` → 全量可见（开发/内测期）
  /// 2. `flags.test_panel_phones` 含当前手机号 → 仅这些账号可见（灰度）
  /// 3. 其余情况隐藏；debug 构建默认可见，便于开发调试
  ///
  /// 这样正式发布时**无需删代码**，只要服务端关掉开关即可对普通用户隐藏。
  static bool testPanelVisible(String phone) =>
      testPanelVisibleByFlags(cachedConfig, phone) || kDebugMode;

  /// 纯函数版本（便于单测，不受 debug/release 影响）
  ///
  /// `kDebugMode` 让开发构建始终能看到测试入口；正式包只看服务端配置。
  @visibleForTesting
  static bool testPanelVisibleByFlags(AppRemoteConfig? config, String phone) {
    final flags = config?.flags ?? const <String, dynamic>{};
    if (flags['test_panel'] == true) return true;
    final list = flags['test_panel_phones'];
    if (list is List && phone.isNotEmpty) {
      return list.map((e) => e.toString()).contains(phone);
    }
    return false;
  }

  /// 标记公告已读（弹过之后调用）
  static Future<void> markAnnouncementSeen(String id) async {
    if (id.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(seenAnnouncementKey, id);
    } catch (_) {
      // 静默
    }
  }

  /// 上报设备（装机量/版本分布）。登录后调用。
  ///
  /// 幂等：服务端按 (账号, 设备标识) 唯一，同一台设备只算一次装机。
  ///
  /// **不再完全静默**：结果写入 [DeviceReportState]，灰度「测试面板」可查看。
  /// 起因：此前把连续 422 全部吞掉，坏了几个月无人知晓（唯一信号是后台"设备数恒为 0"）。
  /// 对用户依旧零打扰 —— 只是把"静默失败"变成"可见状态"。
  static Future<void> reportDevice() async {
    try {
      if ((await TokenStore.accessToken()).isEmpty) {
        // 未登录：不调接口，但记录状态（面板可解释"为什么没有装机数据"）
        await DeviceReportState.save(ok: false, message: '未登录，未上报');
        return;
      }
      final info = await PackageInfo.fromPlatform();
      final deviceId = await TokenStore.deviceId();
      final platform = Platform.isAndroid
          ? 'android'
          : (Platform.isIOS ? 'ios' : Platform.operatingSystem);
      final osVersion = Platform.operatingSystemVersion;
      final snapshot = <String, String>{
        '设备标识': deviceId,
        '平台': platform,
        '系统': osVersion,
        'App 版本': '${info.version}（${info.buildNumber}）',
      };
      final res = await _api.reportDevice(
        deviceId: deviceId,
        platform: platform,
        osVersion: osVersion,
        appVersion: info.version,
        versionCode: int.tryParse(info.buildNumber) ?? 0,
      );
      await DeviceReportState.save(
        ok: res.ok,
        message: res.ok ? '上报成功' : (res.error?.message ?? '上报失败（无详情）'),
        info: snapshot,
      );
    } catch (e) {
      // 不打扰用户，但记录原因（否则又是"静默失败"）
      await DeviceReportState.save(ok: false, message: '异常：$e');
    }
  }
}
