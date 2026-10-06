/// 职业经历本地存储（职管家 · 个人职业版）
///
/// **存储形态**：SharedPreferences，按**当前登录账号**分键存储
/// （`experience_{手机号}` → 每行一条经历的 JSON），与全站
/// 「按手机号做本地数据隔离」的约定一致：换账号登录即换一份经历档案。
///
/// **为什么三类经历共用一个键、而不是每类一个键**：
/// 教育 / 工作 / 培训用的是同一个实体（[ExperienceEntry]，以 `kind` 区分），
/// 合一个键后「新增一类经历」不需要动存储；读取时按 `kind` 过滤即可。
/// 这是本项目里唯一按类型过滤的存储，数据量级很小（每人几十条），过滤成本可忽略。
///
/// **排序**：一律按起始时间倒序（由近及远），未填起始时间的排最后 ——
/// 与主流简历产品一致，最近的一段经历永远在最上面。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../personal/personal_auth_service.dart';
import 'experience_models.dart';

class ExperienceStore {
  /// 每个账号一个存储键（键后缀即账号手机号）
  static const String _keyPrefix = 'experience_';

  /// 未登录时的兜底键后缀
  static const String _guestPhone = 'guest';

  static String _keyFor(String phone) =>
      '$_keyPrefix${phone.isEmpty ? _guestPhone : phone}';

  /// 当前登录手机号（未登录落到 guest）
  static Future<String> _currentPhone() async {
    final auth = await PersonalAuthService.getAuth();
    return (auth == null || auth.phone.isEmpty) ? _guestPhone : auth.phone;
  }

  /// 读当前账号的全部经历（已按起始时间倒序）
  static Future<List<ExperienceEntry>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = await _currentPhone();
    final raw = prefs.getStringList(_keyFor(phone)) ?? const <String>[];
    final out = <ExperienceEntry>[];
    for (final e in raw) {
      try {
        out.add(ExperienceEntry.fromJson(jsonDecode(e) as Map<String, dynamic>));
      } catch (_) {
        // 单条损坏只跳过该条，不影响其他经历
      }
    }
    out.sort((a, b) => b.sortKey.compareTo(a.sortKey));
    return out;
  }

  /// 指定类型的经历（详情页用）
  static Future<List<ExperienceEntry>> listByKind(String kindId) async {
    final all = await _loadAll();
    return all.where((e) => e.kindId == kindId).toList();
  }

  /// 三类经历的条数（数据页通栏卡片右侧显示「N 条」）
  static Future<Map<String, int>> counts() async {
    final all = await _loadAll();
    final map = {for (final k in ExperienceKind.all) k.id: 0};
    for (final e in all) {
      map[e.kindId] = (map[e.kindId] ?? 0) + 1;
    }
    return map;
  }

  /// 新增或更新一条经历（按 id 覆盖，不存在则追加）
  static Future<void> save(ExperienceEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final phone = await _currentPhone();
    final key = _keyFor(phone);
    final raw = prefs.getStringList(key) ?? <String>[];

    var replaced = false;
    final next = <String>[];
    for (final e in raw) {
      String? id;
      try {
        id = (jsonDecode(e) as Map<String, dynamic>)['id']?.toString();
      } catch (_) {
        id = null;
      }
      if (id != null && id == entry.id) {
        next.add(jsonEncode(entry.toJson()));
        replaced = true;
      } else {
        next.add(e);
      }
    }
    if (!replaced) next.add(jsonEncode(entry.toJson()));

    await prefs.setStringList(key, next);
  }

  /// 删除一条经历
  static Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final phone = await _currentPhone();
    final key = _keyFor(phone);
    final raw = prefs.getStringList(key) ?? <String>[];

    final next = <String>[];
    for (final e in raw) {
      try {
        final eid = (jsonDecode(e) as Map<String, dynamic>)['id']?.toString();
        if (eid == id) continue;
      } catch (_) {
        // 损坏条目按原样保留，交给列表页的容错逻辑处理
      }
      next.add(e);
    }
    await prefs.setStringList(key, next);
  }
}
