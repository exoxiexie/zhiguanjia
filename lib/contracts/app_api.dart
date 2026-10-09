/// App 级接口契约（P5 商业能力）
///
/// 覆盖：设备上报（装机量/版本分布）、服务端下发配置（公告/强制更新）、
/// 个人数据导出与账号注销（合规要求）。
///
/// 集中在一个契约里，是因为它们都是「App 与运营后台之间」的接口，
/// 与账号/档案/内容/对话这些业务域无关。
library;

import 'auth_api.dart';

/// 服务端下发的配置
class AppRemoteConfig {
  /// 公告（enabled=false 表示无公告）
  final bool announcementEnabled;
  final String announcementId;
  final String announcementTitle;
  final String announcementBody;

  /// 强制更新：当前 versionCode 低于 [minVersionCode] 必须升级（0=不强制）
  final int minVersionCode;
  final String minVersionName;
  final String updateUrl;
  final String updateNote;

  /// 功能开关（服务端可随时下发，无需发版）
  final Map<String, dynamic> flags;

  const AppRemoteConfig({
    this.announcementEnabled = false,
    this.announcementId = '',
    this.announcementTitle = '',
    this.announcementBody = '',
    this.minVersionCode = 0,
    this.minVersionName = '',
    this.updateUrl = '',
    this.updateNote = '',
    this.flags = const {},
  });

  factory AppRemoteConfig.fromWire(Map<String, dynamic> json) {
    final a = ((json['announcement'] as Map?) ?? const {}).cast<String, dynamic>();
    final m = ((json['min_version'] as Map?) ?? const {}).cast<String, dynamic>();
    return AppRemoteConfig(
      announcementEnabled: a['enabled'] == true,
      announcementId: a['id']?.toString() ?? '',
      announcementTitle: a['title']?.toString() ?? '',
      announcementBody: a['body']?.toString() ?? '',
      minVersionCode: (m['version_code'] as num?)?.toInt() ?? 0,
      minVersionName: m['version_name']?.toString() ?? '',
      updateUrl: m['url']?.toString() ?? '',
      updateNote: m['note']?.toString() ?? '',
      flags: ((json['flags'] as Map?) ?? const {}).cast<String, dynamic>(),
    );
  }
}

/// App 级接口
abstract class AppApi {
  /// 上报设备信息（幂等：同设备重复上报只更新最后活跃时间）
  Future<ApiResult<bool>> reportDevice({
    required String deviceId,
    required String platform,
    required String osVersion,
    required String appVersion,
    required int versionCode,
    String brand = '',
    String model = '',
    String channel = '',
  });

  /// 读取服务端配置（**无需登录**：公告与强制更新要在登录前生效）
  Future<ApiResult<AppRemoteConfig>> fetchConfig();

  /// 导出该账号的全部服务端数据
  Future<ApiResult<Map<String, dynamic>>> exportMyData();

  /// 注销账号（需显式确认，服务端会级联删除全部数据）
  Future<ApiResult<bool>> deleteAccount();
}
