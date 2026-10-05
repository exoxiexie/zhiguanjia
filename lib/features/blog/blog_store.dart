/// 博客本地存储（职管家 · 个人职业版）
///
/// **存储形态**：SharedPreferences，按**作者手机号**分键存储（`blog_posts_{手机号}`），
/// 与全站「按手机号做本地数据隔离」的约定一致。
///
/// **三种读取口径**：
/// - [loadMyPosts]：只读当前登录账号的键 → 用于「我的」子 Tab；
/// - [loadByAuthor]：只读指定作者的键 → 用于用户主页与「关注」流
///   （关注关系存在 follow_store.dart，与说说数据分开）；
/// - [loadFeed]：聚合本机**所有账号**发布的博客并按时间倒序 → 用于「推荐」时间线
///   （推荐规则待后续接入，当前先以全量时间线填充内容）。
///
/// **为什么按作者分键、而不是建一个全局键**：
/// 1. 与既有数据完全兼容 —— v1.0.7/v1.0.8 已发布的博客无需任何迁移即可进入时间线；
/// 2. 「我的」只读自己的键，天然满足租户隔离，不需要读出后再过滤；
/// 3. 单键损坏不会波及他人内容（聚合时逐条容错）。
///
/// 后续接入后端时，把本类的读写换成接口即可，上层（编辑器 / 列表）无需改动。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../personal/personal_auth_service.dart';

/// 博客文章模型
class BlogPost {
  /// 历史版本在标题为空时会自动填充的占位标题。
  /// 展示层需将其视为「无标题」，不再显示该占位文字。
  static const String legacyUntitled = '无标题';

  /// 作者昵称缺失时的兜底显示名
  static const String anonymousAuthor = '匿名用户';

  final String id;
  final String title;
  final String content;

  /// 配图本地文件路径（应用私有目录，见 post_image_store.dart）
  ///
  /// 一条说说可以是「纯文字」「纯图片」或「文字 + 图片」；
  /// 无配图时为空列表（历史数据天然兼容）。
  final List<String> images;

  final int createdAt; // 毫秒时间戳

  /// 作者手机号（发布时快照；历史数据在读取时由所属存储键回填）
  final String authorPhone;

  /// 作者昵称（发布时快照；为空时回落到用户表，仍为空则显示「匿名用户」）
  final String authorName;

  /// 作者头像本地文件路径（发布时快照；读取时以用户表为准，保证换头像后即时一致）
  final String authorAvatarPath;

  const BlogPost({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    this.images = const [],
    this.authorPhone = '',
    this.authorName = '',
    this.authorAvatarPath = '',
  });

  /// 是否应展示标题。
  ///
  /// 为空字符串、纯空白，或历史遗留的「无标题」占位，都视为无标题：
  /// 展示层会跳过标题元素，直接显示正文。
  bool get showTitle {
    final t = title.trim();
    return t.isNotEmpty && t != legacyUntitled;
  }

  /// 正文（去首尾空白，便于展示层直接使用）
  String get displayContent => content.trim();

  /// 是否带配图
  bool get hasImages => images.isNotEmpty;

  /// 作者昵称（缺失时兜底为「匿名用户」）
  String get displayAuthor {
    final n = authorName.trim();
    return n.isEmpty ? anonymousAuthor : n;
  }

  /// 头像取色种子：优先手机号（同一作者颜色恒定），无手机号时退化为昵称
  String get avatarSeed => authorPhone.isNotEmpty ? authorPhone : authorName;

  factory BlogPost.fromJson(Map<String, dynamic> json) => BlogPost(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        content: json['content']?.toString() ?? '',
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
        images: (json['images'] as List?)
                ?.map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList() ??
            const [],
        authorPhone: json['authorPhone']?.toString() ?? '',
        authorName: json['authorName']?.toString() ?? '',
        authorAvatarPath: json['authorAvatarPath']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'createdAt': createdAt,
        'images': images,
        'authorPhone': authorPhone,
        'authorName': authorName,
        'authorAvatarPath': authorAvatarPath,
      };

  BlogPost copyWith({
    String? id,
    String? title,
    String? content,
    int? createdAt,
    List<String>? images,
    String? authorPhone,
    String? authorName,
    String? authorAvatarPath,
  }) =>
      BlogPost(
        id: id ?? this.id,
        title: title ?? this.title,
        content: content ?? this.content,
        createdAt: createdAt ?? this.createdAt,
        images: images ?? this.images,
        authorPhone: authorPhone ?? this.authorPhone,
        authorName: authorName ?? this.authorName,
        authorAvatarPath: authorAvatarPath ?? this.authorAvatarPath,
      );
}

