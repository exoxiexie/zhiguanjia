/// 内容 API 的 HTTP 实现（P3）
library;

import 'dart:io';

import 'package:dio/dio.dart';

import '../../contracts/auth_api.dart';
import '../../contracts/content_api.dart';
import 'api_client.dart';

class HttpContentApi implements ContentApi {
  const HttpContentApi();

  @override
  Future<ApiResult<ContentBundle>> fetch({int feedLimit = 100}) async {
    try {
      final res = await ApiClient.sendAuthed('GET', '/content?feed_limit=$feedLimit');
      if (_isOk(res.statusCode)) {
        return ApiResult.success(ContentBundle.fromWire(_map(res.data)));
      }
      return ApiResult.failure(_errorOf(res));
    } on DioException catch (e) {
      return ApiResult.failure(_networkError(e));
    } catch (_) {
      return ApiResult.failure(_unknownNetworkError());
    }
  }

  @override
  Future<ApiResult<bool>> publishPost(PostDto post) => _void(
        () => ApiClient.sendAuthed('POST', '/content/posts',
            data: <String, dynamic>{
              'id': post.id,
              'title': post.title,
              'content': post.content,
              'images': post.images,
              'created_at': post.createdAt,
              'updated_at': DateTime.now().millisecondsSinceEpoch,
            }),
      );

  @override
  Future<ApiResult<bool>> deletePost(String id) =>
      _void(() => ApiClient.sendAuthed('DELETE', '/content/posts/$id'));

  @override
  Future<ApiResult<bool>> upsertFavorite(FavoriteDto item) => _void(
        () => ApiClient.sendAuthed('POST', '/content/favorites',
            data: <String, dynamic>{
              'id': item.id,
              'content': item.content,
              'source': item.source,
              'created_at': item.createdAt,
            }),
      );

  @override
  Future<ApiResult<bool>> deleteFavorite(String id) =>
      _void(() => ApiClient.sendAuthed('DELETE', '/content/favorites/$id'));

  @override
  Future<ApiResult<bool>> setFollow(String targetPhone, bool follow) => _void(
        () => follow
            ? ApiClient.sendAuthed('PUT', '/content/follows',
                data: <String, dynamic>{'target_phone': targetPhone})
            : ApiClient.sendAuthed('DELETE', '/content/follows/$targetPhone'),
      );

  @override
  Future<ApiResult<String>> uploadImage(String localFilePath) async {
    try {
      final token = await TokenStore.accessToken();
      if (token.isEmpty) {
        return const ApiResult.failure(
            ApiError(statusCode: 401, code: 'unauthorized', message: '未登录'));
      }
      final file = File(localFilePath);
      if (!await file.exists()) {
        return const ApiResult.failure(ApiError(
            statusCode: 0, code: 'file_missing', message: '图片文件不存在'));
      }

      final form = FormData.fromMap(<String, dynamic>{
        'file': await MultipartFile.fromFile(
          localFilePath,
          filename: localFilePath.split(Platform.pathSeparator).last,
        ),
      });
      final res = await ApiClient.dio.post<dynamic>(
        '/content/upload',
        data: form,
        options: Options(headers: <String, dynamic>{
          'Authorization': 'Bearer $token',
        }),
      );
      if (_isOk(res.statusCode)) {
        final url = _map(res.data)['url']?.toString() ?? '';
        if (url.isEmpty) {
          return const ApiResult.failure(ApiError(
              statusCode: 0, code: 'bad_response', message: '上传返回数据异常'));
        }
        return ApiResult.success(url);
      }
      return ApiResult.failure(_errorOf(res));
    } on DioException catch (e) {
      return ApiResult.failure(_networkError(e));
    } catch (_) {
      return ApiResult.failure(_unknownNetworkError());
    }
  }

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

  static bool _isOk(int? s) => s != null && s >= 200 && s < 300;

  static Map<String, dynamic> _map(dynamic d) =>
      d is Map ? d.cast<String, dynamic>() : <String, dynamic>{};

  static ApiError _errorOf(Response<dynamic> res) {
    final body = _map(res.data);
    final err = (body['error'] as Map?)?.cast<String, dynamic>();
    final status = res.statusCode ?? 0;
    final code = err?['code'] as String? ?? 'http_$status';
    final message = (err?['message'] as String?)?.trim();
    return ApiError(
      statusCode: status,
      code: code,
      message: (message == null || message.isEmpty) ? _fallback(status) : message,
    );
  }

  static String _fallback(int status) {
    if (status == 401) return '登录已过期，请重新登录';
    if (status == 403) return '只能操作自己发布的内容';
    if (status == 404) return '内容不存在';
    if (status == 413) return '图片过大，请换一张';
    if (status >= 500) return '服务暂时不可用，请稍后重试';
    return '操作失败（$status），请稍后重试';
  }

  static ApiError _networkError(DioException e) => ApiError(
        statusCode: 0,
        code: 'network',
        message: e.type == DioExceptionType.receiveTimeout ||
                e.type == DioExceptionType.connectionTimeout ||
                e.type == DioExceptionType.sendTimeout
            ? '网络超时，请稍后重试'
            : '网络连接失败，请检查网络后重试',
      );

  static ApiError _unknownNetworkError() => const ApiError(
      statusCode: 0, code: 'network', message: '网络连接失败，请检查网络后重试');
}
