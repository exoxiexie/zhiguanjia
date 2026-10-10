/// 账号被停用时的立即生效机制（真机问题：停用后仍能在本地继续使用）
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhiguanjia/features/api/api_client.dart';

Response<dynamic> res(int code, Object? data) =>
    Response<dynamic>(requestOptions: RequestOptions(path: '/x'), statusCode: code, data: data);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(ApiClient.resetDisabledFlag);
  tearDown(() {
    ApiClient.onAccountDisabled = null;
    ApiClient.resetDisabledFlag();
  });

  test('识别「账号被停用」响应（403 + user_disabled）', () {
    expect(
        ApiClient.isAccountDisabled(res(403, <String, dynamic>{
          'error': <String, dynamic>{'code': 'user_disabled', 'message': '该账号已被停用：测试'}
        })),
        isTrue);
  });

  test('其他 403 / 401 不算停用', () {
    expect(
        ApiClient.isAccountDisabled(res(403, <String, dynamic>{
          'error': <String, dynamic>{'code': 'forbidden', 'message': '无权限'}
        })),
        isFalse);
    expect(
        ApiClient.isAccountDisabled(res(401, <String, dynamic>{
          'error': <String, dynamic>{'code': 'user_disabled', 'message': 'x'}
        })),
        isFalse);
    expect(ApiClient.isAccountDisabled(res(200, null)), isFalse);
    expect(ApiClient.isAccountDisabled(res(500, 'not-json')), isFalse);
  });

  test('停用会触发回调，并带上服务端给的原因', () {
    String? got;
    ApiClient.onAccountDisabled = (r) => got = r;
    ApiClient.handleAccountDisabled(res(403, <String, dynamic>{
      'error': <String, dynamic>{'code': 'user_disabled', 'message': '该账号已被停用：发布违规内容'}
    }));
    expect(got, '该账号已被停用：发布违规内容');
  });

  test('并发请求只提示一次（不反复弹窗）', () {
    var count = 0;
    ApiClient.onAccountDisabled = (_) => count++;
    final r = res(403, <String, dynamic>{
      'error': <String, dynamic>{'code': 'user_disabled', 'message': 'x'}
    });
    ApiClient.handleAccountDisabled(r);
    ApiClient.handleAccountDisabled(r);
    ApiClient.handleAccountDisabled(r);
    expect(count, 1);
  });

  test('非停用响应不触发回调', () {
    var called = false;
    ApiClient.onAccountDisabled = (_) => called = true;
    ApiClient.handleAccountDisabled(res(200, <String, dynamic>{'ok': true}));
    expect(called, isFalse);
  });
}
