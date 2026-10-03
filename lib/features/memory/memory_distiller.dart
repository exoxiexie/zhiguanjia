/// 对话记忆自动提炼服务
///
/// 对话结束后（AI 回复完成），调用 DeepSeek 把对话内容提炼为结构化记忆，
/// 自动去重合并，写入记忆层（MD + YAML，与手动添加共用 MemoryStore）。
///
/// 提炼结果由模型以严格 JSON 输出：
/// {
///   "has_memory": true/false,        // 是否有值得长期记住的内容
///   "update_id": "已有记忆id",        // 与已有记忆重复时返回，用于合并更新
///   "title": "简洁标题",
///   "weight": 0-100,                 // 重要程度
///   "tags": ["标签"],
///   "category": "分类",
///   "business_tags": ["业务标签"],    // 0-3个，从12个业务域中选择
///   "content": "Markdown 正文（要点式）"
/// }
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../contracts/api_config.dart';
import '../data/business_domain.dart';
import '../data/data_tags.dart';
import '../storage/memory_store.dart';

/// 记忆提炼服务
class MemoryDistiller {
  /// 最近一次错误信息（供 UI 层展示具体错误原因）
  static String? lastError;

  /// 提炼用模型：DeepSeek V4.1 Flash（快、便宜，适合结构化提炼任务）
  static const String _model = 'deepseek-flash';

