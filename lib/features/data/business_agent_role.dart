/// 业务智能体角色定义
///
/// 每个业务智能体都有一个独立的角色系统提示词：
/// - 我是谁（该业务域的智能体身份）
/// - 我能解决什么（职责范围）
/// - 你的数据现状（该业务标签下已沉淀的数据）
/// - 我还需要什么（引导用户提供更多材料，让分析更精准）
///
/// 即使业务域数据为 0，智能体也能基于角色定义回答"你是谁"、
/// "你能做什么"等问题，而不是退回通用身份回答。
///
/// 角色定义（职责/材料）来自三位一体注册表 [BusinessDomain]，
/// 保证与智能体列表、业务标签、数据表一致。
library;

import 'business_domain.dart';

/// 业务智能体角色服务
class BusinessAgentRole {
  /// 组装某业务智能体的完整系统提示词（角色定义 + 业务域数据现状）
  static String buildSystemPrompt(String businessTag, String contextText) {
    final def = BusinessDomain.byTag(businessTag);
    final name = def?.tag ?? businessTag;
    final scope = def?.scope ?? '该职业任务域相关的专业分析与建议';
    final need = def?.need ?? '相关职业资料';
    final hasData = contextText.isNotEmpty &&
        !contextText.contains('当前暂无沉淀数据') &&
        !contextText.trim().isEmpty &&
        contextText.trim() != '【任务域上下文：$businessTag】';

    final buf = StringBuffer();
    buf.writeln('你是「职管家」AI 职业管家的【$name】任务智能体，'
        '专注为当前个人用户提供$name领域的专业职业管家服务。\n');
    buf.writeln('【你能帮助用户解决】\n$scope\n');
    buf.writeln('【当前个人$name任务域数据现状】\n'
        '${hasData ? contextText : '暂无沉淀数据。你可以向用户说明目前可用的数据情况，'
            '并引导其补充相关职业资料。'}');
    buf.writeln('\n【你的工作方式】\n'
        '- 回答用户问题时，优先结合用户的职业身份画像与以上任务域数据进行分析，给出针对性建议\n'
        '- 数据不足时，明确告诉用户还需要补充哪些材料（如：$need），'
        '不要凭空猜测或编造个人数据\n'
        '- 当用户询问你的身份时，介绍你是「职管家」AI 职业管家的【$name】任务智能体，'
        '以及你能提供的服务范围\n'
        '- 始终用中文回答，保持专业、准确、诚实');
    return buf.toString();
  }
}
