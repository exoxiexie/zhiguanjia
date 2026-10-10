/// 设备上报的**可见状态**（供灰度「测试面板」展示）
///
/// 为什么需要它：`reportDevice()` 以前是 `catch (_) {}` **完全静默** ——
/// 服务端连续 30 次返回 422，坏了几个月，唯一信号是后台"设备数恒为 0"
/// （真实发生过的 S-6）。这里把每次上报的结果落到本地，面板可直接查看，
/// 让"静默失败"变成"可见状态"，同时**仍然不打扰普通用户**。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 一次上报的结果快照
class DeviceReportSnapshot {
  /// 本地时间（东八区），便于人直接看
  final String at;
  final bool ok;
  final String message;

  /// 设备标识 / 平台 / 系统 / App 版本（上报内容快照）
  final Map<String, String> info;

  const DeviceReportSnapshot({
    required this.at,
    required this.ok,
    required this.message,
    this.info = const <String, String>{},
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'at': at,
        'ok': ok,
        'message': message,
        'info': info,
      };

  factory DeviceReportSnapshot.fromJson(Map<String, dynamic> json) {
    final rawInfo = json['info'];
    return DeviceReportSnapshot(
      at: json['at']?.toString() ?? '',
      ok: json['ok'] == true,
      message: json['message']?.toString() ?? '',
      info: rawInfo is Map
          ? rawInfo.map((k, v) => MapEntry(k.toString(), v.toString()))
          : const <String, String>{},
    );
  }
}

/// 上报结果的本地读写（唯一事实来源：`zhiguanjia.deviceReport`）
class DeviceReportState {
  static const String storageKey = 'zhiguanjia.deviceReport';

  static Future<void> save({
    required bool ok,
    required String message,
    Map<String, String> info = const <String, String>{},
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().toUtc().add(const Duration(hours: 8)); // 展示用东八区
      final snap = DeviceReportSnapshot(
        at: '${now.year}-${_p(now.month)}-${_p(now.day)} '
            '${_p(now.hour)}:${_p(now.minute)}:${_p(now.second)}',
        ok: ok,
        message: message,
        info: info,
      );
      await prefs.setString(storageKey, jsonEncode(snap.toJson()));
    } catch (_) {
      // 记录失败绝不能影响主流程
    }
  }

  static Future<DeviceReportSnapshot?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) return null;
      return DeviceReportSnapshot.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
    } catch (_) {}
  }

  static String _p(int n) => n.toString().padLeft(2, '0');
}