  /// 输入对话文本截断上限（字符数，控制 token 成本）
  static const int _maxInputChars = 12000;

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 60),
  ));

  /// 提炼一段对话并写入记忆层。
  ///
  /// - [conversationText]：对话文本（"【用户】…【智懂你】…"格式）
  /// - [forceSave]：强制保存（手动提炼时使用），即使 AI 判断 has_memory=false 也保存
  /// - [source]：记忆来源，"会话提炼"（自动）或"手动提炼"（手动）
  /// - 已有记忆会作为去重依据传给模型；命中时更新旧记忆而非新建
  /// - 全程不抛异常：任何失败都静默降级（返回 false），不打扰对话
  static Future<bool> distillAndSave({
    required String tenantId,
    required String conversationText,
    bool forceSave = false,
    String source = '会话提炼',
  }) async {
    lastError = null;
    try {
      // 已有记忆（id + 标题），用于去重合并
      final existing = await MemoryStore.listAll(tenantId);
      final existingInfo = existing.map((m) => '${m.id}|${m.title}').join('\n');
      final input = conversationText.length <= _maxInputChars
          ? conversationText
          : conversationText
              .substring(conversationText.length - _maxInputChars);

      final resp = await _dio.post(
        ApiConfig.chatCompletionsUrl,
        data: {
          'model': _model,
          'max_tokens': 4096,
          'temperature': 0.3,
          'messages': [
            {
              'role': 'system',
              'content': '你是「职管家」AI 职业管家的记忆提炼模块。你的任务是从用户与 AI 职业管家的对话中，'
                  '提炼出值得长期记住的信息，保存为个人职业记忆。\n\n'
                  '值得提炼的信息包括：\n'
                  '- 个人职业关键事实与决策（职业目标、岗位方向、技能栈、求职意向、offer、薪酬等）\n'
                  '- 用户的长期偏好与要求（沟通风格、工作方式、注意事项等）\n'
                  '- 讨论中形成的明确结论与方案要点\n\n'
                  '不值得提炼的信息：\n'
                  '- 日常寒暄、无实质结论的闲聊、单一事实问答\n\n'
                  '输出要求（严格遵守）：\n'
                  '- 只输出一个 JSON 对象，不要输出任何其他文字，不要使用 Markdown 围栏\n'
                  '- 格式：{"has_memory": true或false, "update_id": "与已有记忆重复时填该记忆id，否则不填", '
                  '"title": "15字以内的简洁标题", "weight": 0到100的整数（越重要分越高）, '
                  '"tags": ["标签1", "标签2"], "category": "分类（如：职业规划/简历求职/技能学习/薪酬/用户偏好/其他）", '
                  '"business_tags": ["任务标签"], '
                  '"content": "Markdown正文，要点式，简洁完整，包含关键结论与细节"}\n'
                  '- business_tags：标注本条记忆最相关的职业任务标签（如职业规划、简历、求职面试、技能、薪酬等），'
                  '最多3个，无法确定归属时可为空数组[]\n'
                  '- 如果对话没有值得记住的内容，has_memory 必须为 false，其余字段可省略\n'
                  '- update_id 只能从【已有记忆】列表中选择，用于把新内容合并进旧记忆（保留旧记忆 id），'
                  '若不存在重复记忆则不填',
            },
            {
              'role': 'user',
              'content':
                  '【已有记忆】\n${existingInfo.isEmpty ? '（暂无）' : existingInfo}\n\n'
                      '【对话内容】\n$input',
            },
          ],
        },
        options: Options(
          headers: {
            'X-Proxy-Token': ApiConfig.proxyToken,
            'Content-Type': 'application/json',
          },
        ),
      );

      final choices = resp.data?['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        lastError = '模型返回为空，choices=null';
        return false;
      }
      final text = (choices[0] as Map)['message']?['content']?.toString() ?? '';
      final result = parseResult(text);
      // 自动提炼时，解析失败或 has_memory=false 则不保存；手动提炼（forceSave）时强制保存
      if (result == null && !forceSave) {
        lastError =
            '解析模型输出失败，返回内容：${text.substring(0, text.length > 200 ? 200 : text.length)}';
        return false;
      }
      if (result != null && result['has_memory'] != true && !forceSave)
        return false;

      // ── 合并更新：命中已有记忆则更新，否则新建 ──
      final updateId = result?['update_id']?.toString() ?? '';
      MemoryItem? existingItem;
      if (updateId.isNotEmpty) {
        for (final m in existing) {
          if (m.id == updateId) {
            existingItem = m;
            break;
          }
        }
      }

      final title = result?['title']?.toString().trim().isNotEmpty == true
          ? result!['title']!.toString().trim()
          : '对话记忆';
      final weight = int.tryParse(result?['weight']?.toString() ?? '') ?? 50;
      final tags = _parseTags(result?['tags']);
      final category = result?['category']?.toString().trim().isNotEmpty == true
          ? result!['category']!.toString().trim()
          : '未分类';
      var content = result?['content']?.toString().trim() ?? '';

      // 手动提炼（forceSave）时，如果 AI 没有输出内容或解析失败，用对话摘要作为默认内容
      if (forceSave && content.isEmpty) {
        final summary =
            input.length > 500 ? '${input.substring(0, 500)}...' : input;
        content = '## 对话摘要\n\n$summary';
      }

      // forceSave 时如果没有标签，给一个默认标签
      if (forceSave && tags.isEmpty) {
        tags.add('对话提炼');
      }

      // 业务标签：只保留 12 个合法业务域值，其余丢弃
      final businessTags = _parseBusinessTags(result?['business_tags']);

      if (existingItem != null) {
        existingItem.title = title;
        existingItem.weight = weight.clamp(0, 100);
        existingItem.tags = tags;
        existingItem.category = category;
        existingItem.content = content;
        existingItem.source = source;
        if (businessTags.isNotEmpty) {
          existingItem.dataTags.set(DataTagDimension.business, businessTags);
        }
        await MemoryStore.save(tenantId, existingItem);
      } else {
        final item = MemoryItem(
          id: MemoryItem.safeId(title),
          title: title,
          weight: weight.clamp(0, 100),
          tags: tags,
          category: category,
          source: source,
          content: content,
        );
        if (businessTags.isNotEmpty) {
          item.dataTags.set(DataTagDimension.business, businessTags);
        }
        await MemoryStore.save(tenantId, item);
      }
      return true;
    } catch (e) {
      // 提炼失败打印错误日志，方便排查
      debugPrint('MemoryDistiller 提炼失败: $e');
      lastError = '异常：$e';
      return false;
    }
  }

  /// 解析模型输出的提炼结果 JSON（容错：剥掉 Markdown 围栏、截取 JSON 区间）
  static Map<String, dynamic>? parseResult(String raw) {
    if (raw.trim().isEmpty) return null;
    var text = raw.trim();
    // 去掉 ```json ... ``` 围栏
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
    if (fence != null) {
      text = fence.group(1)!.trim();
    }
    // 截取第一个 { 到最后一个 } 之间的内容
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    text = text.substring(start, end + 1);
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      return null;
    }
    return null;
  }

  /// 解析 tags 字段（字符串或数组均可）
  static List<String> _parseTags(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return value
        .toString()
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// 解析任务标签：只保留已注册职业任务域的合法值（去重、限 3 个）。
  /// 任务域注册表为空时（MVP），不保留任何任务标签；注册职业域后自动生效。
  static List<String> _parseBusinessTags(dynamic value) {
    final valid = kBusinessDomains.map((d) => d.tag).toSet();
    final raw = _parseTags(value);
    final result = <String>[];
    for (final t in raw) {
      if (valid.contains(t) && !result.contains(t)) {
        result.add(t);
      }
      if (result.length >= 3) break;
    }
    return result;
  }
}
