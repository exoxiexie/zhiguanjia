/// 记忆层存储服务
///
/// 记忆文件格式：MD + YAML front matter
/// 存储位置：tenants/{手机号}/memory/*.md
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/data_tags.dart';
import 'tenant_storage.dart';

/// 记忆条目
class MemoryItem {
  final String id; // 文件名（不含 .md）
  String title;
  int weight; // 0-100，默认50
  List<String> tags;
  String category;
  String source; // session提炼 / 手动添加 / 文件导入
  DateTime createdAt;
  DateTime updatedAt;
  String content; // MD 正文

  /// 统一数据标签（来源/业务等维度，可持续扩展）
  DataTags dataTags;

  MemoryItem({
    required this.id,
    required this.title,
    this.weight = 50,
    List<String>? tags,
    this.category = '未分类',
    this.source = '手动添加',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.content = '',
    DataTags? dataTags,
  })  : tags = tags ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        dataTags = dataTags ?? DataTags();

  /// 从 MD 文件内容解析
  factory MemoryItem.parse(String id, String fileContent) {
    final lines = fileContent.split('\n');
    var contentStart = 0;
    final frontMatter = <String, String>{};

    if (lines.isNotEmpty && lines[0].trim() == '---') {
      for (var i = 1; i < lines.length; i++) {
        if (lines[i].trim() == '---') {
          contentStart = i + 1;
          break;
        }
        final idx = lines[i].indexOf(':');
        if (idx > 0) {
          final key = lines[i].substring(0, idx).trim();
          final value = lines[i].substring(idx + 1).trim();
          frontMatter[key] = value;
        }
      }
    }

    final content = contentStart < lines.length
        ? lines.sublist(contentStart).join('\n').trim()
        : '';

    return MemoryItem(
      id: id,
      title: frontMatter['title'] ?? id,
      weight: int.tryParse(frontMatter['weight'] ?? '50') ?? 50,
      tags: (frontMatter['tags'] ?? '')
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      category: frontMatter['category'] ?? '未分类',
      source: frontMatter['source'] ?? '手动添加',
      createdAt:
          DateTime.tryParse(frontMatter['created_at'] ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(frontMatter['updated_at'] ?? '') ?? DateTime.now(),
      content: content,
      // 统一数据标签（来源/业务等维度）
      dataTags: DataTags.fromJsonString(frontMatter['data_tags']),
    );
  }

  /// 序列化为 MD 文件内容
  String toFileContent() {
    final now = DateTime.now().toIso8601String().substring(0, 19);
    final tagsStr = tags.join(', ');
    final dataTagsStr = dataTags.isEmpty ? '' : dataTags.toJsonString();
    return '''---
title: $title
weight: $weight
tags: $tagsStr
category: $category
source: $source
${dataTagsStr.isEmpty ? '' : 'data_tags: $dataTagsStr\n'}created_at: ${createdAt.toIso8601String().substring(0, 19)}
updated_at: $now
---

$content
''';
  }

  /// 安全的文件名
  static String safeId(String title) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final clean = title
        .replaceAll(RegExp(r'[^\w\u4e00-\u9fa5]'), '_')
        .substring(0, title.length > 20 ? 20 : title.length);
    return '${now}_$clean';
  }
}

/// 记忆层存储服务
class MemoryStore {
  /// 获取指定租户的所有记忆文件
  static Future<List<MemoryItem>> listAll(String tenantId) async {
    final dir = await TenantStorage.getMemoryDir(tenantId);
    final items = <MemoryItem>[];

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.md')) {
        try {
          final id = p.basenameWithoutExtension(entity.path);
          final content = await entity.readAsString();
          items.add(MemoryItem.parse(id, content));
        } catch (_) {
          // 跳过解析失败的文件
        }
      }
    }

    // 按更新时间倒序
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items;
  }

  /// 读取单条记忆
  static Future<MemoryItem?> read(String tenantId, String id) async {
    final dir = await TenantStorage.getMemoryDir(tenantId);
    final file = File(p.join(dir.path, '$id.md'));
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    return MemoryItem.parse(id, content);
  }

  /// 保存记忆（新建或更新）
  static Future<void> save(String tenantId, MemoryItem item) async {
    final dir = await TenantStorage.getMemoryDir(tenantId);
    final file = File(p.join(dir.path, '${item.id}.md'));
    item.updatedAt = DateTime.now();
    // 统一标签：来源标签固定为"对话记忆"（业务标签由提炼/编辑时打）
    if (!item.dataTags.has(DataTagDimension.source)) {
      item.dataTags.set(DataTagDimension.source, [DataSourceTag.chatMemory]);
    }
    await file.writeAsString(item.toFileContent());
  }

  /// 删除记忆
  static Future<void> delete(String tenantId, String id) async {
    final dir = await TenantStorage.getMemoryDir(tenantId);
    final file = File(p.join(dir.path, '$id.md'));
    if (await file.exists()) {
      await file.delete();
    }
  }
}
