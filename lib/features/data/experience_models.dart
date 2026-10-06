/// 职业经历：数据模型 + 字段描述表（职管家 · 个人职业版）
///
/// **为什么用「字段描述表 + 通用实体」而不是写三个类、三套页面**：
/// 教育 / 工作 / 培训三类经历结构同源 —— 都是「一组字段 + 起止时间」，
/// 差异只在**字段清单**。把字段清单抽成描述表（[ExperienceKind.fields]）之后：
/// 1. 详情页、编辑表单、卡片摘要全部由描述表驱动，**一份 UI 服务三类经历**，
///    不会出现"改了一个类型忘了改另一个"；
/// 2. 将来要加「项目经历」「证书」「语言能力」等新类型，只需在
///    [ExperienceKind.all] 里加一条描述，页面与存储零改动 ——
///    与首页「专业智能体」的三位一体注册表是同一个思路。
///
/// **字段类型**（[ExperienceFieldType]）决定编辑页渲染什么控件、
/// 详情页怎么排版；新增类型时优先复用这四种，不要随意扩枚举。
library;

import 'package:flutter/material.dart';

/// 字段控件类型
enum ExperienceFieldType {
  /// 单行文本
  text,

  /// 多行文本（工作内容 / 培训内容）
  multiline,

  /// 枚举选择（学历、学习形式等），用 [ExperienceField.options] 渲染选项
  select,

  /// 年月（存 `yyyy-MM`），点击调系统日期选择器
  month,
}

/// 一个字段的描述
class ExperienceField {
  /// 存储键（稳定不变，改动会让老数据失联）
  final String key;

  /// 显示名（表单标签、详情页标签）
  final String label;

  /// 输入提示
  final String hint;

  final ExperienceFieldType type;

  /// [ExperienceFieldType.select] 的候选项
  final List<String> options;

  /// 是否必填（保存时校验）
  final bool required;

  /// 是否为主字段 —— 卡片标题用它
  final bool primary;

  const ExperienceField({
    required this.key,
    required this.label,
    this.hint = '',
    this.type = ExperienceFieldType.text,
    this.options = const [],
    this.required = false,
    this.primary = false,
  });
}

/// 一类经历（教育 / 工作 / 培训）的完整描述
class ExperienceKind {
  /// 稳定 id：同时作为存储里的类型标识
  final String id;

  /// 页面标题 / 卡片名称
  final String label;

  /// 通栏卡片图标与配色
  final IconData icon;
  final Color color;

  /// 一句话说明（详情页空态用）
  final String subtitle;

  /// 字段清单（顺序即表单顺序）
  final List<ExperienceField> fields;

  const ExperienceKind({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.subtitle,
    required this.fields,
  });

  /// 主字段（卡片标题）
  ExperienceField get primaryField =>
      fields.firstWhere((f) => f.primary, orElse: () => fields.first);

  /// 起始时间字段（按字段顺序取第一个年月字段）
  ExperienceField? get startField {
    for (final f in fields) {
      if (f.type == ExperienceFieldType.month) return f;
    }
    return null;
  }

  /// 结束时间字段（取第二个年月字段，无则为 null）
  ExperienceField? get endField {
    var seen = 0;
    for (final f in fields) {
      if (f.type == ExperienceFieldType.month) {
        seen++;
        if (seen == 2) return f;
      }
    }
    return null;
  }

  // ── 三类经历 ───────────────────────────────────────────────

  /// 教育经历：学校 / 专业 / 学历 / 起止
  static const ExperienceKind education = ExperienceKind(
    id: 'education',
    label: '教育经历',
    icon: Icons.school_outlined,
    color: Color(0xFF3B7CF6),
    subtitle: '就读院校、专业与学历，按时间倒序排列',
    fields: [
      ExperienceField(
        key: 'school',
        label: '学校名称',
        hint: '如：北京大学',
        required: true,
        primary: true,
      ),
      ExperienceField(key: 'major', label: '专业', hint: '如：计算机科学与技术'),
      ExperienceField(
        key: 'degree',
        label: '学历',
        type: ExperienceFieldType.select,
        options: ['高中及以下', '中专', '大专', '本科', '硕士', '博士'],
      ),
      ExperienceField(
        key: 'start',
        label: '入学时间',
        type: ExperienceFieldType.month,
      ),
      ExperienceField(
        key: 'end',
        label: '毕业时间',
        hint: '尚未毕业可留空',
        type: ExperienceFieldType.month,
      ),
    ],
  );

  /// 工作经历：公司 / 职位 / 起止 / 工作内容
  static const ExperienceKind work = ExperienceKind(
    id: 'work',
    label: '工作经历',
    icon: Icons.work_outline,
    color: Color(0xFF16B89C),
    subtitle: '任职公司、岗位与工作内容，按时间倒序排列',
    fields: [
      ExperienceField(
        key: 'company',
        label: '公司名称',
        hint: '如：腾讯科技（深圳）有限公司',
        required: true,
        primary: true,
      ),
      ExperienceField(key: 'position', label: '职位名称', hint: '如：高级产品经理'),
      ExperienceField(
        key: 'start',
        label: '入职时间',
        type: ExperienceFieldType.month,
      ),
      ExperienceField(
        key: 'end',
        label: '离职时间',
        hint: '在职中可留空',
        type: ExperienceFieldType.month,
      ),
      ExperienceField(
        key: 'description',
        label: '工作内容',
        hint: '负责的职责、做过的项目、拿到的结果…',
        type: ExperienceFieldType.multiline,
      ),
    ],
  );

