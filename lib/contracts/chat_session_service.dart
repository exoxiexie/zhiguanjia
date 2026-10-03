/// 对话会话服务契约
///
/// 职责：管理多租户下的会话列表、消息持久化、原始 JSON 存档、
/// 以及 AI 回复后的自动记忆提炼。UI 层只依赖本契约，不直接操作数据库。
library;

import 'chat_service.dart';

/// 单个会话（从 home_tab 抽取，作为会话领域模型）
class Conversation {
  final String id;
  String title;
  final List<ChatMessage> messages;
  final DateTime createdAt;
  DateTime updatedAt;

  Conversation({
    required this.id,
    required this.title,
    List<ChatMessage>? messages,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : messages = messages ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();
}

/// 对话会话服务抽象接口
abstract class ChatSessionService {
  /// 初始化：获取当前租户、打开数据库、加载历史会话和消息。
  Future<void> init();

  /// 数据库是否已初始化完成。
  bool get isReady;

  /// 所有历史会话（最新的在前面）。
  List<Conversation> get conversations;

  /// 当前对话索引。
  int get currentIndex;

  /// 当前对话。
  Conversation get currentConversation;

  /// 当前对话的消息列表（便捷访问）。
  List<ChatMessage> get currentMessages;

  /// 新建对话并写入数据库，返回新会话 id。
  Future<String> newConversation();

  /// 切换到指定索引的对话。
  void switchConversation(int index);

  /// 持久化单条消息到数据库，并同步 JSON 存档；
  /// AI 回复后自动触发记忆提炼（fire-and-forget，失败静默）。
  Future<void> persistMessage(ChatMessage msg);

  /// 更新当前会话标题到数据库。
  Future<void> updateSessionTitle(String title);

  /// 把当前会话完整内容写为原始 JSON 存档（sessions/{sessionId}.json）。
  Future<void> syncArchive();

  /// 获取当前会话最后一次提炼时的消息ID（用于增量提炼）。
  /// 返回 null 表示从未提炼过。
  Future<String?> getLastExtractedMessageId();

  /// 更新当前会话最后一次提炼时的消息ID。
  Future<void> updateLastExtractedMessageId(String messageId);

  /// 把当前会话提炼为记忆。
  ///
  /// [incremental] 为 true 时，只提炼上一次提炼之后的增量消息；
  /// 为 false 时，提炼全部消息。
  /// 返回 true 表示提炼成功并保存了记忆，false 表示提炼失败或无值得记忆的内容。
  Future<bool> extractToMemory({bool incremental = true});
}
