/// 联网搜索数据存储服务
///
/// 管理从对话中自动沉淀的联网搜索数据。
/// - 存储格式：MD文件 + YAML front matter
/// - 自动沉淀的搜索数据默认权重 30，不进上下文
/// - 用户手动调整权重到 60 以上后，会进对话上下文
/// - 文件路径：tenants/{creditCode}/search_data/{时间戳}_{slug}.md
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../contracts/chat_service.dart';
import '../data/data_tags.dart';

/// 联网搜索数据项
class SearchDataItem {
  final String id; // 唯一ID（时间戳）
  final String title; // 标题
  final int weight; // 权重（0-100），默认30
  final List<String> tags; // 标签
  final String category; // 分类，固定"联网搜索"
  final String searchQuery; // 原始搜索关键词
  final String source; // 搜索来源（DSH搜索等）
  final String content; // MD正文（搜索提炼内容，输入模型的上下文）
  final List<SearchSource> sources; // 信源列表（备注，不进上下文）
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 统一数据标签（来源/业务等维度，可持续扩展）
  final DataTags dataTags;

  SearchDataItem({
    required this.id,
    required this.title,
    this.weight = 30,
    this.tags = const [],
    this.category = '联网搜索',
    required this.searchQuery,
    this.source = 'DSH搜索',
    required this.content,
    this.sources = const [],
    required this.createdAt,
    required this.updatedAt,
    DataTags? dataTags,
  }) : dataTags = dataTags ?? DataTags();

  /// 权重颜色
  Color get weightColor {
    if (weight >= 80) return const Color(0xFFDC2626);
    if (weight >= 60) return const Color(0xFFF59E0B);
    if (weight >= 40) return const Color(0xFF2563EB);
    return const Color(0xFF9CA3AF);
  }

  /// 是否进上下文（权重>=60）
  bool get inContext => weight >= 60;

  SearchDataItem copyWith({
    String? title,
    int? weight,
    List<String>? tags,
    String? searchQuery,
    String? source,
    String? content,
    List<SearchSource>? sources,
    DateTime? updatedAt,
    DataTags? dataTags,
  }) {
    return SearchDataItem(
      id: id,
      title: title ?? this.title,
      weight: weight ?? this.weight,
      tags: tags ?? this.tags,
      category: category,
      searchQuery: searchQuery ?? this.searchQuery,
      source: source ?? this.source,
      content: content ?? this.content,
      sources: sources ?? this.sources,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      dataTags: dataTags ?? this.dataTags,
    );
  }
}

/// 联网搜索数据存储服务
class SearchDataStore {
  /// 默认权重
  static const int defaultWeight = 30;

  /// 进上下文的权重阈值
  static const int contextThreshold = 60;

  /// 获取搜索数据存储目录
  static Future<String> _dir(String tenantId) async {
    final docDir = await getApplicationDocumentsDirectory();
    final dir = p.join(docDir.path, 'tenants', tenantId, 'search_data');
    await Directory(dir).create(recursive: true);
    return dir;
  }

