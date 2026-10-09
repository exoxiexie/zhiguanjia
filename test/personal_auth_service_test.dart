/// 账号服务单元测试（P1 · 服务端账号体系）
///
/// 用假 AuthApi 替换真实 HTTP 实现，覆盖最容易出错、也最影响可用性的路径：
/// 1. 注册成功：写入令牌 + 本地用户缓存，且本机不再保留明文密码
/// 2. 注册失败：如实透传服务端提示
/// 3. 本地格式校验：不满足时**不发起网络请求**
/// 4. 登录成功：写入令牌
/// 5. 老版本地账号自动迁移（服务端 bad_credentials + 本机同号同密码）
/// 6. 网络异常：不触发迁移，提示"检查网络"
/// 7. 退出登录：清空令牌与登录态
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhiguanjia/contracts/auth_api.dart';
import 'package:zhiguanjia/features/api/api_client.dart';
import 'package:zhiguanjia/features/personal/personal_auth_service.dart';
import 'package:zhiguanjia/features/personal/personal_model.dart';

/// 假接口：按用例可配置成功/失败
class FakeAuthApi implements AuthApi {
  String userPhone = '13800001111';
  String userName = '张三';

  bool registerOk = true;
  ApiError registerError =
      const ApiError(statusCode: 409, code: 'phone_taken', message: '该手机号已注册，请直接登录');

  bool loginOk = true;
  ApiError loginError =
      const ApiError(statusCode: 401, code: 'bad_credentials', message: '手机号或密码不正确');

  int registerCalls = 0;
  int loginCalls = 0;

  AuthSession _session(String phone, String name) => AuthSession(
        user: AuthUser(id: 'uid-1', phone: phone, name: name),
        accessToken: 'access-token-1',
        refreshToken: 'refresh-token-1',
        expiresIn: 7200,
      );

  @override
  Future<ApiResult<AuthSession>> register({
    required String phone,
    required String password,
    required String name,
  }) async {
    registerCalls++;
    if (!registerOk) return ApiResult.failure(registerError);
    userPhone = phone;
    userName = name;
    return ApiResult.success(_session(phone, name));
  }

  @override
  Future<ApiResult<AuthSession>> login({
    required String phone,
    required String password,
  }) async {
    loginCalls++;
    if (!loginOk) return ApiResult.failure(loginError);
    return ApiResult.success(_session(phone, userName));
  }

  @override
  Future<ApiResult<AuthSession>> refresh(String refreshToken) async =>
      ApiResult.success(_session(userPhone, userName));

  @override
  Future<ApiResult<bool>> logout({
    String refreshToken = '',
    bool allDevices = false,
  }) async =>
      const ApiResult.success(true);

  @override
  Future<ApiResult<AuthUser>> me() async =>
      ApiResult.success(AuthUser(id: 'uid-1', phone: userPhone, name: userName));
}