  /// 培训经历：机构 / 课程 / 起止 / 培训内容
  static const ExperienceKind training = ExperienceKind(
    id: 'training',
    label: '培训经历',
    icon: Icons.menu_book_outlined,
    color: Color(0xFFFD5C13),
    subtitle: '参加过的培训课程与认证，按时间倒序排列',
    fields: [
      ExperienceField(
        key: 'org',
        label: '培训机构',
        hint: '如：某某职业培训学校',
        required: true,
        primary: true,
      ),
      ExperienceField(key: 'course', label: '培训课程', hint: '如：PMP 项目管理认证'),
      ExperienceField(
        key: 'start',
        label: '开始时间',
        type: ExperienceFieldType.month,
      ),
      ExperienceField(
        key: 'end',
        label: '结束时间',
        type: ExperienceFieldType.month,
      ),
      ExperienceField(
        key: 'certificate',
        label: '所获证书',
        hint: '如：PMP 证书（证书编号）',
      ),
      ExperienceField(
        key: 'description',
        label: '培训内容',
        hint: '课程要点、学习成果…',
        type: ExperienceFieldType.multiline,
      ),
    ],
  );

  /// 全部类型（数据页通栏卡片按此顺序生成）
  static const List<ExperienceKind> all = [education, work, training];

  static ExperienceKind? byId(String id) {
    for (final k in all) {
      if (k.id == id) return k;
    }
    return null;
  }
}

/// 一条经历（通用实体：类型 + 字段值表）
///
/// 值统一按字符串存：[ExperienceFieldType.month] 存 `yyyy-MM`，
/// 其余存原始文本。空值一律存空串（而不是缺键），读取端无需判 null。
class ExperienceEntry {
  final String id;
  final String kindId;
  final Map<String, String> values;
  final int createdAt;
  final int updatedAt;

  const ExperienceEntry({
    required this.id,
    required this.kindId,
    required this.values,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 取字段值（去首尾空白，缺失返回空串）
  String v(String key) => (values[key] ?? '').trim();

  /// 主字段值（卡片标题）
  String primaryOf(ExperienceKind kind) => v(kind.primaryField.key);

  /// 起始时间 `yyyy-MM`（空串表示未填）
  String startOf(ExperienceKind kind) {
    final f = kind.startField;
    return f == null ? '' : v(f.key);
  }

  /// 结束时间 `yyyy-MM`（空串表示未填/至今）
  String endOf(ExperienceKind kind) {
    final f = kind.endField;
    return f == null ? '' : v(f.key);
  }

  /// 起止时间展示：`2020.09 - 2024.06`；结束为空时显示「至今」；两者都空返回空串
  String rangeText(ExperienceKind kind) {
    final s = formatMonth(startOf(kind));
    final e = formatMonth(endOf(kind));
    if (s.isEmpty && e.isEmpty) return '';
    if (s.isEmpty) return '— $e';
    return '$s - ${e.isEmpty ? '至今' : e}';
  }

  /// 排序键：起始时间倒序（由近及远），未填的排最后
  String get sortKey {
    final raw = values['start'] ?? '';
    return raw.isEmpty ? '0000-00' : raw;
  }

  ExperienceEntry copyWith({
    String? kindId,
    Map<String, String>? values,
    int? updatedAt,
  }) =>
      ExperienceEntry(
        id: id,
        kindId: kindId ?? this.kindId,
        values: values ?? this.values,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  factory ExperienceEntry.fromJson(Map<String, dynamic> json) => ExperienceEntry(
        id: json['id']?.toString() ?? '',
        kindId: json['kind']?.toString() ?? '',
        values: {
          for (final e
              in ((json['values'] as Map?) ?? const <String, dynamic>{})
                  .entries)
            e.key.toString(): e.value?.toString() ?? '',
        },
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
        updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kindId,
        'values': values,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

/// `yyyy-MM` → `yyyy.MM`（不合规的原文返回，避免吃掉用户输入）
String formatMonth(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return '';
  final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(t);
  if (m == null) return t;
  return '${m.group(1)}.${m.group(2)}';
}

/// `yyyy-MM` → DateTime（用于日期选择器定位初始值），解析失败返回 null
DateTime? parseMonth(String raw) {
  final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(raw.trim());
  if (m == null) return null;
  final y = int.tryParse(m.group(1)!);
  final mo = int.tryParse(m.group(2)!);
  if (y == null || mo == null || mo < 1 || mo > 12) return null;
  return DateTime(y, mo, 1);
}

/// DateTime → `yyyy-MM`
String toMonthValue(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';
