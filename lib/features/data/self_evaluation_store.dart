/// 自我评价存储（职管家 · 个人职业版）
///
/// **为什么单独一个存储、而不是塞进经历模块**：
/// 三类经历（学历教育 / 工作经历 / 技能培训）是「多条记录的列表」，
/// 而自我评价是**单段自由文本**——每人一份、可反复修改，不存在多条。
/// 硬塞进经历模型只会让「列表」和「单值」两种形态互相迁就。
///
/// **存储形态**：SharedPreferences，按当前登录账号分键
/// （`self_evaluation_{手机号}`），与全站「按手机号做本地数据隔离」一致。
/// 保存空串即删除该键（等价于"清空自我评价"）。
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../personal/personal_auth_service.dart';

class SelfEvaluationStore {
  /// 每个账号一个存储键（键后缀即账号手机号）
  static const String _keyPrefix = 'self_evaluation_';

  /// 未登录时的兜底键后缀
  static const String _guestPhone = 'guest';

  static Future<String> _keyFor() async {
    final auth = await PersonalAuthService.getAuth();
    final phone =
        (auth == null || auth.phone.isEmpty) ? _guestPhone : auth.phone;
    return '$_keyPrefix$phone';
  }

  /// 读取自我评价（未填写返回空串）
  static Future<String> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(await _keyFor()) ?? '';
  }

  /// 保存自我评价（传空串或纯空白即清空）
  static Future<void> save(String text) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _keyFor();
    final t = text.trim();
    if (t.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, t);
    }
  }
}
