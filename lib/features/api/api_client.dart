/// API 客户端（P1 · 服务端接入层）
///
/// 职责：
/// - 提供全局 dio 实例（超时、统一 JSON、不因 4xx 抛异常，便于按状态码分支）
/// - [TokenStore]：访问令牌 / 刷新令牌 / 设备标识的本机持久化
/// - 鉴权请求的 401 静默刷新重试（业务代码无需关心令牌过期）
///
/// 设计取舍：不使用 dio 拦截器做令牌刷新，而是提供 [ApiClient.sendAuthed]，
/// 因为拦截器里的重试容易产生递归与"刷新风暴"，显式调用更可预测。
library;

import 'dart:math';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../contracts/api_config.dart';
import '../../contracts/auth_api.dart';

/// 令牌与设备标识的本机存储
class TokenStore {
  static const String _kAccess = 'zhiguanjia.api.accessToken';
  static const String _kRefresh = 'zhiguanjia.api.refreshToken';
  static const String _kExpiresAt = 'zhiguanjia.api.expiresAt';
  static const String _kUserId = 'zhiguanjia.api.userId';
  static const String _kDeviceId = 'zhiguanjia.api.deviceId';

  /// 写入会话令牌
  ///
  /// [expiresIn] 为访问令牌有效期（秒），提前 60 秒视为过期，避免边界失败。
  static Future<void> save({
    required String accessToken,
    required String refreshToken,
    int expiresIn = 0,
    String userId = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccess, accessToken);
    if (refreshToken.isNotEmpty) {
      await prefs.setString(_kRefresh, refreshToken);
    }
    final expiresAt = expiresIn > 0
        ? DateTime.now()
            .add(Duration(seconds: expiresIn - 60))
            .millisecondsSinceEpoch
        : 0;
    await prefs.setInt(_kExpiresAt, expiresAt);
    if (userId.isNotEmpty) {
      await prefs.setString(_kUserId, userId);
    }
  }

  static Future<String> accessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kAccess) ?? '';
  }

  static Future<String> refreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kRefresh) ?? '';
  }

  static Future<String> userId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kUserId) ?? '';
  }

  /// 访问令牌是否已过期（未设置有效期时视为未过期，交由服务端判断）
  static Future<bool> isAccessExpired() async {
    final prefs = await SharedPreferences.getInstance();
    final expiresAt = prefs.getInt(_kExpiresAt) ?? 0;
    if (expiresAt <= 0) return false;
    return DateTime.now().millisecondsSinceEpoch >= expiresAt;
  }

  /// 是否持有有效会话（用于启动时判断能否静默续期）
  static Future<bool> hasSession() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_kRefresh) ?? '').isNotEmpty;
  }

  /// 清空令牌（退出登录时调用；设备标识保留）
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccess);
    await prefs.remove(_kRefresh);
    await prefs.remove(_kExpiresAt);
    await prefs.remove(_kUserId);
  }

  /// 设备标识（首次调用生成并持久化，用于服务端按设备管理登录态）
  static Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_kDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final rand = Random.secure();
    final buf = StringBuffer('and-');
    for (var i = 0; i < 16; i++) {
      buf.write(rand.nextInt(16).toRadixString(16));
    }
    final id = buf.toString();
    await prefs.setString(_kDeviceId, id);
    return id;
  }
}

/// 全局 dio 实例与鉴权请求封装
class ApiClient {
  ApiClient._();

