/// 职业档案 API 的 HTTP 实现（配合 [ApiClient]）
///
/// 与 `HttpAuthApi` 同一套约定：4xx 不抛异常、按统一错误结构翻译成
/// 用户可读中文与机器可读错误码，网络异常统一转成 `code=network`。
library;

import 'package:dio/dio.dart';

import '../../contracts/auth_api.dart';
import '../../contracts/profile_api.dart';
import 'api_client.dart';

class HttpProfileApi implements ProfileApi {
  const HttpProfileApi();

  @override
  Future<ApiResult<ProfileBundle>> fetch() async {
    try {
      final res = await ApiClient.sendAuthed('GET', '/profile');
      if (_isOk(res.statusCode)) {
        return ApiResult.success(
            ProfileBundle.fromWire(_map(res.data)));
      }
      return ApiResult.failure(_errorOf(res));
    } on DioException catch (e) {
      return ApiResult.failure(_networkError(e));
    } catch (_) {
      return ApiResult.failure(_unknownNetworkError());
    }
  }

  @override
  Future<ApiResult<bool>> saveBasic(Map<String, dynamic> basic) =>
      _void(() => ApiClient.sendAuthed('PUT', '/profile/basic', data: basic));

  @override
  Future<ApiResult<bool>> saveSelfEvaluation(String content) => _void(
        () => ApiClient.sendAuthed('PUT', '/profile/evaluation',
            data: <String, dynamic>{'content': content}),
      );

  @override
  Future<ApiResult<bool>> upsertExperience(ExperienceDto dto) => _void(
        () => ApiClient.sendAuthed('POST', '/profile/experiences',
            data: <String, dynamic>{
              'id': dto.id,
              'kind_id': dto.kindId,
              'values': dto.values,
              'created_at': dto.createdAt,
              'updated_at': dto.updatedAt,
            }),
      );

  @override
  Future<ApiResult<bool>> deleteExperience(String id) =>
      _void(() => ApiClient.sendAuthed('DELETE', '/profile/experiences/$id'));

  @override
  Future<ApiResult<bool>> saveIdentity({
    required String idCard,
    required String realName,
    String gender = '',
    String birthday = '',
    String province = '',
  }) =>
      _void(
        () => ApiClient.sendAuthed('PUT', '/profile/identity',
            data: <String, dynamic>{
              'id_card': idCard,
              'real_name': realName,
              'gender': gender,
              'birthday': birthday,
              'province': province,
            }),
      );

  // ────────────────────────── 内部工具 ──────────────────────────

  Future<ApiResult<bool>> _void(
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

  static bool _isOk(int? status) =>
      status != null && status >= 200 && status < 300;

  static Map<String, dynamic> _map(dynamic data) =>
      data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};

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
      case 'unauthorized':
      case 'token_invalid':
        return '登录已过期，请重新登录';
      case 'id_card_taken':
        return '该身份证号已绑定其他账号';
      case 'experience_id_conflict':
        return '该记录已属于其他账号';
      default:
        break;
    }
    if (status == 401) return '登录已过期，请重新登录';
    if (status == 404) return '记录不存在';
    if (status >= 500) return '服务暂时不可用，请稍后重试';
    return '保存失败（$status），请稍后重试';
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