void main() {
  late FakeAuthApi api;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    api = FakeAuthApi();
    PersonalAuthService.apiForTest = api;
  });

  test('注册成功：写入令牌与本地缓存，且本机不保留明文密码', () async {
    final result = await PersonalAuthService.registerUser(
      phone: '13800001111',
      password: 'secret123456',
      name: '张三',
    );

    expect(result['ok'], isTrue, reason: '注册应成功');
    final user = result['user'] as PersonalUser;
    expect(user.phone, '13800001111');
    expect(user.name, '张三');

    // 令牌已落地（后续业务接口靠它鉴权）
    expect(await TokenStore.accessToken(), 'access-token-1');
    expect(await TokenStore.refreshToken(), 'refresh-token-1');

    // 本地用户表里不该再有明文密码
    final users = await PersonalAuthService.getUsers();
    expect(users.length, 1);
    expect(users.first.password, isEmpty, reason: '服务端认证后本机不再保存明文密码');
  });

  test('注册失败：透传服务端提示，不写入令牌', () async {
    api.registerOk = false;
    final result = await PersonalAuthService.registerUser(
      phone: '13800001111',
      password: 'secret123456',
      name: '张三',
    );

    expect(result['ok'], isFalse);
    expect(result['error'], '该手机号已注册，请直接登录');
    expect(await TokenStore.accessToken(), isEmpty);
  });

  test('本地格式校验不通过时：不发起网络请求', () async {
    final bad = await PersonalAuthService.registerUser(
      phone: '23800001111', // 手机号必须以 1 开头
      password: 'secret123456',
      name: '张三',
    );
    expect(bad['ok'], isFalse);
    expect(bad['error'], '请输入正确的11位手机号');

    final shortPw = await PersonalAuthService.registerUser(
      phone: '13800001111',
      password: '123',
      name: '张三',
    );
    expect(shortPw['error'], '密码至少6位');

    expect(api.registerCalls, 0, reason: '格式错误不应浪费一次网络请求');
  });

  test('登录成功：写入令牌', () async {
    final result = await PersonalAuthService.loginUser('13800001111', 'secret123456');
    expect(result['ok'], isTrue);
    expect(await TokenStore.accessToken(), 'access-token-1');
    expect(await TokenStore.refreshToken(), 'refresh-token-1');
  });

  test('老版本地账号自动迁移：服务端无此账号时用本机密码注册后登录', () async {
    // 造一个"老版本"遗留的本地账号（含明文密码）
    SharedPreferences.setMockInitialValues(<String, Object>{
      'zhiguanjia.personal.users':
          '[{"phone":"13800001111","password":"oldpass123","name":"老用户","createdAt":"2026-09-01T00:00:00.000"}]',
    });

    // 服务端登录失败（账号尚未迁移），但注册可用
    api.loginOk = false;
    api.registerOk = true;

    final result = await PersonalAuthService.loginUser('13800001111', 'oldpass123');

    expect(result['ok'], isTrue, reason: '应自动迁移后登录成功');
    expect(result['migrated'], isTrue);
    expect(api.registerCalls, 1);
    expect(await TokenStore.accessToken(), 'access-token-1');

    // 迁移后本地密码被清除
    final users = await PersonalAuthService.getUsers();
    expect(users.first.password, isEmpty);
  });

  test('登录失败且本机密码不符：不迁移，如实报错', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'zhiguanjia.personal.users':
          '[{"phone":"13800001111","password":"oldpass123","name":"老用户","createdAt":"2026-09-01T00:00:00.000"}]',
    });
    api.loginOk = false;

    final result = await PersonalAuthService.loginUser('13800001111', 'wrong-pass');

    expect(result['ok'], isFalse);
    expect(result['error'], '手机号或密码不正确');
    expect(api.registerCalls, 0, reason: '密码不符时不应尝试迁移');
  });

  test('网络异常：不触发迁移，提示检查网络', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'zhiguanjia.personal.users':
          '[{"phone":"13800001111","password":"oldpass123","name":"老用户","createdAt":"2026-09-01T00:00:00.000"}]',
    });
    api.loginOk = false;
    api.loginError = const ApiError(
        statusCode: 0, code: 'network', message: '无法连接服务器，请检查网络后重试');

    final result = await PersonalAuthService.loginUser('13800001111', 'oldpass123');

    expect(result['ok'], isFalse);
    expect(result['error'], contains('网络'));
    expect(api.registerCalls, 0);
  });

  test('退出登录：清空令牌与登录态', () async {
    await PersonalAuthService.registerUser(
      phone: '13800001111',
      password: 'secret123456',
      name: '张三',
    );
    final login = await PersonalAuthService.loginUser('13800001111', 'secret123456');
    await PersonalAuthService.setAuth(PersonalAuth.fromUser(login['user'] as PersonalUser));

    expect(await PersonalAuthService.getAuth(), isNotNull);
    expect(await TokenStore.accessToken(), isNotEmpty);

    await PersonalAuthService.clearAuth();

    expect(await PersonalAuthService.getAuth(), isNull);
    expect(await TokenStore.accessToken(), isEmpty);
    expect(await TokenStore.refreshToken(), isEmpty);
  });
}
