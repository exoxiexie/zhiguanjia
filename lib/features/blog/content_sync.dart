/// 内容同步层（P3）：说说 / 收藏 / 关注
///
/// 策略（《商业版改造方案》第五节 B 类「内容类」）：**服务端为准 + 本地缓存**
///
/// - 写：先落本地（离线立即可见）→ 再尽力推送；推送失败静默，下次拉取以服务端为准
/// - 发布说说时会**先把本机图片上传**换成服务端地址，再发布 ——
///   这样换手机后配图也能显示（图片上传失败则保留本机路径，不阻塞发布）
/// - 读：按作者手机号把云端说说分组写回本机原有的 `blog_posts_{作者}` 键，
///   因此「推荐 / 关注 / 我的」三个子 Tab 的既有逻辑一行都不用改
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../contracts/content_api.dart';
import '../api/content_api_impl.dart';
import '../data/favorite_store.dart';
import '../personal/personal_auth_service.dart';
import 'blog_store.dart';
import 'follow_store.dart';
import 'post_image.dart';

class ContentSync {
  /// 内容接口（契约类型，便于替换实现与单元测试）
  static ContentApi _api = const HttpContentApi();

  /// 测试注入口：替换接口实现（仅单元测试使用）
  @visibleForTesting
  static set apiForTest(ContentApi value) => _api = value;

  /// 拉取节流：同一会话内 90 秒最多拉一次
  static const Duration minPullInterval = Duration(seconds: 90);

  /// 单次拉取硬超时：弱网时不能把"进入说说页"卡住
  static const Duration pullTimeout = Duration(seconds: 8);

  /// 节流时间按账号记录（换账号后应立即同步）
  static final Map<String, DateTime> _lastPullAt = <String, DateTime>{};
  static bool _pulling = false;

  /// 历史回填标记（按账号）
  static String backfillKeyFor(String phone) =>
      'zhiguanjia.content.backfilled.$phone';

  static Future<String?> _currentPhone() async {
    final auth = await PersonalAuthService.getAuth();
    final phone = auth?.phone ?? '';
    return phone.isEmpty ? null : phone;
  }

  static Future<bool> _canSync() async => await _currentPhone() != null;

  // ────────────────────────── 推送（写） ──────────────────────────

  /// 发布说说：先上传本机图片 → 再发布
  static Future<void> pushPost(BlogPost post) async {
    if (!await _canSync()) return;
    try {
      final uploaded = await _uploadLocalImages(post.images);
      final ok = await _api.publishPost(PostDto(
        id: post.id,
        title: post.title,
        content: post.content,
        images: uploaded,
        authorPhone: post.authorPhone,
        authorName: post.authorName,
        authorAvatarPath: post.authorAvatarPath,
        createdAt: post.createdAt,
      ));
      // 上传成功：把服务端地址写回本地，避免下次重复上传同一张图
      if (ok.ok && !listEquals(uploaded, post.images)) {
        await BlogStore.updatePostImagesLocal(post.authorPhone, post.id, uploaded);
      }
    } catch (_) {
      // 静默：本地已发布，联网后拉取会以服务端为准
    }
  }

  /// 把本机图片逐张上传；已是服务端地址的直接保留；失败的保留本机路径
  static Future<List<String>> _uploadLocalImages(List<String> images) async {
    if (images.isEmpty) return const [];
    final out = <String>[];
    for (final path in images) {
      if (isRemoteImage(path)) {
        out.add(path);
        continue;
      }
      final res = await _api.uploadImage(path);
      out.add(res.ok && (res.data ?? '').isNotEmpty ? res.data! : path);
    }
    return out;
  }

  /// 新增/更新收藏
  static Future<void> pushFavorite(FavoriteItem item) async {
    if (!await _canSync()) return;
    try {
      await _api.upsertFavorite(FavoriteDto(
        id: item.id,
        content: item.content,
        source: item.source,
        createdAt: item.createdAt,
      ));
    } catch (_) {
      // 静默
    }
  }

  /// 删除收藏
  static Future<void> pushDeleteFavorite(String id) async {
    if (!await _canSync()) return;
    try {
      await _api.deleteFavorite(id);
    } catch (_) {
      // 静默
    }
  }

  /// 关注 / 取关
  static Future<void> pushFollow(String targetPhone, bool follow) async {
    if (!await _canSync()) return;
    try {
      await _api.setFollow(targetPhone, follow);
    } catch (_) {
      // 静默
    }
  }

