/// 博客本地存储（职管家 · 个人职业版）
///
/// 当前用 SharedPreferences 按登录手机号隔离存储「我发布的博客」，
/// 仅为 MVP 本地闭环；后续接入后端时，把 [BlogStore] 的读写换成接口即可，
/// 上层（编辑器 / 我的列表）无需改动。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../personal/personal_auth_service.dart';

/// 博客文章模型
class BlogPost {
  /// 历史版本在标题为空时会自动填充的占位标题。
  /// 展示层需将其视为「无标题」，不再显示该占位文字。
  static const String legacyUntitled = '无标题';

  final String id;
  final String title;
  final String content;
  final int createdAt; // 毫秒时间戳

  const BlogPost({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
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

  factory BlogPost.fromJson(Map<String, dynamic> json) => BlogPost(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        content: json['content']?.toString() ?? '',
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'createdAt': createdAt,
      };
}

class BlogStore {
  static const String _keyPrefix = 'blog_posts_';

  /// 当前登录手机号对应的存储 key（未登录时落到 guest）
  static Future<String> _key() async {
    final auth = await PersonalAuthService.getAuth();
    final phone = (auth == null || auth.phone.isEmpty) ? 'guest' : auth.phone;
    return '$_keyPrefix$phone';
  }

  /// 读取我发布的博客（按发布时间倒序）
  ///
  /// 单条记录损坏时跳过该条并继续，避免一条坏数据导致整个列表（推荐流与
  /// 我的列表）加载失败、只剩空态。
  static Future<List<BlogPost>> loadMyPosts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(await _key()) ?? const [];
    final list = <BlogPost>[];
    for (final e in raw) {
      try {
        list.add(BlogPost.fromJson(jsonDecode(e) as Map<String, dynamic>));
      } catch (_) {
        // 跳过损坏条目
      }
    }
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// 新增一篇博客
  static Future<void> addPost(BlogPost post) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _key();
    final list = prefs.getStringList(key) ?? <String>[];
    list.add(jsonEncode(post.toJson()));
    await prefs.setStringList(key, list);
  }
}
