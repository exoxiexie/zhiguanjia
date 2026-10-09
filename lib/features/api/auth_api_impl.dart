/// 账号 API 的 HTTP 实现（配合 [ApiClient]）
///
/// 所有错误在这里被翻译成用户可读的中文提示与机器可读错误码，
/// 上层（PersonalAuthService / UI）不需要了解 dio 与 HTTP 细节。
library;

import 'package:dio/dio.dart';

import '../../contracts/auth_api.dart';
import 'api_client.dart';

class HttpAuthApi implements AuthApi {
  const HttpAuthApi();

  @override
  Future<ApiResult<AuthSession>> register({
    required String phone,
    required String password,
    required String name,
  }) async {
    final deviceId = await TokenStore.deviceId();
    return _asSession(() => ApiClient.send('POST', '/auth/register', data: {
          'phone': phone,
          'password': password,
          'name': name,
          'device_id': deviceId,
          'platform': 'android',
        }));
  }

  @override
  Future<ApiResult<AuthSession>> login({
    required String phone,
    required String password,
  }) async {
    final deviceId = await TokenStore.deviceId();
    return _asSession(() => ApiClient.send('POST', '/auth/login', data: {
          'phone': phone,
          'password': password,
          'device_id': deviceId,
          'platform': 'android',
        }));
  }

  @override
  Future<ApiResult<AuthSession>> refresh(String refreshToken) => _asSession(
        () => ApiClient.send('POST', '/auth/refresh',
            data: <String, dynamic>{'refresh_token': refreshToken}),
      );

  @override
  Future<ApiResult<bool>> logout({
    String refreshToken = '',
    bool allDevices = false,
  }) =>
      _asBool(() => ApiClient.sendAuthed('POST', '/auth/logout',
          data: <String, dynamic>{
            'refresh_token': refreshToken,
            'all_devices': allDevices,
          }));

  @override
  Future<ApiResult<AuthUser>> me() => _asUser(() => ApiClient.sendAuthed('GET', '/me'));

  // ────────────────────────── 内部工具 ──────────────────────────

  Future<ApiResult<AuthSession>> _asSession(
    Future<Response<dynamic>> Function() run,
  ) async {
    try {
      final res = await run();
      if (_isOk(res.statusCode)) {
        return ApiResult.success(AuthSession.fromJson(_map(res.data)));
      }
      return ApiResult.failure(_errorOf(res));
    } on DioException catch (e) {
      return ApiResult.failure(_networkError(e));
    } catch (_) {
      return ApiResult.failure(_unknownNetworkError());
    }
  }

  Future<ApiResult<AuthUser>> _asUser(
    Future<Response<dynamic>> Function() run,
  ) async {
    try {
      final res = await run();
      if (_isOk(res.statusCode)) {
        return ApiResult.success(AuthUser.fromJson(_map(res.data)));
      }
      return ApiResult.failure(_errorOf(res));
    } on DioException catch (e) {
      return ApiResult.failure(_networkError(e));
    } catch (_) {
      return ApiResult.failure(_unknownNetworkError());
    }
  }

  Future<ApiResult<bool>> _asBool(
    Future<Response<dynamic>> Function() run,
  ) async {
    try {
      final res = await run();
      if (_isOk(res.statusCode)) return const ApiResult.success(true);
      return ApiResult.failure(_errorOf(res));
    } on DioException catch (e) {
      return ApiResult.failure(_networkError(e));
    } catch (_) {
      return ApiResult.failure(_unknownNetworkError());
    }
  }

  static bool _isOk(int? status) => status != null && status >= 200 && status < 300;

  static Map<String, dynamic> _map(dynamic data) =>
      data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};

  /// 解析服务端统一错误结构 {"error": {"code", "message"}}
  static ApiError _errorOf(Response<dynamic> res) {
    final body = _map(res.data);
    final err = (body['error'] as Map?)?.cast<String, dynamic>();
    final status = res.statusCode ?? 0;
    final code = err?['code'] as String? ?? 'http_$status';
    final message = (err?['message'] as String?)?.trim();
    return ApiError(
      statusCode: status,
      code: code,
      message: (message == null || message.isEmpty)
          ? _fallbackMessage(status, code)
          : message,
    );
  }

  static String _fallbackMessage(int status, String code) {
    switch (code) {
      case 'bad_credentials':
        return '手机号或密码不正确';
      case 'phone_taken':
        return '该手机号已注册，请直接登录';
      case 'token_invalid':
      case 'unauthorized':
        return '登录已过期，请重新登录';
      case 'too_many_requests':
        return '操作过于频繁，请稍后再试';
      default:
        break;
    }
    if (status == 401) return '登录已过期，请重新登录';
    if (status == 429) return '操作过于频繁，请稍后再试';
    if (status >= 500) return '服务暂时不可用，请稍后重试';
    return '请求失败（$status），请稍后重试';
  }

  static ApiError _networkError(DioException e) {
    final String message;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
        message = '连接超时，请检查网络后重试';
        break;
      case DioExceptionType.receiveTimeout:
        message = '服务器响应超时，请稍后重试';
        break;
      case DioExceptionType.connectionError:
        message = '无法连接服务器，请检查网络后重试';
        break;
      case DioExceptionType.badCertificate:
        message = '安全连接失败，请稍后重试';
        break;
      case DioExceptionType.cancel:
        message = '请求已取消';
        break;
      default:
        message = '网络连接失败，请检查网络后重试';
    }
    return ApiError(statusCode: 0, code: 'network', message: message);
  }

  static ApiError _unknownNetworkError() => const ApiError(
        statusCode: 0,
        code: 'network',
        message: '网络连接失败，请检查网络后重试',
      );
}
