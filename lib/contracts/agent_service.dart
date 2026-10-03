/// 契约层：Agent 服务接口（Harness）。
///
/// 【铁律1 前端驱动后端】业务层只依赖本接口编程，不接触模型/网络实现。
/// Harness 负责：工具注册 → 模型调用循环 → 终止条件 → 运行日志。
/// 当前 MVP 由 App 内置的轻量 harness 实现；未来迁移到后端时 UI/业务零改动。
library;

import 'chat_service.dart';

/// 流式增量回调：每次调用携带一段新增文本。
/// [delta] 本次新增片段；[reasoning] 为 true 表示思考过程片段，
/// false 表示最终正文片段（应逐字展示）。
typedef AgentStreamCallback = void Function(
  String delta, {
  required bool reasoning,
});

/// 工具开始执行回调（UI 可显示"正在搜索…"等状态）
typedef AgentToolStartCallback = void Function(String toolName);

/// 工具执行完成回调（UI 可更新状态）
typedef AgentToolEndCallback = void Function(String toolName, String result);

/// 一次工具调用的执行结果（给模型回填）
class ToolResult {
  /// 工具名
  final String name;

  /// 执行结果（纯文本，回填给模型）
  final String content;

  const ToolResult({required this.name, required this.content});
}

/// 单个 Agent 循环步骤的日志
class AgentStepLog {
  /// 步骤序号（从 1 开始）
  final int step;

  /// 本步模型调用的工具请求（可多个）
  final List<ToolCallRecord> toolCalls;

  /// 本步是否命中终止（模型给出最终回复）
  final bool finished;

  /// 本步耗时
  final Duration elapsed;

  /// 本步 token 消耗
  final int promptTokens;
  final int completionTokens;

  const AgentStepLog({
    required this.step,
    required this.toolCalls,
    required this.finished,
    required this.elapsed,
    required this.promptTokens,
    required this.completionTokens,
  });
}

/// 一次工具调用记录
class ToolCallRecord {
  /// 工具调用 id（DeepSeek 返回）
  final String id;

  /// 工具名
  final String name;

  /// 参数（JSON）
  final Map<String, dynamic> args;

  /// 执行结果
  final String? result;

  const ToolCallRecord({
    required this.id,
    required this.name,
    required this.args,
    this.result,
  });
}

/// Agent 运行结果
class AgentResult {
  /// 最终回复（模型正文；未结束时为最后一步输出）
  final String reply;

  /// 循环步数
  final int steps;

  /// 总工具调用次数
  final int toolCalls;

  /// 完整运行日志（供排查/展示）
  final List<AgentStepLog> stepLogs;

  /// 是否在达到终止条件前正常结束
  final bool finished;

  const AgentResult({
    required this.reply,
    required this.steps,
    required this.toolCalls,
    required this.stepLogs,
    required this.finished,
  });
}

/// 工具定义（注册进工具注册表，供模型调用）
class ToolDefinition {
  /// 工具名（模型调用的唯一标识，如 `web_search`）
  final String name;

  /// 工具描述（告诉模型何时用、怎么用）
  final String description;

  /// 参数 JSON Schema（`type: object` + properties + required）
  final Map<String, dynamic> parameters;

  /// 执行函数：入参为解析后的参数 Map，返回纯文本结果回填给模型
  final Future<String> Function(Map<String, dynamic> args) execute;

  const ToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
    required this.execute,
  });
}

/// Agent 服务接口
abstract class AgentService {
  /// 设置个人职业身份上下文，作为每次 Agent 任务的系统提示词注入。
  ///
  /// 传入 null 表示清除个人上下文。
  void setPersonContext(String? contextText);

  /// 设置当前租户ID（个人手机号），用于搜索数据自动沉淀等租户隔离操作。
  ///
  /// 传入 null 表示清除租户ID。
  void setTenantId(String? tenantId);

  /// 运行一次 Agent 任务。
  ///
  /// [history] 完整对话历史（含最新一条用户消息，ChatMessage 格式）。
  /// [tools] 本次任务可用的工具。
  /// [model] 指定模型 id。
  /// [maxSteps] 最大循环步数（终止条件之一）。
  /// [timeout] 整体超时（终止条件之二）。
  /// [onDelta] 最终回复阶段的流式增量回调（思考段/正文段分开）。
  /// [onToolStart] 工具开始执行时回调（UI 显示"正在搜索…"）。
  /// [onToolEnd] 工具执行完成时回调。
  Future<AgentResult> run({
    required List<ChatMessage> history,
    List<ToolDefinition> tools = const [],
    String model = 'deepseek-flash',
    int maxSteps = 8,
    Duration timeout = const Duration(seconds: 90),
    AgentStreamCallback? onDelta,
    AgentToolStartCallback? onToolStart,
    AgentToolEndCallback? onToolEnd,
  });
}
