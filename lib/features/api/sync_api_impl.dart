/// 对话同步 API 的 HTTP 实现（P4）
library;

import 'package:dio/dio.dart';

import '../../contracts/auth_api.dart';
import '../../contracts/sync_api.dart';
import 'api_client.dart';

class HttpSyncApi implements SyncApi {
  const HttpSyncApi();

  @override
  Future<ApiResult<SyncServerStatus>> status() async {
    try {
      final res = await ApiClient.sendAuthed('GET', '/sync/status');
      if (_isOk(res.statusCode)) {
        return ApiResult.success(SyncServerStatus.fromWire(_map(res.data)));
      }
      return ApiResult.failure(_errorOf(res));
    } on DioException catch (e) {
      return ApiResult.failure(_networkError(e));
    } catch (_) {
      return ApiResult.failure(_unknownNetworkError());
    }
  }

  @override
  Future<ApiResult<SyncChanges>> pull({required int since, int limit = 500}) async {
    try {
      final res = await ApiClient.sendAuthed('GET', '/sync?since=$since&limit=$limit');
      if (_isOk(res.statusCode)) {
        return ApiResult.success(SyncChanges.fromWire(_map(res.data)));
      }
      return ApiResult.failure(_errorOf(res));
    } on DioException catch (e) {
      return ApiResult.failure(_networkError(e));
    } catch (_) {
      return ApiResult.failure(_unknownNetworkError());
    }
  }

  @override
  Future<ApiResult<int>> push(SyncPushPayload payload) async {
    try {
      final res = await ApiClient.sendAuthed('POST', '/sync/push', data: payload.toWire());
      if (_isOk(res.statusCode)) {
        return ApiResult.success((_map(res.data)['seq'] as num?)?.toInt() ?? 0);
      }
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
          : (status == 401 ? '登录已过期，请重新登录' : '同步失败（$status）'),
    );
  }

  static ApiError _networkError(DioException e) => ApiError(
        statusCode: 0,
        code: 'network',
        message: e.type == DioExceptionType.receiveTimeout ||
                e.type == DioExceptionType.connectionTimeout
            ? '网络超时，稍后会自动重试'
            : '网络连接失败，稍后会自动重试',
      );

  static ApiError _unknownNetworkError() => const ApiError(
      statusCode: 0, code: 'network', message: '网络连接失败，稍后会自动重试');
}