  // ────────────────────────── 拉取（读） ──────────────────────────

  /// 拉取云端内容并写入本地缓存（[force] 忽略节流）
  static Future<bool> pull({bool force = false}) async {
    final phone = await _currentPhone();
    if (phone == null) return false;
    if (_pulling) return false;
    final last = _lastPullAt[phone];
    if (!force && last != null && DateTime.now().difference(last) < minPullInterval) {
      return false;
    }

    _pulling = true;
    try {
      // 首次同步：把本地已发布/已收藏/已关注的内容全量推一次
      await _maybeBackfill(phone);

      final result = await _api.fetch().timeout(pullTimeout);
      if (!result.ok || result.data == null) return false;
      final bundle = result.data!;

      // 说说：按作者分组写回本机键（与原有存储布局完全一致）
      final byAuthor = <String, List<BlogPost>>{};
      for (final dto in bundle.posts) {
        final phone = dto.authorPhone.isEmpty ? 'guest' : dto.authorPhone;
        byAuthor.putIfAbsent(phone, () => []).add(_postFromDto(dto));
      }
      for (final entry in byAuthor.entries) {
        final list = entry.value
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        await BlogStore.replaceAuthorCache(entry.key, list);
      }

      await FavoriteStore.replaceCache([
        for (final f in bundle.favorites)
          FavoriteItem(
            id: f.id,
            content: f.content,
            source: f.source,
            createdAt: f.createdAt,
          ),
      ]);

      await FollowStore.replaceCache(bundle.follows.toSet());

      _lastPullAt[phone] = DateTime.now();
      return true;
    } catch (_) {
      // 超时/离线：保留本地缓存
      return false;
    } finally {
      _pulling = false;
    }
  }

  /// 进入说说页时调用：节流 + 超时保护，失败静默
  static Future<void> pullIfNeeded() => pull();

  /// 登录后调用：强制拉取一次
  static Future<void> pullOnLogin() => pull(force: true);

  /// 首次同步：把本地已有内容全量推一次
  ///
  /// 与对话侧同理：outbox 只记录升级后的新写入，升级前发过的说说/收藏/关注
  /// 从未上传过，需要一次性回填（幂等，失败下次重试）。
  static Future<void> _maybeBackfill(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(backfillKeyFor(phone)) == true) return;
    if (await backfillLocalContent()) {
      await prefs.setBool(backfillKeyFor(phone), true);
    }
  }

  /// 全量回填本地内容（我的说说含配图、收藏、关注），返回是否全部成功
  @visibleForTesting
  static Future<bool> backfillLocalContent() async {
    final phone = await _currentPhone();
    if (phone == null) return false;
    try {
      // 我发布过的说说（配图先上传）
      final mine = await BlogStore.loadByAuthor(phone);
      for (final post in mine) {
        final uploaded = await _uploadLocalImages(post.images);
        final res = await _api.publishPost(PostDto(
          id: post.id,
          title: post.title,
          content: post.content,
          images: uploaded,
          authorPhone: post.authorPhone,
          authorName: post.authorName,
          authorAvatarPath: post.authorAvatarPath,
          createdAt: post.createdAt,
        ));
        if (!res.ok) return false;
        if (!listEquals(uploaded, post.images)) {
          await BlogStore.updatePostImagesLocal(
              post.authorPhone.isEmpty ? phone : post.authorPhone,
              post.id,
              uploaded);
        }
      }

      // 收藏
      for (final item in await FavoriteStore.list()) {
        final res = await _api.upsertFavorite(FavoriteDto(
          id: item.id,
          content: item.content,
          source: item.source,
          createdAt: item.createdAt,
        ));
        if (!res.ok) return false;
      }

      // 关注
      for (final target in await FollowStore.loadFollowing()) {
        final res = await _api.setFollow(target, true);
        if (!res.ok) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 仅测试使用：清空节流与进行中标记
  @visibleForTesting
  static void resetForTest() {
    _lastPullAt.clear();
    _pulling = false;
  }

  static BlogPost _postFromDto(PostDto d) => BlogPost(
        id: d.id,
        title: d.title,
        content: d.content,
        images: d.images,
        authorPhone: d.authorPhone,
        authorName: d.authorName,
        authorAvatarPath: d.authorAvatarPath,
        createdAt: d.createdAt,
      );
}
