/// 个人认证服务（职管家 · P1 商业版）
///
/// 变更要点（v1.0.36）：
/// - 注册 / 登录 **改为服务端校验**（账号云端化，换手机不丢号）
/// - 服务端认证成功后**不再在本机保留明文密码**（旧版本地密码仅在
///   "老账号首次迁移"时用于证明身份，迁移成功即清除）
/// - 本机仍按手机号做数据隔离租户ID（注册即有、永不变，认证前后一致），
///   因此**升级后原有对话/记忆/说说等本机数据不受影响**
///
/// 保持不变（对外签名零改动，UI 无需调整）：
/// [getUsers] [registerUser] [loginUser] [verifyIdentity]
/// [updateAvatar] [setAuth] [getAuth] [clearAuth]
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../contracts/auth_api.dart';
import '../api/api_client.dart';
import '../api/auth_api_impl.dart';
import 'id_card_util.dart';
import 'personal_model.dart';

class PersonalAuthService {
  static const String _usersKey = 'zhiguanjia.personal.users';
  static const String _authKey = 'zhiguanjia.personal.auth';

  /// 账号接口（契约类型，便于将来替换实现）
  static AuthApi _api = const HttpAuthApi();

  /// 测试注入口：替换账号接口实现（仅单元测试使用，生产代码不得调用）
  @visibleForTesting
  static set apiForTest(AuthApi value) => _api = value;

  /// 获取所有本机用户（服务端认证成功后作为本地缓存与档案来源）
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

  /// 注册个人账号（手机号 + 密码 + 姓名）· 服务端校验
  static Future<Map<String, dynamic>> registerUser({
    required String phone,
    required String password,
    required String name,
  }) async {
    // 本地先做格式校验：断网时也能立刻给出明确提示
    final invalid = _validateRegistration(phone, password, name);
    if (invalid != null) return {'ok': false, 'error': invalid};

    final result = await _api.register(
      phone: phone,
      password: password,
      name: name.trim(),
    );
    if (!result.ok) {
      return {'ok': false, 'error': result.error!.message};
    }
    final user = await _persistSession(result.data!);
    return {'ok': true, 'user': user};
  }

  /// 登录校验 · 服务端校验
  ///
  /// 兼容老版本：若本机存在同手机号且密码一致的历史账号、而服务端尚无
  /// 该账号，则**自动迁移**（用同一手机号+密码注册到服务端）后直接登录，
  /// 让老用户无感升级。
  static Future<Map<String, dynamic>> loginUser(
      String phone, String password) async {
    final trimmedPhone = phone.trim();
    if (trimmedPhone.isEmpty || password.isEmpty) {
      return {'ok': false, 'error': '请输入手机号和密码'};
    }

    final result =
        await _api.login(phone: trimmedPhone, password: password);
    if (result.ok) {
      final user = await _persistSession(result.data!);
      return {'ok': true, 'user': user};
    }

    final error = result.error!;
    // 仅"账号或密码不正确"时才尝试迁移；网络错误直接如实提示
    if (error.code == 'bad_credentials' && error.statusCode == 401) {
      final migrated = await _migrateLegacyLocalAccount(trimmedPhone, password);
      if (migrated != null) return migrated;
    }
    return {'ok': false, 'error': error.message};
  }

  /// 老版本地账号迁移：本机存在同手机号、密码一致的老账号 → 注册到服务端
  ///
  /// 返回登录结果；无法证明身份（本机无记录 / 密码不符 / 服务端已有该号）
  /// 时返回 null，由调用方回落到普通错误提示。
  static Future<Map<String, dynamic>?> _migrateLegacyLocalAccount(
    String phone,
    String password,
  ) async {
    final users = await getUsers();
    final idx = users.indexWhere((u) => u.phone == phone);
    if (idx < 0) return null;

    final local = users[idx];
    // 必须是"老版本留下的明文密码"且与输入一致，否则不做迁移
    if (local.password.isEmpty || local.password != password) return null;

    final name = local.name.trim().isNotEmpty
        ? local.name.trim()
        : '用户${phone.length >= 8 ? phone.substring(phone.length - 4) : phone}';

    final result = await _api.register(
      phone: phone,
      password: password,
      name: name,
    );
    if (!result.ok) return null; // 409=服务端已存在（密码确实不对），或网络异常

    final user = await _persistSession(result.data!);
    return {'ok': true, 'user': user, 'migrated': true};
  }

