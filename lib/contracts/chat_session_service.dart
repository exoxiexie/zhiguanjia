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

  /// 重置为「刚安装、未登录」的内存态：清空会话与租户信息，并保留一个
  /// 空的「新对话」占位（保证 [conversations] 永不为空，界面读取不越界）。
  ///
  /// 由退出登录流程调用（见 `features/chat/session_reset.dart`）。
  /// 存在的意义：本服务是**进程级单例**，不清空会把上一账号的会话
  /// 泄漏给下一个账号（缺陷 P0-1）。
  void reset();

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

  /// 从当前会话的第 [uptoIndex] 条消息处分叉：
  /// 新建一个会话，把当前会话中 **[uptoIndex]（含）之前**的消息全量复制过去，
  /// 并立即切换到新会话；**原会话及其后续消息保持不变**。
  ///
  /// 用途：用户在 AI 回复气泡上点「分叉」，即可在不破坏原对话的前提下
  /// 另起一条从该处继续的对话线。返回新会话 id。
  /// [uptoIndex] 越界时按「复制当前全部消息」处理。
  Future<String> forkConversation(int uptoIndex);

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

  /// 把**单条消息**提炼为记忆（AI 气泡上的「提炼」按钮）。
  ///
  /// 与会话级 [extractToMemory] 的区别：
  /// - 只提炼这一条内容，**不改变会话的增量提炼进度指针**
  /// - 提炼结果写入**同一份「对话记忆」**（数据页可见）
  ///
  /// 按内容定位消息（界面层 [ChatMessage] 不带 id）：取当前会话中**最新**一条
  /// 内容相同且角色一致的消息。
  Future<bool> extractMessageToMemory(String content);
}