class BlogStore {
  /// 每个作者一个存储键（键后缀即作者手机号）
  static const String _keyPrefix = 'blog_posts_';

  /// 未登录时的兜底键后缀
  static const String _guestPhone = 'guest';

  static String _keyFor(String phone) =>
      '$_keyPrefix${phone.isEmpty ? _guestPhone : phone}';

  /// 当前登录手机号（未登录落到 guest）
  static Future<String> _currentPhone() async {
    final auth = await PersonalAuthService.getAuth();
    return (auth == null || auth.phone.isEmpty) ? _guestPhone : auth.phone;
  }

  /// 全站时间线：聚合本机所有作者发布的博客（按发布时间倒序）
  ///
  /// 用于「推荐」子 Tab。推荐规则接入前，先以全量时间线解决内容过少的问题；
  /// 「关注」流只取已关注作者，见 follow_store.dart。
  static Future<List<BlogPost>> loadFeed() async {
    final prefs = await SharedPreferences.getInstance();
    final names = await _authorRegistry();
    final all = <BlogPost>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_keyPrefix)) continue;
      final phone = key.substring(_keyPrefix.length);
      all.addAll(_decode(prefs.getStringList(key) ?? const [], phone, names));
    }
    all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return all;
  }

  /// 我发布的博客（只读当前账号的存储键，按发布时间倒序）
  static Future<List<BlogPost>> loadMyPosts() async =>
      loadByAuthor(await _currentPhone());

  /// 指定作者发布的博客（只读该作者的存储键，按发布时间倒序）
  ///
  /// 用于用户主页与「关注」流：按作者手机号精确取数，不触碰其他账号的键。
  static Future<List<BlogPost>> loadByAuthor(String phone) async {
    if (phone.isEmpty) return const [];
    final prefs = await SharedPreferences.getInstance();
    final names = await _authorRegistry();
    final list =
        _decode(prefs.getStringList(_keyFor(phone)) ?? const [], phone, names);
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// 新增一篇博客
  ///
  /// 写入当前登录账号的存储键；作者信息缺失时由本层补齐（调用方无需关心）。
  static Future<void> addPost(BlogPost post) async {
    final prefs = await SharedPreferences.getInstance();
    final auth = await PersonalAuthService.getAuth();
    final phone =
        (auth == null || auth.phone.isEmpty) ? _guestPhone : auth.phone;

    final toSave = post.copyWith(
      authorPhone: post.authorPhone.isEmpty ? phone : post.authorPhone,
      authorName:
          post.authorName.isEmpty ? (auth?.name ?? '') : post.authorName,
    );

    final key = _keyFor(phone);
    final list = prefs.getStringList(key) ?? <String>[];
    list.add(jsonEncode(toSave.toJson()));
    await prefs.setStringList(key, list);
  }

  /// 用户表：手机号 → 作者资料（昵称 + 头像路径）
  ///
  /// 作者头像以用户表为准（而不是只用发布时的快照），
  /// 这样用户换了头像后，他此前发布的博客在信息流里也会同步显示新头像。
  static Future<Map<String, ({String name, String avatarPath})>>
      _authorRegistry() async {
    try {
      final users = await PersonalAuthService.getUsers();
      return {
        for (final u in users) u.phone: (name: u.name, avatarPath: u.avatarPath)
      };
    } catch (_) {
      return const {};
    }
  }

  /// 逐条解析（单条损坏只跳过该条，不影响同键与他人内容）
  ///
  /// [fallbackPhone] 为该存储键对应的作者手机号：历史数据未写入作者字段时据此回填。
  static List<BlogPost> _decode(
    List<String> raw,
    String fallbackPhone,
    Map<String, ({String name, String avatarPath})> registry,
  ) {
    final out = <BlogPost>[];
    for (final e in raw) {
      try {
        var post = BlogPost.fromJson(jsonDecode(e) as Map<String, dynamic>);
        final phone =
            post.authorPhone.isEmpty ? fallbackPhone : post.authorPhone;
        final profile = registry[phone];
        post = post.copyWith(
          authorPhone: phone,
          authorName:
              post.authorName.isEmpty ? (profile?.name ?? '') : post.authorName,
          // 头像始终以用户表为准，其次才用发布时的快照
          authorAvatarPath: (profile != null && profile.avatarPath.isNotEmpty)
              ? profile.avatarPath
              : post.authorAvatarPath,
        );
        out.add(post);
      } catch (_) {
        // 跳过损坏条目
      }
    }
    return out;
  }
}