  /// 生成slug（从标题简化）
  static String _slugify(String text) {
    final cleaned = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w一-龥]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
    return cleaned.isEmpty
        ? 'search'
        : cleaned.substring(0, cleaned.length > 30 ? 30 : cleaned.length);
  }

  /// 解析YAML front matter和MD内容
  static SearchDataItem? _parseFile(File file) {
    try {
      final content = file.readAsStringSync();
      final id = p.basenameWithoutExtension(file.path);

      // 解析YAML front matter
      final yamlMatch = RegExp(r'^---\s*\n([\s\S]*?)\n---\s*\n?([\s\S]*)')
          .firstMatch(content);
      if (yamlMatch == null) return null;

      final yamlStr = yamlMatch.group(1)!;
      final body = yamlMatch.group(2) ?? '';

      // 简单YAML解析
      final yaml = <String, String>{};
      for (final line in yamlStr.split('\n')) {
        final idx = line.indexOf(':');
        if (idx > 0) {
          final key = line.substring(0, idx).trim();
          final value = line
              .substring(idx + 1)
              .trim()
              .replaceAll(RegExp('^["\']|["\']\$'), '');
          yaml[key] = value;
        }
      }

      // 解析信源列表
      List<SearchSource> sources = [];
      final sourcesJson = yaml['sources'];
      if (sourcesJson != null && sourcesJson.isNotEmpty) {
        try {
          final list = jsonDecode(sourcesJson) as List;
          sources = list
              .map((e) => SearchSource(
                    title: (e as Map)['title']?.toString() ?? '',
                    url: e['url']?.toString() ?? '',
                  ))
              .toList();
        } catch (_) {}
      }

      return SearchDataItem(
        id: id,
        title: yaml['title'] ?? '未命名搜索',
        weight: int.tryParse(yaml['weight'] ?? '30') ?? 30,
        tags: (yaml['tags'] ?? '')
            .split(RegExp(r'[,，]'))
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.trim())
            .toList(),
        category: yaml['category'] ?? '联网搜索',
        searchQuery: yaml['search_query'] ?? '',
        source: yaml['source'] ?? 'DSH搜索',
        content: body,
        sources: sources,
        createdAt:
            DateTime.tryParse(yaml['created_at'] ?? '') ?? DateTime.now(),
        updatedAt:
            DateTime.tryParse(yaml['updated_at'] ?? '') ?? DateTime.now(),
        // 统一数据标签（来源/业务等维度）
        dataTags: DataTags.fromJsonString(yaml['data_tags']),
      );
    } catch (e) {
      return null;
    }
  }

  /// 序列化为MD文件内容
  static String _serialize(SearchDataItem item) {
    final buf = StringBuffer();
    buf.writeln('---');
    buf.writeln('title: ${item.title}');
    buf.writeln('weight: ${item.weight}');
    buf.writeln('tags: ${item.tags.join(", ")}');
    buf.writeln('category: ${item.category}');
    buf.writeln('search_query: ${item.searchQuery}');
    buf.writeln('source: ${item.source}');
    if (!item.dataTags.isEmpty) {
      buf.writeln('data_tags: ${item.dataTags.toJsonString()}');
    }
    if (item.sources.isNotEmpty) {
      final sourcesJson = jsonEncode(
          item.sources.map((s) => {'title': s.title, 'url': s.url}).toList());
      buf.writeln('sources: $sourcesJson');
    }
    buf.writeln('created_at: ${item.createdAt.toIso8601String()}');
    buf.writeln('updated_at: ${item.updatedAt.toIso8601String()}');
    buf.writeln('---');
    buf.write(item.content);
    return buf.toString();
  }

  /// 列出所有搜索数据（按时间倒序）
  static Future<List<SearchDataItem>> listAll(String tenantId) async {
    final dir = Directory(await _dir(tenantId));
    if (!await dir.exists()) return [];

    final items = <SearchDataItem>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.md')) {
        final item = _parseFile(entity);
        if (item != null) items.add(item);
      }
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  /// 获取单条搜索数据
  static Future<SearchDataItem?> getById(String tenantId, String id) async {
    final dir = await _dir(tenantId);
    final file = File(p.join(dir, '$id.md'));
    if (!await file.exists()) return null;
    return _parseFile(file);
  }

  /// 创建搜索数据（自动沉淀）
  static Future<SearchDataItem> create({
    required String tenantId,
    required String title,
    required String searchQuery,
    required String content,
    List<SearchSource> sources = const [],
    String source = 'DSH搜索',
    List<String> tags = const [],
    int weight = defaultWeight,
  }) async {
    final now = DateTime.now();
    final id = now.millisecondsSinceEpoch.toString();
    final slug = _slugify(title);
    final fileName = '${id}_$slug.md';
    final dir = await _dir(tenantId);
    final file = File(p.join(dir, fileName));

    // 业务标签：根据 标题/搜索词/内容 关键词匹配（零模型成本，用户可手改）
    final businessTags =
        DataBusinessTag.matchFromText('$title $searchQuery $content');

    final item = SearchDataItem(
      id: id,
      title: title,
      weight: weight,
      tags: tags,
      searchQuery: searchQuery,
      source: source,
      content: content,
      sources: sources,
      createdAt: now,
      updatedAt: now,
      // 统一标签：来源标签固定为"联网搜索"（业务标签由关键词规则/提炼时打）
      dataTags: DataTags()
        ..set(DataTagDimension.source, [DataSourceTag.webSearch])
        ..set(DataTagDimension.business, businessTags),
    );

    await file.writeAsString(_serialize(item));
    return item;
  }

  /// 更新搜索数据
  static Future<SearchDataItem> update(
      String tenantId, SearchDataItem item) async {
    final dir = await _dir(tenantId);
    // 找到对应的文件（文件名包含id前缀）
    File? targetFile;
    await for (final entity in Directory(dir).list()) {
      if (entity is File && p.basename(entity.path).startsWith('${item.id}_')) {
        targetFile = entity;
        break;
      }
    }

    final updated = item.copyWith(updatedAt: DateTime.now());
    if (targetFile != null) {
      await targetFile.writeAsString(_serialize(updated));
    } else {
      // 文件不存在，重新创建
      final slug = _slugify(updated.title);
      final fileName = '${updated.id}_$slug.md';
      await File(p.join(dir, fileName)).writeAsString(_serialize(updated));
    }
    return updated;
  }

  /// 只更新权重（列表页快速操作）
  static Future<SearchDataItem?> updateWeight(
      String tenantId, String id, int weight) async {
    final item = await getById(tenantId, id);
    if (item == null) return null;
    return update(tenantId, item.copyWith(weight: weight));
  }

  /// 删除搜索数据
  static Future<bool> delete(String tenantId, String id) async {
    final dir = await _dir(tenantId);
    await for (final entity in Directory(dir).list()) {
      if (entity is File && p.basename(entity.path).startsWith('${id}_')) {
        await entity.delete();
        return true;
      }
    }
    return false;
  }

  /// 获取权重>=阈值的搜索数据（用于注入上下文）
  static Future<List<SearchDataItem>> getContextItems(String tenantId) async {
    final all = await listAll(tenantId);
    return all.where((item) => item.weight >= contextThreshold).toList();
  }
}