  static final Dio dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 25),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
      // 4xx 交给上层按业务码处理，不让 dio 抛异常，避免错误信息被吞掉
      validateStatus: (status) => status != null && status < 600,
    ),
  );

  /// 匿名请求（注册 / 登录 / 刷新）
  static Future<Response<dynamic>> send(
    String method,
    String path, {
    Object? data,
    String? accessToken,
  }) {
    return dio.request<dynamic>(
      path,
      data: data,
      options: Options(
        method: method,
        headers: accessToken == null
            ? null
            : <String, dynamic>{'Authorization': 'Bearer $accessToken'},
      ),
    );
  }

  /// 服务端判定「账号被停用」时的统一回调（由 main.dart 注册）
  ///
  /// 为什么必须要有：App 是**离线优先**的 —— 发对话/发说说先写本地库、同步在后，
  /// 业务请求失败会被当成"网络问题"静默忽略。结果就是账号被后台停用后，
  /// 用户仍能在本地继续使用（真机实测问题）。这里让停用**立即生效**。
  static void Function(String reason)? onAccountDisabled;

  /// 本次启动是否已触发过（并发请求不重复弹窗）
  static bool _disabledNotified = false;

  /// 响应是否为「账号被停用」（403 + code=user_disabled）
  static bool isAccountDisabled(Response<dynamic> res) {
    if (res.statusCode != 403) return false;
    final body = res.data;
    if (body is! Map) return false;
    final err = body['error'];
    return err is Map && err['code'] == 'user_disabled';
  }

  /// 从响应里取停用原因（服务端会把原因写在 message 里）
  static String disabledReason(Response<dynamic> res) {
    final body = res.data;
    if (body is Map) {
      final err = body['error'];
      if (err is Map && err['message'] is String) return err['message'] as String;
    }
    return '该账号已被停用';
  }

  /// 处理「账号被停用」（[sendAuthed] 调用；单独抽出来便于测试）
  static void handleAccountDisabled(Response<dynamic> res) {
    if (!isAccountDisabled(res) || _disabledNotified) return;
    _disabledNotified = true;
    onAccountDisabled?.call(disabledReason(res));
  }

  /// 仅测试使用：重置"已提示"标记
  static void resetDisabledFlag() => _disabledNotified = false;

  /// 鉴权请求：令牌失效（401）时静默刷新一次并重试
  static Future<Response<dynamic>> sendAuthed(
    String method,
    String path, {
    Object? data,
  }) async {
    var token = await TokenStore.accessToken();
    var res = await send(method, path, data: data, accessToken: token);
    if (res.statusCode == 401 && await refreshSession()) {
      token = await TokenStore.accessToken();
      res = await send(method, path, data: data, accessToken: token);
    }
    handleAccountDisabled(res);  // 停用立即生效（登出 + 告知原因）
    return res;
  }

  /// 静默续期：用刷新令牌换新令牌（成功返回 true）
  ///
  /// 供启动时预刷新与 [sendAuthed] 的 401 重试共用；
  /// 任何异常都吞掉并返回 false——续期失败不应让 App 崩溃或卡住。
  static Future<bool> refreshSession() async {
    final refreshToken = await TokenStore.refreshToken();
    if (refreshToken.isEmpty) return false;
    try {
      final res = await send('POST', '/auth/refresh',
          data: <String, dynamic>{'refresh_token': refreshToken});
      final body = res.data;
      if (res.statusCode == 200 && body is Map) {
        final session =
            AuthSession.fromJson(body.cast<String, dynamic>());
        if (session.accessToken.isNotEmpty) {
          await TokenStore.save(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresIn: session.expiresIn,
            userId: session.user.id,
          );
          return true;
        }
      }
    } catch (_) {
      // 网络异常/解析失败：静默失败即可
    }
    return false;
  }

  /// 启动时尽力续期：令牌已过期或持有刷新令牌时尝试一次，不阻塞界面
  static Future<void> ensureFreshSession() async {
    if (await isSessionUsable()) return;
    await refreshSession();
  }

  /// 会话是否仍可直接使用（无令牌=否；未过期=是）
  static Future<bool> isSessionUsable() async {
    if (!await TokenStore.hasSession()) return false;
    return !await TokenStore.isAccessExpired();
  }
}

/// 网络层异常（供上层转换为用户可读提示）
class ApiNetworkException implements Exception {
  final String message;
  const ApiNetworkException(this.message);

  @override
  String toString() => message;
}
