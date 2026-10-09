/// App 级接口的 HTTP 实现（P5）
library;

import 'package:dio/dio.dart';

import '../../contracts/app_api.dart';
import '../../contracts/auth_api.dart';
import 'api_client.dart';

class HttpAppApi implements AppApi {
  const HttpAppApi();

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
  }) =>
      _bool(() => ApiClient.sendAuthed('POST', '/device/report',
          data: <String, dynamic>{
            'device_id': deviceId,
            'platform': platform,
            'os_version': osVersion,
            'app_version': appVersion,
            'version_code': versionCode,
            'brand': brand,
            'model': model,
            'channel': channel,
          }));

  @override
  Future<ApiResult<AppRemoteConfig>> fetchConfig() async {
    try {
      // 公开接口：不需要令牌
      final res = await ApiClient.send('GET', '/app/config');
      if (_isOk(res.statusCode)) {
        return ApiResult.success(AppRemoteConfig.fromWire(_map(res.data)));
      }
      return ApiResult.failure(_errorOf(res));
    } on DioException catch (e) {
      return ApiResult.failure(_networkError(e));
    } catch (_) {
      return ApiResult.failure(_unknownNetworkError());
    }
  }

  @override
  Future<ApiResult<Map<String, dynamic>>> exportMyData() async {
    try {
      final res = await ApiClient.sendAuthed('GET', '/me/export');
      if (_isOk(res.statusCode)) {
        return ApiResult.success(_map(res.data));
      }
      return ApiResult.failure(_errorOf(res));
    } on DioException catch (e) {
      return ApiResult.failure(_networkError(e));
    } catch (_) {
      return ApiResult.failure(_unknownNetworkError());
    }
  }

  @override
  Future<ApiResult<bool>> deleteAccount() =>
      // 服务端要求显式二次确认，防止误调用导致不可逆的数据丢失
      _bool(() => ApiClient.sendAuthed('DELETE', '/me?confirm=DELETE'));

  // ────────────────────────── 内部工具 ──────────────────────────

  Future<ApiResult<bool>> _bool(
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

  static bool _isOk(int? s) => s != null && s >= 200 && s < 300;

  static Map<String, dynamic> _map(dynamic d) =>
      d is Map ? d.cast<String, dynamic>() : <String, dynamic>{};

  static ApiError _errorOf(Response<dynamic> res) {
    final body = _map(res.data);
    final err = (body['error'] as Map?)?.cast<String, dynamic>();
    final status = res.statusCode ?? 0;
    return ApiError(
      statusCode: status,
      code: err?['code'] as String? ?? 'http_$status',
      message: (err?['message'] as String?)?.trim().isNotEmpty == true
          ? (err!['message'] as String).trim()
          : (status == 401 ? '登录已过期，请重新登录' : '操作失败（$status）'),
    );
  }

  static ApiError _networkError(DioException e) => ApiError(
        statusCode: 0,
        code: 'network',
        message: e.type == DioExceptionType.receiveTimeout ||
                e.type == DioExceptionType.connectionTimeout
            ? '网络超时，请稍后重试'
            : '网络连接失败，请检查网络后重试',
      );

  static ApiError _unknownNetworkError() => const ApiError(
      statusCode: 0, code: 'network', message: '网络连接失败，请检查网络后重试');
}
