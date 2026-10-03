/// 个人主体数据模型（职管家 · 面向个人用户）
///
/// 对应智懂你的 Enterprise/EnterpriseAuth/EnterpriseUser：
/// - 企业版以「统一社会信用代码」为主体标识，多管理员（owner/admin）
/// - 个人版以「手机号」为账号唯一标识（数据隔离租户ID），
///   注册后再做实名认证（身份证号 + 姓名），单账号无管理员体系。
library;

/// 个人注册用户记录
class PersonalUser {
  /// 手机号（账号主键，同时作为数据隔离租户ID，注册即有且永不变）
  final String phone;

  /// 密码（MVP 本地明文存储，与智懂你当前实现保持一致）
  final String password;

  /// 姓名（注册时填写）
  final String name;

  /// 身份证号（实名认证后回填，空字符串=未认证）
  final String idCard;

  /// 性别（实名认证后由身份证号解析：男/女）
  final String gender;

  /// 出生日期（实名认证后解析，yyyy-MM-dd）
  final String birthday;

  /// 籍贯省份（实名认证后解析）
  final String province;

  /// 实名认证时间（ISO8601，空=未认证）
  final String verifiedAt;

  /// 注册时间
  final String createdAt;

  const PersonalUser({
    required this.phone,
    required this.password,
    required this.name,
    this.idCard = '',
    this.gender = '',
    this.birthday = '',
    this.province = '',
    this.verifiedAt = '',
    required this.createdAt,
  });

  bool get isVerified => idCard.isNotEmpty;

  /// 脱敏身份证号（未认证返回空）
  String get maskedIdCard {
    if (idCard.isEmpty) return '';
    if (idCard.length != 18) return idCard;
    return '${idCard.substring(0, 6)}********${idCard.substring(14)}';
  }

  factory PersonalUser.fromJson(Map<String, dynamic> json) => PersonalUser(
        phone: json['phone'] as String? ?? '',
        password: json['password'] as String? ?? '',
        name: json['name'] as String? ?? '',
        idCard: json['idCard'] as String? ?? '',
        gender: json['gender'] as String? ?? '',
        birthday: json['birthday'] as String? ?? '',
        province: json['province'] as String? ?? '',
        verifiedAt: json['verifiedAt'] as String? ?? '',
        createdAt: json['createdAt'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'phone': phone,
        'password': password,
        'name': name,
        'idCard': idCard,
        'gender': gender,
        'birthday': birthday,
        'province': province,
        'verifiedAt': verifiedAt,
        'createdAt': createdAt,
      };

  PersonalUser copyWith({
    String? password,
    String? name,
    String? idCard,
    String? gender,
    String? birthday,
    String? province,
    String? verifiedAt,
  }) {
    return PersonalUser(
      phone: phone,
      password: password ?? this.password,
      name: name ?? this.name,
      idCard: idCard ?? this.idCard,
      gender: gender ?? this.gender,
      birthday: birthday ?? this.birthday,
      province: province ?? this.province,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      createdAt: createdAt,
    );
  }
}

/// 个人登录态
class PersonalAuth {
  final String token;
  final String phone;
  final String name;
  final String idCard;
  final String gender;
  final String birthday;
  final String province;
  final String verifiedAt;

  const PersonalAuth({
    required this.token,
    required this.phone,
    required this.name,
    this.idCard = '',
    this.gender = '',
    this.birthday = '',
    this.province = '',
    this.verifiedAt = '',
  });

  bool get isVerified => idCard.isNotEmpty;

  String get maskedIdCard {
    if (idCard.isEmpty) return '';
    if (idCard.length != 18) return idCard;
    return '${idCard.substring(0, 6)}********${idCard.substring(14)}';
  }

  factory PersonalAuth.fromUser(PersonalUser u) => PersonalAuth(
        token: 'mock-token',
        phone: u.phone,
        name: u.name,
        idCard: u.idCard,
        gender: u.gender,
        birthday: u.birthday,
        province: u.province,
        verifiedAt: u.verifiedAt,
      );

  factory PersonalAuth.fromJson(Map<String, dynamic> json) => PersonalAuth(
        token: json['token'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        name: json['name'] as String? ?? '',
        idCard: json['idCard'] as String? ?? '',
        gender: json['gender'] as String? ?? '',
        birthday: json['birthday'] as String? ?? '',
        province: json['province'] as String? ?? '',
        verifiedAt: json['verifiedAt'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'token': token,
        'phone': phone,
        'name': name,
        'idCard': idCard,
        'gender': gender,
        'birthday': birthday,
        'province': province,
        'verifiedAt': verifiedAt,
      };
}
