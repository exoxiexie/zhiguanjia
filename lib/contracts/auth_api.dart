/// 账号 API 契约（P1 · 商业版账号体系）
///
/// 铁律：UI 与服务调用方只依赖契约，不直接依赖 dio / HTTP 细节；
/// 具体实现见 `features/api/auth_api_impl.dart`。
///
/// 路径经 Nginx 反代：App 访问 `{apiBaseUrl}/auth/login` →
/// 服务端实际路由 `/auth/login`（Nginx 已剥离 `/api/` 前缀）。
library;

/// 服务端用户资料（身份证等敏感字段一律脱敏返回）
class AuthUser {
  /// 用户唯一 ID（服务端 UUID）
  final String id;

  /// 手机号（账号标识，同时作为本机数据隔离的租户 ID）
  final String phone;

  /// 姓名
  final String name;

  /// 头像地址（P1 仍用本机路径，P3 上云）
  final String avatarPath;

  final String gender;
  final String birthday;
  final String province;

  /// 已认证的脱敏身份证号（未认证为空）
  final String idCardMasked;

  /// 是否已实名认证
  final bool isVerified;

  /// 实名认证时间（ISO8601，空=未认证）
  final String verifiedAt;

  /// 注册时间（ISO8601）
  final String createdAt;

  const AuthUser({
    required this.id,
    required this.phone,
    required this.name,
    this.avatarPath = '',
    this.gender = '',
    this.birthday = '',
    this.province = '',
    this.idCardMasked = '',
    this.isVerified = false,
    this.verifiedAt = '',
    this.createdAt = '',
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        name: json['name'] as String? ?? '',
        avatarPath: json['avatar_path'] as String? ?? '',
        gender: json['gender'] as String? ?? '',
        birthday: json['birthday'] as String? ?? '',
        province: json['province'] as String? ?? '',
        idCardMasked: json['id_card_masked'] as String? ?? '',
        isVerified: json['is_verified'] as bool? ?? false,
        verifiedAt: json['verified_at'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
      );
}

/// 一次成功认证的会话
class AuthSession {
  final AuthUser user;

  /// 访问令牌（短时效，用于业务接口）
  final String accessToken;

  /// 刷新令牌（长时效，仅用于换取新令牌）
  final String refreshToken;

  /// 访问令牌有效期（秒）
  final int expiresIn;

  const AuthSession({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    this.expiresIn = 0,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        user: AuthUser.fromJson(
            (json['user'] as Map?)?.cast<String, dynamic>() ?? const {}),
        accessToken: json['access_token'] as String? ?? '',
        refreshToken: json['refresh_token'] as String? ?? '',
        expiresIn: (json['expires_in'] as num?)?.toInt() ?? 0,
      );
}

/// 统一错误：服务端业务错误与网络异常共用一种结构
class ApiError {
  /// HTTP 状态码；0 表示网络层失败（未拿到响应）
  final int statusCode;

  /// 机器可读错误码（如 bad_credentials / phone_taken / token_invalid）
  final String code;

  /// 可直接展示给用户的中文提示
  final String message;

  const ApiError({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  /// 是否为网络问题（用于提示"检查网络"而非"密码错误"）
  bool get isNetwork => statusCode == 0;

  @override
  String toString() => 'ApiError($statusCode/$code): $message';
}

/// 接口调用结果：成功带数据，失败带错误
class ApiResult<T> {
  final T? data;
  final ApiError? error;

  const ApiResult.success(this.data) : error = null;
  const ApiResult.failure(this.error) : data = null;

  bool get ok => error == null;
}

/// 账号接口
abstract class AuthApi {
  /// 注册（手机号 + 密码 + 姓名）
  Future<ApiResult<AuthSession>> register({
    required String phone,
    required String password,
    required String name,
  });

  /// 登录
  Future<ApiResult<AuthSession>> login({
    required String phone,
    required String password,
  });

  /// 刷新令牌（服务端会一次性轮换，旧令牌立即失效）
  Future<ApiResult<AuthSession>> refresh(String refreshToken);

  /// 退出登录（吊销本设备或全部设备的刷新令牌）
  Future<ApiResult<bool>> logout({
    String refreshToken = '',
    bool allDevices = false,
  });

  /// 当前登录用户资料
  Future<ApiResult<AuthUser>> me();
}
