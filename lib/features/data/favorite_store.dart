/// 收藏存储（职管家 · 个人职业版）
///
/// **用途**：把 AI 回复气泡「收藏」下来的输出统一收拢，在「我的 · 收藏」卡按时间线展示。
///
/// **存储形态**：SharedPreferences，按当前登录账号分键（`favorites_{手机号}`），
/// 与全站「按手机号做本地数据隔离」一致；未登录落到 guest。
///
/// **排序**：一律按收藏时间倒序（最近收藏的在最上面）。
/// **去重**：同一段内容重复点「收藏」不产生第二条；气泡按钮据此在「收藏 / 已收藏」间切换。
library;

import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../personal/personal_auth_service.dart';

/// 一条收藏的 AI 输出
class FavoriteItem {
  /// 唯一 id
  final String id;

  /// 正文（AI 回复全文）
  final String content;

  /// 来源（对话首页的 AI 回复统一记为 '通用对话'）
  final String source;

  /// 收藏时间（毫秒时间戳，时间线排序依据）
  final int createdAt;

  const FavoriteItem({
    required this.id,
    required this.content,
    required this.source,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'source': source,
        'createdAt': createdAt,
      };

  factory FavoriteItem.fromJson(Map<String, dynamic> j) => FavoriteItem(
        id: j['id']?.toString() ?? '',
        content: j['content']?.toString() ?? '',
        source: j['source']?.toString() ?? '',
        createdAt: j['createdAt'] is int
            ? j['createdAt'] as int
            : int.tryParse('${j['createdAt']}') ?? 0,
      );
}

class FavoriteStore {
  /// 每个账号一个存储键（键后缀即账号手机号）
  static const String _keyPrefix = 'favorites_';

  /// 未登录时的兜底键后缀
  static const String _guestPhone = 'guest';

  static Future<String> _keyFor() async {
    final auth = await PersonalAuthService.getAuth();
    final phone =
        (auth == null || auth.phone.isEmpty) ? _guestPhone : auth.phone;
    return '$_keyPrefix$phone';
  }

  static FavoriteItem? _decode(String raw) {
    try {
      return FavoriteItem.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // 单条损坏只跳过该条，不影响其他收藏
      return null;
    }
  }

  /// 当前账号的全部收藏（按时间倒序）
  static Future<List<FavoriteItem>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(await _keyFor()) ?? const <String>[];
    final out = <FavoriteItem>[];
    for (final e in raw) {
      final item = _decode(e);
      if (item != null) out.add(item);
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  /// 收藏条数（我的页卡片右侧显示「N 条」）
  static Future<int> count() async => (await list()).length;

  /// 是否已收藏同一内容（供气泡按钮显示「已收藏」态）
  static Future<bool> contains(String content) async {
    if (content.trim().isEmpty) return false;
    final items = await list();
    return items.any((e) => e.content == content);
  }

  /// 新增一条收藏；内容为空返回 false，已存在同内容也返回 false（不重复收藏）
  static Future<bool> add({
    required String content,
    required String source,
  }) async {
    if (content.trim().isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    final key = await _keyFor();
    final raw = prefs.getStringList(key) ?? <String>[];

    for (final e in raw) {
      final item = _decode(e);
      if (item != null && item.content == content) return false;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(0x7fffffff);
    final item = FavoriteItem(
      id: '$now-$rand',
      content: content,
      source: source,
      createdAt: now,
    );
    await prefs.setStringList(key, [...raw, jsonEncode(item.toJson())]);
    return true;
  }

  /// 取消收藏（按内容移除，供气泡「已收藏」再点取消）
  static Future<void> removeByContent(String content) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _keyFor();
    final raw = prefs.getStringList(key) ?? <String>[];
    final next = <String>[];
    for (final e in raw) {
      final item = _decode(e);
      if (item != null && item.content == content) continue;
      next.add(e);
    }
    await prefs.setStringList(key, next);
  }

  /// 删除一条收藏（收藏列表页按 id 删除）
  static Future<void> removeById(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _keyFor();
    final raw = prefs.getStringList(key) ?? <String>[];
    final next = <String>[];
    for (final e in raw) {
      final item = _decode(e);
      if (item != null && item.id == id) continue;
      next.add(e);
    }
    await prefs.setStringList(key, next);
  }
}
