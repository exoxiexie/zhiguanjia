/// 基础信息存储（职管家 · 个人职业版）
///
/// **内容**：现在住址（省 / 市 / 区 + 详细地址）、工作状态、婚姻状况。
///
/// **存储**：SharedPreferences，按当前登录账号分键（`basic_info_{手机号}`），
/// 与全站「按手机号做本地数据隔离」一致；未登录落到 guest。
/// **空态**：四项全空时**不写键**（等同未填写），数据页卡片据此留白。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../personal/personal_auth_service.dart';

/// 工作状态
enum WorkStatus {
  employed('在职'),
  resigned('离职');

  final String label;

  const WorkStatus(this.label);

  /// 由存储里的枚举名还原；无法识别返回 null
  static WorkStatus? fromName(String? name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

/// 婚姻状况
enum MaritalStatus {
  married('已婚'),
  single('未婚'),
  other('其他');

  final String label;

  const MaritalStatus(this.label);

  static MaritalStatus? fromName(String? name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

/// 一份基础信息
class BasicInfo {
  /// 省 / 市 / 区（空串表示尚未选择）
  final String province;
  final String city;
  final String district;

  /// 详细地址（省市区之外的部分，如「科技园路 1 号 3 栋 502」）
  final String address;

  final WorkStatus? workStatus;
  final MaritalStatus? maritalStatus;

  const BasicInfo({
    this.province = '',
    this.city = '',
    this.district = '',
    this.address = '',
    this.workStatus,
    this.maritalStatus,
  });

  /// 省市区连成一行（未选时为空串）
  String get regionText =>
      [province, city, district].where((e) => e.isNotEmpty).join(' ');

  /// 完整住址：省市区 + 详细地址
  String get fullAddress =>
      [regionText, address].where((e) => e.isNotEmpty).join(' ');

  /// 四项都没填 = 未填写
  bool get isEmpty =>
      province.isEmpty &&
      address.isEmpty &&
      workStatus == null &&
      maritalStatus == null;

  bool get isNotEmpty => !isEmpty;

  BasicInfo copyWith({
    String? province,
    String? city,
    String? district,
    String? address,
    WorkStatus? workStatus,
    MaritalStatus? maritalStatus,
  }) =>
      BasicInfo(
        province: province ?? this.province,
        city: city ?? this.city,
        district: district ?? this.district,
        address: address ?? this.address,
        workStatus: workStatus ?? this.workStatus,
        maritalStatus: maritalStatus ?? this.maritalStatus,
      );

  Map<String, dynamic> toJson() => {
        'province': province,
        'city': city,
        'district': district,
        'address': address,
        'workStatus': workStatus?.name,
        'maritalStatus': maritalStatus?.name,
      };

  factory BasicInfo.fromJson(Map<String, dynamic> j) => BasicInfo(
        province: j['province']?.toString() ?? '',
        city: j['city']?.toString() ?? '',
        district: j['district']?.toString() ?? '',
        address: j['address']?.toString() ?? '',
        workStatus: WorkStatus.fromName(j['workStatus']?.toString()),
        maritalStatus: MaritalStatus.fromName(j['maritalStatus']?.toString()),
      );
}

class BasicInfoStore {
  /// 每个账号一个存储键（键后缀即账号手机号）
  static const String _keyPrefix = 'basic_info_';

  /// 未登录时的兜底键后缀
  static const String _guestPhone = 'guest';

  static Future<String> _keyFor() async {
    final auth = await PersonalAuthService.getAuth();
    final phone =
        (auth == null || auth.phone.isEmpty) ? _guestPhone : auth.phone;
    return '$_keyPrefix$phone';
  }

  /// 读取当前账号的基础信息；未填写或数据损坏时返回空对象
  static Future<BasicInfo> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(await _keyFor());
    if (raw == null || raw.isEmpty) return const BasicInfo();
    try {
      return BasicInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // 单条损坏按未填写处理，不让页面崩
      return const BasicInfo();
    }
  }

  /// 保存；全部字段为空时删除键（等于清空）
  static Future<void> save(BasicInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _keyFor();
    if (info.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, jsonEncode(info.toJson()));
  }

  /// 是否有任何一项已填（数据页卡片显示「已填写」）
  static Future<bool> hasAny() async => (await load()).isNotEmpty;
}
