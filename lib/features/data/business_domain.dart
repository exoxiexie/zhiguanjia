/// 任务域中心注册表 —— 三位一体（职管家 · 个人职业版）
///
/// 任务智能体 ↔ 数据标签 ↔ 数据表 一一映射，统一由 [BusinessDomain] 注册：
/// - [id]：统一 ID（如 'resume'），三者共用
/// - [tag]：任务标签值（与 DataBusinessTag 完全一致）
/// - [table]：任务域数据表名（如 'resume_data'）
/// - UI 元数据（图标/颜色/副标题）与角色定义（职责/材料）也注册于此，
///   智能体列表、标签、数据表、角色提示词全部从这里派生，保证一致。
///
/// 三个都可以随时增长：新增任务域时只需在此注册一条，
/// 建表、智能体卡片、标签、上下文注入、按任务视图自动跟随。
///
/// 说明：底层注册表机制与智懂你（企业版）完全一致，仅域数据不同。
/// 职业任务域（职业规划/简历/求职/技能/薪酬/职场法律/职业健康等）
/// 待产品定义后在此填充，MVP 阶段列表为空（首页任务智能体区域为空）。
library;

import 'package:flutter/material.dart';

/// 业务域定义（三位一体注册单元）
///
/// 历史命名沿用 BusinessDomain；在职管家中表示一个「职业任务域」，
/// 与企业版的业务域共用同一套注册表机制。
class BusinessDomain {
  /// 统一 ID（贯穿智能体/标签/数据表）
  final String id;

  /// 业务标签值（= DataBusinessTag 对应常量）
  final String tag;

  /// 业务域数据表名（SQLite）
  final String table;

  /// 智能体副标题（首页卡片展示）
  final String subtitle;

  /// 智能体图标
  final IconData icon;

  /// 智能体主题色
  final Color color;

  /// 职责范围（角色系统提示词用）
  final String scope;

  /// 需要用户提供的材料（角色系统提示词引导用）
  final String need;

  const BusinessDomain({
    required this.id,
    required this.tag,
    required this.table,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.scope,
    required this.need,
  });

  /// 按标签值查找
  static BusinessDomain? byTag(String tag) {
    for (final d in kBusinessDomains) {
      if (d.tag == tag) return d;
    }
    return null;
  }

  /// 按统一ID查找
  static BusinessDomain? byId(String id) {
    for (final d in kBusinessDomains) {
      if (d.id == id) return d;
    }
    return null;
  }
}

/// 全部职业任务域（顺序即展示顺序，三位一体）
///
/// MVP 阶段为空：首页「任务智能体」区域不展示卡片。
/// 后续按产品定义逐条注册，例如：
///   career_plan(职业规划) / resume(简历) / job_hunting(求职面试) /
///   skill_learning(技能学习) / salary(薪酬谈判) /
///   workplace_law(职场法律) / career_health(职业健康) 等。
const List<BusinessDomain> kBusinessDomains = [
  // 暂无注册的职业任务域，待填充。
];
