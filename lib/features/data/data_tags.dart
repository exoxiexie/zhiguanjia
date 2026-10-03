/// 统一数据标签体系
///
/// 每一条沉淀数据都挂载一套标签（DataTags），按"维度"组织：
/// - source（来源）：信息公开 / 对话记忆 / 本地私有 / 联网搜索 / 外接应用
/// - business（业务）：贷款 / 工商 / 税务 / 司法 / 信用 / 财务 / 知识产权 /
///   政策申报 / 项目审批 / 法律 / 社保 / 供应链
///
/// 维度可**持续扩展**：将来需要新的查询维度（如时间、人员、项目等），
/// 只需新增维度常量并给数据打对应标签，无需改动数据结构。
/// 标签体系在数据层维护，前台 UI 按需读取展示。
library;

import 'dart:convert';

/// 标签维度常量（可持续扩展）
class DataTagDimension {
  /// 数据来源维度
  static const String source = 'source';

  /// 业务维度
  static const String business = 'business';

  const DataTagDimension._();
}

/// 数据来源标签（五大类）
class DataSourceTag {
  static const String publicInfo = '信息公开';
  static const String chatMemory = '对话记忆';
  static const String localPrivate = '本地私有';
  static const String webSearch = '联网搜索';
  static const String externalApp = '外接应用';

  const DataSourceTag._();
}

/// 任务标签（对应任务智能体，职管家 · 个人职业版）
///
/// MVP 阶段任务域注册表 kBusinessDomains 为空，故标签候选与关键词规则也为空，
/// 不对个人数据自动打企业类标签。后续定义职业任务域（职业规划/简历/求职/技能等）
/// 时，在此补充对应常量、all 列表与关键词规则。
class DataBusinessTag {
  // 职业任务标签常量将随职业域定义补充，例如：
  // static const String careerPlan = '职业规划';
  // static const String resume = '简历';
  // static const String jobHunting = '求职面试';
  // static const String skillLearning = '技能学习';
  // static const String salary = '薪酬谈判';
  // static const String workplaceLaw = '职场法律';
  // static const String careerHealth = '职业健康';

  /// 全部任务域标签（有序，与任务智能体展示顺序一致）；MVP 为空
  static const List<String> all = [];

  /// 关键词规则表：任务域 -> 触发关键词（用于零成本自动打标）；MVP 为空
  static const Map<String, List<String>> _keywordRules = {};

  /// 根据文本关键词匹配任务标签（零模型成本）。
  /// 命中多个任务域时全部返回（多对多）；匹配不到返回空。
  static List<String> matchFromText(String text) {
    if (text.isEmpty) return const [];
    final result = <String>[];
    _keywordRules.forEach((tag, keywords) {
      for (final kw in keywords) {
        if (text.contains(kw)) {
          result.add(tag);
          break;
        }
      }
    });
    return result;
  }

  const DataBusinessTag._();
}

/// 单条数据的标签容器：维度 -> 标签值列表
class DataTags {
  final Map<String, List<String>> _tags;

  DataTags([Map<String, List<String>>? tags]) : _tags = tags ?? {};

  /// 常量构造：直接传入 const 标签 Map（用于 const 数据定义，不可变）
  const DataTags.fromConst(Map<String, List<String>> tags) : _tags = tags;

  /// 是否没有任何标签
  bool get isEmpty => _tags.isEmpty;

  /// 是否包含某维度
  bool has(String dimension) => (_tags[dimension]?.isNotEmpty ?? false);

  /// 读取某维度的全部标签（不可变视图）
  List<String> of(String dimension) =>
      List.unmodifiable(_tags[dimension] ?? const []);

  /// 设置某维度标签（覆盖）
  void set(String dimension, List<String> values) {
    _tags[dimension] = List.of(values);
  }

  /// 向某维度添加一个标签（去重）
  void add(String dimension, String value) {
    final list = _tags.putIfAbsent(dimension, () => []);
    if (!list.contains(value)) list.add(value);
  }

  /// 序列化为 Map（用于 JSON / YAML / SQLite 列）
  Map<String, dynamic> toMap() =>
      _tags.map((k, v) => MapEntry(k, List<String>.of(v)));

  /// 从 Map 反序列化
  factory DataTags.fromMap(Map<String, dynamic>? map) {
    final tags = DataTags();
    if (map == null) return tags;
    map.forEach((dim, vals) {
      if (vals is List) {
        tags.set(dim, vals.whereType<String>().toList());
      }
    });
    return tags;
  }

  /// 序列化为 JSON 字符串（存 YAML / SQLite 文本列）
  String toJsonString() => jsonEncode(toMap());

  /// 从 JSON 字符串反序列化（解析失败返回空标签）
  factory DataTags.fromJsonString(String? json) {
    if (json == null || json.isEmpty) return DataTags();
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map) {
        return DataTags.fromMap(decoded.cast<String, dynamic>());
      }
    } catch (_) {
      // 标签损坏不影响数据读取
    }
    return DataTags();
  }
}