  /// 本地格式校验（与旧版本提示文案保持一致，避免用户困惑）
  static String? _validateRegistration(
      String phone, String password, String name) {
    if (phone.length != 11 || !phone.startsWith('1')) {
      return '请输入正确的11位手机号';
    }
    if (name.trim().isEmpty) return '请输入姓名';
    if (password.length < 6) return '密码至少6位';
    return null;
  }

  /// 保存服务端会话（令牌 + 本地用户缓存）
  ///
  /// 服务端认证成功后本机不再保留明文密码（传空字符串）。
  static Future<PersonalUser> _persistSession(
    AuthSession session, {
    String password = '',
  }) async {
    await TokenStore.save(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      expiresIn: session.expiresIn,
      userId: session.user.id,
    );
    return _mergeLocalUser(session.user, password: password);
  }

  /// 把服务端资料合并进本机用户缓存
  ///
  /// 合并原则：**本机已有的档案字段优先保留**（实名信息、头像、注册时间等
  /// 在 P2/P3 才会上云），服务端只负责账号身份相关字段。
  static Future<PersonalUser> _mergeLocalUser(
    AuthUser remote, {
    String password = '',
  }) async {
    final users = await getUsers();
    final idx = users.indexWhere((u) => u.phone == remote.phone);
    final existing = idx >= 0 ? users[idx] : null;

    final merged = PersonalUser(
      phone: remote.phone,
      password: password,
      name: remote.name.isNotEmpty ? remote.name : (existing?.name ?? ''),
      idCard: existing?.idCard ?? '',
      gender: (existing?.gender ?? '').isNotEmpty
          ? existing!.gender
          : remote.gender,
      birthday: (existing?.birthday ?? '').isNotEmpty
          ? existing!.birthday
          : remote.birthday,
      province: (existing?.province ?? '').isNotEmpty
          ? existing!.province
          : remote.province,
      verifiedAt: (existing?.verifiedAt ?? '').isNotEmpty
          ? existing!.verifiedAt
          : remote.verifiedAt,
      createdAt: (existing?.createdAt ?? '').isNotEmpty
          ? existing!.createdAt
          : DateTime.now().toIso8601String(),
      avatarPath: (existing?.avatarPath ?? '').isNotEmpty
          ? existing!.avatarPath
          : remote.avatarPath,
    );

    if (idx >= 0) {
      users[idx] = merged;
    } else {
      users.add(merged);
    }
    await _saveUsers(users);
    return merged;
  }

  /// 实名认证：校验身份证号 + 姓名，回填认证信息
  ///
  /// P1 仍在本机完成（身份证校验规则在 [IdCardUtil]）；
  /// P2 会改为服务端校验并上云（同一证件不可绑定多个账号的校验届时由服务端做）。
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

  /// 设置登录态（同时把服务端访问令牌写入登录记录）
  static Future<void> setAuth(PersonalAuth auth) async {
    final accessToken = await TokenStore.accessToken();
    final record = accessToken.isEmpty
        ? auth
        : PersonalAuth(
            token: accessToken,
            phone: auth.phone,
            name: auth.name,
            idCard: auth.idCard,
            gender: auth.gender,
            birthday: auth.birthday,
            province: auth.province,
            verifiedAt: auth.verifiedAt,
            avatarPath: auth.avatarPath,
          );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_authKey, jsonEncode(record.toJson()));
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

  /// 退出登录：吊销服务端令牌（尽力而为）+ 清理本机令牌与登录态
  static Future<void> clearAuth() async {
    final refreshToken = await TokenStore.refreshToken();
    if (refreshToken.isNotEmpty) {
      // 不阻塞退出流程；网络失败也不影响本机登出
      unawaited(() async {
        try {
          await _api.logout(refreshToken: refreshToken);
        } catch (_) {
          // 忽略：服务端令牌到期后自然失效
        }
      }());
    }
    await TokenStore.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authKey);
  }
}
