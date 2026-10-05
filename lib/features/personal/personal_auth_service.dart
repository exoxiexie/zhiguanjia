/// 个人认证服务（职管家）
///
/// - SharedPreferences 存储用户列表（模拟数据库）
/// - 注册：手机号 + 密码 + 姓名（单账号，无管理员体系）
/// - 登录：手机号 + 密码
/// - 实名认证：注册登录后补充身份证号 + 真实姓名（本地校验）
/// - 数据隔离租户ID统一用手机号（注册即有、永不变，认证前后一致）
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'id_card_util.dart';
import 'personal_model.dart';

class PersonalAuthService {
  static const String _usersKey = 'zhiguanjia.personal.users';
  static const String _authKey = 'zhiguanjia.personal.auth';

  /// 获取所有注册用户
  static Future<List<PersonalUser>> getUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_usersKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => PersonalUser.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveUsers(List<PersonalUser> users) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _usersKey, jsonEncode(users.map((u) => u.toJson()).toList()));
  }

  /// 注册个人账号（手机号 + 密码 + 姓名）
  static Future<Map<String, dynamic>> registerUser({
    required String phone,
    required String password,
    required String name,
  }) async {
    if (phone.length != 11 || !phone.startsWith('1')) {
      return {'ok': false, 'error': '请输入正确的11位手机号'};
    }
    if (name.trim().isEmpty) {
      return {'ok': false, 'error': '请输入姓名'};
    }
    if (password.length < 6) {
      return {'ok': false, 'error': '密码至少6位'};
    }
    final users = await getUsers();
    if (users.any((u) => u.phone == phone)) {
      return {'ok': false, 'error': '该手机号已注册'};
    }
    final user = PersonalUser(
      phone: phone,
      password: password,
      name: name.trim(),
      createdAt: DateTime.now().toIso8601String(),
    );
    users.add(user);
    await _saveUsers(users);
    return {'ok': true, 'user': user};
  }

  /// 登录校验
  static Future<Map<String, dynamic>> loginUser(
      String phone, String password) async {
    final users = await getUsers();
    final found = users.where((u) => u.phone == phone).toList();
    if (found.isEmpty) {
      return {'ok': false, 'error': '手机号未注册，请先注册'};
    }
    if (found.first.password != password) {
      return {'ok': false, 'error': '手机号或密码错误'};
    }
    return {'ok': true, 'user': found.first};
  }

  /// 实名认证：校验身份证号 + 姓名，回填认证信息
  /// [realName] 为空时默认使用注册姓名；也允许填写与注册姓名一致的真实姓名。
  static Future<Map<String, dynamic>> verifyIdentity({
    required String phone,
    required String idCard,
    String? realName,
  }) async {
    final info = IdCardUtil.validate(idCard);
    if (!info.valid) {
      return {'ok': false, 'error': info.error};
    }
    final users = await getUsers();
    final idx = users.indexWhere((u) => u.phone == phone);
    if (idx < 0) {
      return {'ok': false, 'error': '账号不存在，请重新登录'};
    }
    // 同一身份证号不能绑定到其他账号
    final normalized = idCard.trim().toUpperCase();
    if (users.any((u) => u.idCard == normalized && u.phone != phone)) {
      return {'ok': false, 'error': '该身份证号已绑定其他账号'};
    }

    final name = (realName == null || realName.trim().isEmpty)
        ? users[idx].name
        : realName.trim();

    final birthday = info.birthday!;
    final birthdayStr =
        '${birthday.year.toString().padLeft(4, '0')}-${birthday.month.toString().padLeft(2, '0')}-${birthday.day.toString().padLeft(2, '0')}';

    users[idx] = users[idx].copyWith(
      name: name,
      idCard: normalized,
      gender: info.gender ?? '',
      birthday: birthdayStr,
      province: info.province ?? '',
      verifiedAt: DateTime.now().toIso8601String(),
    );
    await _saveUsers(users);
    return {'ok': true, 'user': users[idx]};
  }

  /// 更新头像路径（写入用户档案并同步刷新登录态）
  ///
  /// 传空字符串表示移除头像（界面回落为默认图标）。
  static Future<Map<String, dynamic>> updateAvatar({
    required String phone,
    required String avatarPath,
  }) async {
    final users = await getUsers();
    final idx = users.indexWhere((u) => u.phone == phone);
    if (idx < 0) {
      return {'ok': false, 'error': '账号不存在，请重新登录'};
    }
    users[idx] = users[idx].copyWith(avatarPath: avatarPath);
    await _saveUsers(users);

    // 同步登录态，避免「我的」页重新读取时拿到旧值
    final auth = await getAuth();
    if (auth != null && auth.phone == phone) {
      await setAuth(PersonalAuth.fromUser(users[idx]));
    }
    return {'ok': true, 'user': users[idx]};
  }

  /// 设置登录态
  static Future<void> setAuth(PersonalAuth auth) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_authKey, jsonEncode(auth.toJson()));
  }

  /// 获取当前登录态
  static Future<PersonalAuth?> getAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_authKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return PersonalAuth.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 退出登录
  static Future<void> clearAuth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authKey);
  }
}
