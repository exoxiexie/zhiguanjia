/// 关注关系本地存储（职管家 · 个人职业版）
///
/// **存储形态**：SharedPreferences，按**当前登录账号**分键存储
/// （`follows_{我的手机号}` → 被关注者手机号列表），与全站
/// 「按手机号做本地数据隔离」的约定一致：换账号登录即换一份关注关系。
///
/// **为什么单独一个 Store，而不塞进 [BlogStore]**：
/// 关注是「账号 → 账号」的社交关系，与说说内容本身无关。独立成键后，
/// 说说数据的读写完全不受关注功能影响；接口化时两者也能各自替换。
library;

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../personal/personal_auth_service.dart';
import 'blog_store.dart';
import 'content_sync.dart';

class FollowStore {
  /// 每个账号一个存储键（键后缀即账号手机号）
  static const String _keyPrefix = 'follows_';

  /// 未登录时的兜底键后缀
  static const String _guestPhone = 'guest';

  static String _keyFor(String phone) =>
      '$_keyPrefix${phone.isEmpty ? _guestPhone : phone}';

  /// 当前登录手机号（未登录落到 guest）
  static Future<String> _currentPhone() async {
    final auth = await PersonalAuthService.getAuth();
    return (auth == null || auth.phone.isEmpty) ? _guestPhone : auth.phone;
  }

  /// 我关注的作者手机号集合
  static Future<Set<String>> loadFollowing() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = await _currentPhone();
    return (prefs.getStringList(_keyFor(phone)) ?? const <String>[]).toSet();
  }

  /// 是否已关注某人
  static Future<bool> isFollowing(String targetPhone) async {
    if (targetPhone.isEmpty) return false;
    return (await loadFollowing()).contains(targetPhone);
  }

  /// 设置关注状态（`true` 关注 / `false` 取关），幂等
  ///
  /// 不允许关注自己（自己主页本就不显示关注按钮，这里再兜一道）。
  static Future<void> setFollow(String targetPhone, bool follow) async {
    if (targetPhone.isEmpty) return;
    final me = await _currentPhone();
    if (targetPhone == me) return;

    final prefs = await SharedPreferences.getInstance();
    final key = _keyFor(me);
    final set = (prefs.getStringList(key) ?? const <String>[]).toSet();
    if (follow) {
      set.add(targetPhone);
    } else {
      set.remove(targetPhone);
    }
    await prefs.setStringList(key, set.toList());
    // P3 起：本地关注成功后尽力上云
    unawaited(ContentSync.pushFollow(targetPhone, follow));
  }

  /// 用云端数据覆盖本地缓存（同步层专用，不触发推送）
  static Future<void> replaceCache(Set<String> following) async {
    final prefs = await SharedPreferences.getInstance();
    final me = await _currentPhone();
    await prefs.setStringList(_keyFor(me), following.toList());
  }

  /// 切换关注状态，返回切换**后**的状态
  static Future<bool> toggleFollow(String targetPhone) async {
    final wasFollowing = await isFollowing(targetPhone);
    await setFollow(targetPhone, !wasFollowing);
    return !wasFollowing;
  }

  /// 关注流：已关注作者的说说，按发布时间倒序（由近及远）
  ///
  /// 未关注任何人时返回空列表（列表页据此显示空态）。
  static Future<List<BlogPost>> loadFollowingFeed() async {
    final following = await loadFollowing();
    if (following.isEmpty) return const [];
    final all = <BlogPost>[];
    for (final phone in following) {
      all.addAll(await BlogStore.loadByAuthor(phone));
    }
    all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return all;
  }
}
