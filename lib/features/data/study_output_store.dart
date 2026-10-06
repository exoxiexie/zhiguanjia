/// 自主学习成果的本地存储（职管家 · 个人职业版）
///
/// **定位**：这里放的是「自主式学习的成果」—— 研究报告、论文，
/// 尤其是**借助 AI 完成的研究式学习产出**。与「学历教育 / 技能培训」不同，
/// 前者记录的是"上过什么学、参加过什么培训"，这里记录的是"做出了什么"。
///
/// **存储形态**：SharedPreferences，按当前登录账号分键
/// （`study_output_{手机号}` → 每行一条成果的 JSON），与全站
/// 「按手机号做本地数据隔离」的约定一致。
///
/// **附件落盘**：图片与 PDF 由 [StudyFileStore] 复制进应用私有目录
/// `study_files/` 之后才入库；本类只存**绝对路径 + 原始文件名 + 字节数**，
/// **不存文件内容** —— 与说说配图同一套思路（系统临时路径会被清理成坏附件）。
///
/// **排序**：按最近更新倒序（刚编辑过的成果排最前）。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../personal/personal_auth_service.dart';

/// 一个附件（当前用于 PDF，结构上不限定类型）
class StudyAttachment {
  /// 私有目录里的绝对路径
  final String path;

  /// 原始文件名（展示用，比时间戳命名可读）
  final String name;

  /// 字节数（展示用）
  final int size;

  const StudyAttachment({
    required this.path,
    this.name = '',
    this.size = 0,
  });

  factory StudyAttachment.fromJson(Map<String, dynamic> json) =>
      StudyAttachment(
        path: json['path']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        size: (json['size'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'size': size,
      };
}

/// 一条自主学习成果
///
/// 内容形态：**标题（必填）+ 文字说明 + 图片 + 附件**，四者可任意组合。
class StudyOutput {
  final String id;
  final String title;
  final String content;

  /// 图片（私有目录绝对路径）
  final List<String> images;

  /// 附件（PDF 等）
  final List<StudyAttachment> files;

  final int createdAt;
  final int updatedAt;

  const StudyOutput({
    required this.id,
    required this.title,
    this.content = '',
    this.images = const [],
    this.files = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  /// 展示用标题（空标题回落）
  String get displayTitle => title.trim().isEmpty ? '未命名成果' : title.trim();

  factory StudyOutput.fromJson(Map<String, dynamic> json) => StudyOutput(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        content: json['content']?.toString() ?? '',
        images: [
          for (final e in (json['images'] as List?) ?? const [])
            if (e != null) e.toString(),
        ].where((e) => e.isNotEmpty).toList(),
        files: [
          for (final e in (json['files'] as List?) ?? const [])
            if (e is Map) StudyAttachment.fromJson(Map<String, dynamic>.from(e)),
        ],
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
        updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'images': images,
        'files': [for (final f in files) f.toJson()],
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

class StudyOutputStore {
  /// 每个账号一个存储键（键后缀即账号手机号）
  static const String _keyPrefix = 'study_output_';

  /// 未登录时的兜底键后缀
  static const String _guestPhone = 'guest';

  static String _keyFor(String phone) =>
      '$_keyPrefix${phone.isEmpty ? _guestPhone : phone}';

  /// 当前登录手机号（未登录落到 guest）
  static Future<String> _currentPhone() async {
    final auth = await PersonalAuthService.getAuth();
    return (auth == null || auth.phone.isEmpty) ? _guestPhone : auth.phone;
  }

  /// 读当前账号的全部成果（已按最近更新倒序）
  static Future<List<StudyOutput>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = await _currentPhone();
    final raw = prefs.getStringList(_keyFor(phone)) ?? const <String>[];
    final out = <StudyOutput>[];
    for (final e in raw) {
      try {
        out.add(StudyOutput.fromJson(jsonDecode(e) as Map<String, dynamic>));
      } catch (_) {
        // 单条损坏只跳过该条，不影响其他成果
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  /// 成果条数（数据页通栏卡片右侧显示「N 条」）
  static Future<int> count() async => (await loadAll()).length;

  /// 新增或更新一条成果（按 id 覆盖，不存在则追加）
  static Future<void> save(StudyOutput output) async {
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
      if (id != null && id == output.id) {
        next.add(jsonEncode(output.toJson()));
        replaced = true;
      } else {
        next.add(e);
      }
    }
    if (!replaced) next.add(jsonEncode(output.toJson()));

    await prefs.setStringList(key, next);
  }

  /// 删除一条成果（**只删数据**；图片与附件文件由调用方按需清理）
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
