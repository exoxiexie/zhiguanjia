/// 对话同步 API 契约（P4）
///
/// 设计（《商业版改造方案》第五节 C 类「对话类」）：**本地优先 + 增量同步**
/// - 写：本地先落库（离线可用），变更进本地 outbox，联网后按序补发
/// - 读：`pull(since:)` 只取 `seq > since` 的变更（含软删除），客户端存一个游标即可
///
/// 载荷用 Map 传输：本地实体已有 `toMap/fromMap`，映射层集中在同步引擎里，
/// 避免为四类数据各写一套 DTO。
library;

import 'auth_api.dart';

/// 一次增量拉取的结果
class SyncChanges {
  final int seq;
  final bool hasMore;
  final List<Map<String, dynamic>> conversations;
  final List<Map<String, dynamic>> messages;
  final List<Map<String, dynamic>> memories;
  final List<Map<String, dynamic>> searchItems;

  const SyncChanges({
    this.seq = 0,
    this.hasMore = false,
    this.conversations = const [],
    this.messages = const [],
    this.memories = const [],
    this.searchItems = const [],
  });

  bool get isEmpty =>
      conversations.isEmpty &&
      messages.isEmpty &&
      memories.isEmpty &&
      searchItems.isEmpty;

  static List<Map<String, dynamic>> _list(dynamic raw) => [
        for (final e in (raw as List? ?? const []))
          (e as Map).cast<String, dynamic>(),
      ];

  factory SyncChanges.fromWire(Map<String, dynamic> json) => SyncChanges(
        seq: (json['seq'] as num?)?.toInt() ?? 0,
        hasMore: json['has_more'] as bool? ?? false,
        conversations: _list(json['conversations']),
        messages: _list(json['messages']),
        memories: _list(json['memories']),
        searchItems: _list(json['search_items']),
      );
}

/// 一批待补发的本地变更
class SyncPushPayload {
  final List<Map<String, dynamic>> conversations;
  final List<Map<String, dynamic>> messages;
  final List<Map<String, dynamic>> memories;
  final List<Map<String, dynamic>> searchItems;
  final List<String> deletedConversations;
  final List<String> deletedMessages;
  final List<String> deletedMemories;
  final List<String> deletedSearchItems;

  const SyncPushPayload({
    this.conversations = const [],
    this.messages = const [],
    this.memories = const [],
    this.searchItems = const [],
    this.deletedConversations = const [],
    this.deletedMessages = const [],
    this.deletedMemories = const [],
    this.deletedSearchItems = const [],
  });

  bool get isEmpty =>
      conversations.isEmpty &&
      messages.isEmpty &&
      memories.isEmpty &&
      searchItems.isEmpty &&
      deletedConversations.isEmpty &&
      deletedMessages.isEmpty &&
      deletedMemories.isEmpty &&
      deletedSearchItems.isEmpty;

  Map<String, dynamic> toWire() => <String, dynamic>{
        'conversations': conversations,
        'messages': messages,
        'memories': memories,
        'search_items': searchItems,
        'deleted': <String, dynamic>{
          'conversations': deletedConversations,
          'messages': deletedMessages,
          'memories': deletedMemories,
          'search_items': deletedSearchItems,
        },
      };
}

/// 同步诊断信息（只含统计数字，不含内容）
class SyncServerStatus {
  final int seq;
  final int conversations;
  final int messages;
  final int memories;
  final int searchItems;

  const SyncServerStatus({
    this.seq = 0,
    this.conversations = 0,
    this.messages = 0,
    this.memories = 0,
    this.searchItems = 0,
  });

  factory SyncServerStatus.fromWire(Map<String, dynamic> json) =>
      SyncServerStatus(
        seq: (json['seq'] as num?)?.toInt() ?? 0,
        conversations: (json['conversations'] as num?)?.toInt() ?? 0,
        messages: (json['messages'] as num?)?.toInt() ?? 0,
        memories: (json['memories'] as num?)?.toInt() ?? 0,
        searchItems: (json['search_items'] as num?)?.toInt() ?? 0,
      );
}

/// 对话同步接口
abstract class SyncApi {
  /// 服务端同步状态（诊断用）
  Future<ApiResult<SyncServerStatus>> status();

  /// 增量拉取：[since] 之后的全部变更
  Future<ApiResult<SyncChanges>> pull({required int since, int limit = 500});

  /// 批量补发本地变更，返回服务端最新游标
  Future<ApiResult<int>> push(SyncPushPayload payload);
}
