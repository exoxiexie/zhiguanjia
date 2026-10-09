/// 注销账号时的本机数据清理（P5-c）
///
/// 注销是**不可恢复**操作，服务端删完后本机也必须清干净，
/// 否则重新注册同号会读到上一份残留数据（隐私问题）。
///
/// 清理范围：
/// 1. 租户目录 `tenants/{手机号}`：数据库（会话/消息/发件箱）、记忆、搜索沉淀
/// 2. 按账号分键的偏好存储（说说/收藏/关注/基础信息/经历/自我评价/学习成果）
/// 3. 本机用户表中的该账号
/// 4. 该账号上传的说说配图与头像文件（按文件名前缀无法枚举，故按目录清理会话相关）
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../personal/personal_auth_service.dart';
import '../storage/tenant_storage.dart';

class LocalDataCleaner {
  /// 按账号分键的存储前缀（键形如 `前缀 + 手机号`）
  static const List<String> accountKeyPrefixes = <String>[
    'blog_posts_',
    'favorites_',
    'follows_',
    'basic_info_',
    'experience_',
    'self_evaluation_',
    'study_output_',
  ];

  /// 清除该账号在本机的全部数据（任一步失败都不抛出：清理是尽力而为）
  static Future<void> purgeAccount(String phone) async {
    if (phone.isEmpty) return;

    // ① 租户目录（数据库/记忆/搜索沉淀）
    try {
      final dir = await TenantStorage.getTenantDir(phone);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // 忽略
    }

    // ② 按账号分键的偏好存储
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().toList()) {
        for (final prefix in accountKeyPrefixes) {
          if (key == '$prefix$phone') {
            await prefs.remove(key);
            break;
          }
        }
      }
    } catch (_) {
      // 忽略
    }

    // ③ 本机用户表
    try {
      await PersonalAuthService.removeLocalAccount(phone);
    } catch (_) {
      // 忽略
    }
  }
}
