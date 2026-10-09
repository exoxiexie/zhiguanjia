/// 对话同步引擎（P4）：**本地优先 + outbox 补发 + 增量拉取**
///
/// 设计（《商业版改造方案》第五节 C 类「对话类」）：
/// - 本地永远先落库（离线可用、不阻塞界面），变更写入 outbox 表
/// - 联网后按 seq 顺序补发（`POST /sync/push`），成功即出队
/// - 拉取用 `GET /sync?since=<游标>` 只取增量（含软删除），合并进本地库后前移游标
/// - 消息**只增不改**（服务端同规则），避免多设备互相覆盖历史
///
/// 所有网络失败都静默：同步是"尽力而为"的后台增强，绝不能影响聊天本身。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../contracts/sync_api.dart';
import '../api/sync_api_impl.dart';
import '../personal/personal_auth_service.dart';
import '../storage/database/app_database.dart';
import '../storage/database/dao/message_dao.dart';
import '../storage/database/dao/outbox_dao.dart';
import '../storage/database/dao/session_dao.dart';
import '../storage/database/models/message_entity.dart';
import '../storage/database/models/session_entity.dart';
import '../storage/memory_store.dart';
import '../storage/search_data_store.dart';
import '../../contracts/chat_service.dart';

class SyncEngine {
  /// 同步接口（契约类型，便于替换实现与单元测试）
  static SyncApi _api = const HttpSyncApi();

  /// 测试注入口
  @visibleForTesting
  static set apiForTest(SyncApi value) => _api = value;

  /// 增量游标（服务端 seq）
  @visibleForTesting
  static const String cursorKey = 'zhiguanjia.sync.cursor';

  /// 两次同步的最小间隔（进会话页、切后台回来都不至于狂发请求）
  static const Duration minInterval = Duration(seconds: 45);

  /// 单次请求硬超时
  static const Duration requestTimeout = Duration(seconds: 12);

  static bool _syncing = false;
  static DateTime? _lastSyncAt;

  // ────────────────────────── 入队 ──────────────────────────

  /// 会话新增/更新入队（传本地行 map，即 SessionEntity.toMap()）
  static Future<void> enqueueConversation(Map<String, dynamic> localRow) =>
      _enqueue('conversation', conversationToWire(localRow));

  /// 消息入队（传本地行 map，即 MessageEntity.toMap()）
  static Future<void> enqueueMessage(Map<String, dynamic> localRow) =>
      _enqueue('message', messageToWire(localRow));

  /// 会话删除入队
  static Future<void> enqueueDeleteConversation(String id) =>
      _enqueue('delete_conversation', <String, dynamic>{'id': id});

  /// 记忆入队（对话记忆从会话中提炼后调用）
  static Future<void> enqueueMemory(Map<String, dynamic> wire) =>
      _enqueue('memory', wire);

  /// 记忆删除入队
  static Future<void> enqueueDeleteMemory(String id) =>
      _enqueue('delete_memory', <String, dynamic>{'id': id});

  /// 联网搜索沉淀入队
  static Future<void> enqueueSearchItem(Map<String, dynamic> wire) =>
      _enqueue('search_item', wire);

  /// 搜索沉淀删除入队
  static Future<void> enqueueDeleteSearchItem(String id) =>
      _enqueue('delete_search_item', <String, dynamic>{'id': id});

  static Future<void> _enqueue(String kind, Map<String, dynamic> payload) async {
    try {
      await OutboxDao().add(kind, payload);
      // 立即尝试补发（真正的节流在 sync() 内部：45 秒内只发一次请求），
      // 不用 Timer 去抖：避免测试环境残留 pending timer，也少一层状态。
      unawaited(sync());
    } catch (_) {
      // 本地库未打开等异常：静默——同步绝不能影响业务写入
    }
  }

  // ────────────────────────── 同步主流程 ──────────────────────────

  static Future<bool> _canSync() async {
    final auth = await PersonalAuthService.getAuth();
    if (auth == null || auth.phone.isEmpty) return false;
    // 本地库必须先打开（有租户才有地方合并数据）
    return AppDatabase.instance.tenantId != null;
  }

  /// 一次完整同步：先补发本地变更，再拉取云端增量
  ///
  /// [force] 为 true 时忽略最小间隔（进入会话页时用）。
  static Future<bool> sync({bool force = false}) async {
    if (_syncing) return false;
    if (!await _canSync()) return false;
    if (!force &&
        _lastSyncAt != null &&
        DateTime.now().difference(_lastSyncAt!) < minInterval) {
      return false;
    }

    _syncing = true;
    try {
      await _flush();
      final pulled = await _pull();
      _lastSyncAt = DateTime.now();
      return pulled;
    } catch (_) {
      return false;
    } finally {
      _syncing = false;
    }
  }

  /// 补发 outbox 里的本地变更
  static Future<void> _flush() async {
    final dao = OutboxDao();
    final rows = await dao.pending();
    if (rows.isEmpty) return;

    final payload = buildPayload(rows);
    if (payload.isEmpty) {
      await dao.removeUpTo(rows.last.seq);
      return;
    }
    final res = await _api.push(payload).timeout(requestTimeout);
    if (res.ok) {
      await dao.removeUpTo(rows.last.seq);
    }
    // 失败：保留在 outbox，下次同步重试（本地已落库，不会丢数据）
  }

  /// 拉取云端增量并合并进本地库
  static Future<bool> _pull() async {
    final prefs = await SharedPreferences.getInstance();
    var cursor = prefs.getInt(cursorKey) ?? 0;

    // 循环拉取，直到没有更多（limit=500/次）
    for (var round = 0; round < 20; round++) {
      final res = await _api.pull(since: cursor).timeout(requestTimeout);
      if (!res.ok || res.data == null) return false;
      final changes = res.data!;
      await applyChanges(changes);
      cursor = changes.seq;
      await prefs.setInt(cursorKey, cursor);
      if (!changes.hasMore || changes.isEmpty) break;
    }
    return true;
  }

  /// 把云端变更合并进本地库（公开以便单测直接验证）
  static Future<void> applyChanges(SyncChanges changes) async {
    final tenant = AppDatabase.instance.tenantId;
    if (tenant == null) return;

    final sessionDao = SessionDao();
    for (final row in changes.conversations) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      if (row['deleted'] == true) {
        await sessionDao.delete(id);
        continue;
      }
      await sessionDao.insert(SessionEntity.fromMap(sessionRowFromWire(row, tenant)));
    }

    final messageDao = MessageDao();
    for (final row in changes.messages) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      if (row['deleted'] == true) {
        await AppDatabase.instance.db
            .delete('messages', where: 'id = ?', whereArgs: [id]);
        continue;
      }
      await messageDao.insert(MessageEntity.fromMap(messageRowFromWire(row)));
    }

    // 记忆（文件型存储）
    for (final row in changes.memories) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      if (row['deleted'] == true) {
        await MemoryStore.delete(tenant, id, sync: false);
        continue;
      }
      await MemoryStore.save(tenant, memoryFromWire(row), sync: false);
    }

    // 联网搜索沉淀（文件型存储）
    for (final row in changes.searchItems) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      if (row['deleted'] == true) {
        await SearchDataStore.delete(tenant, id, sync: false);
        continue;
      }
      await SearchDataStore.saveRaw(tenant, searchItemFromWire(row));
    }
  }

  // ────────────────────────── 记忆 / 搜索沉淀映射 ──────────────────────────

  /// 记忆 → 线上字段
  static Map<String, dynamic> memoryToWire(MemoryItem item) =>
      <String, dynamic>{
        'id': item.id,
        'title': item.title,
        'content': item.content,
        'tags': item.tags,
        'weight': item.weight,
        'category': item.category,
        'source': item.source,
        'created_at': item.createdAt.millisecondsSinceEpoch,
        'updated_at': item.updatedAt.millisecondsSinceEpoch,
      };

  /// 线上 → 记忆（dataTags 由本地默认生成，服务端只关心 tags 列表）
  static MemoryItem memoryFromWire(Map<String, dynamic> wire) => MemoryItem(
        id: wire['id']?.toString() ?? '',
        title: wire['title']?.toString() ?? '',
        weight: (wire['weight'] as num?)?.toInt() ?? 50,
        tags: [
          for (final t in (wire['tags'] as List? ?? const [])) t.toString(),
        ],
        category: wire['category']?.toString() ?? '未分类',
        source: wire['source']?.toString() ?? '对话记忆',
        createdAt: _msToDate(wire['created_at']),
        updatedAt: _msToDate(wire['updated_at']),
        content: wire['content']?.toString() ?? '',
      );

  /// 搜索沉淀 → 线上字段
  static Map<String, dynamic> searchItemToWire(SearchDataItem item) =>
      <String, dynamic>{
        'id': item.id,
        'title': item.title,
        'content': item.content,
        'search_query': item.searchQuery,
        'source': item.source,
        'category': item.category,
        'weight': item.weight,
        'tags': item.tags,
        'sources': [
          for (final s in item.sources) <String, dynamic>{'title': s.title, 'url': s.url},
        ],
        'created_at': item.createdAt.millisecondsSinceEpoch,
        'updated_at': item.updatedAt.millisecondsSinceEpoch,
      };

  /// 线上 → 搜索沉淀
  static SearchDataItem searchItemFromWire(Map<String, dynamic> wire) =>
      SearchDataItem(
        id: wire['id']?.toString() ?? '',
        title: wire['title']?.toString() ?? '',
        weight: (wire['weight'] as num?)?.toInt() ?? 30,
        tags: [
          for (final t in (wire['tags'] as List? ?? const [])) t.toString(),
        ],
        category: wire['category']?.toString() ?? '联网搜索',
        searchQuery: wire['search_query']?.toString() ?? '',
        source: wire['source']?.toString() ?? '联网搜索',
        content: wire['content']?.toString() ?? '',
        sources: [
          for (final s in (wire['sources'] as List? ?? const []))
            SearchSource(
              title: (s as Map)['title']?.toString() ?? '',
              url: s['url']?.toString() ?? '',
            ),
        ],
        createdAt: _msToDate(wire['created_at']),
        updatedAt: _msToDate(wire['updated_at']),
      );

  static DateTime _msToDate(dynamic value) =>
      DateTime.fromMillisecondsSinceEpoch((value as num?)?.toInt() ?? 0);

  // ────────────────────────── 载荷组装与字段映射 ──────────────────────────

  /// 把 outbox 行按类型归并成一次推送载荷（公开以便单测）
  static SyncPushPayload buildPayload(List<OutboxRow> rows) {
    final conversations = <Map<String, dynamic>>[];
    final messages = <Map<String, dynamic>>[];
    final memories = <Map<String, dynamic>>[];
    final searchItems = <Map<String, dynamic>>[];
    final delConversations = <String>[];
    final delMessages = <String>[];
    final delMemories = <String>[];
    final delSearchItems = <String>[];

    for (final row in rows) {
      switch (row.kind) {
        case 'conversation':
          conversations.add(row.payload);
          break;
        case 'message':
          messages.add(row.payload);
          break;
        case 'memory':
          memories.add(row.payload);
          break;
        case 'search_item':
          searchItems.add(row.payload);
          break;
        case 'delete_conversation':
          delConversations.add(row.payload['id']?.toString() ?? '');
          break;
        case 'delete_message':
          delMessages.add(row.payload['id']?.toString() ?? '');
          break;
        case 'delete_memory':
          delMemories.add(row.payload['id']?.toString() ?? '');
          break;
        case 'delete_search_item':
          delSearchItems.add(row.payload['id']?.toString() ?? '');
          break;
        default:
          break;
      }
    }

    return SyncPushPayload(
      conversations: conversations,
      messages: messages,
      memories: memories,
      searchItems: searchItems,
      deletedConversations: delConversations.where((e) => e.isNotEmpty).toList(),
      deletedMessages: delMessages.where((e) => e.isNotEmpty).toList(),
      deletedMemories: delMemories.where((e) => e.isNotEmpty).toList(),
      deletedSearchItems: delSearchItems.where((e) => e.isNotEmpty).toList(),
    );
  }

  /// 本地会话行 → 线上字段（本地用 session_id/tenant_id，线上用 conversation_id/user_id）
  static Map<String, dynamic> conversationToWire(Map<String, dynamic> local) =>
      <String, dynamic>{
        'id': local['id']?.toString() ?? '',
        'title': local['title']?.toString() ?? '',
        'business_tag': local['business_tag']?.toString() ?? '',
        'message_count': (local['message_count'] as num?)?.toInt() ?? 0,
        'last_extracted_message_id':
            local['last_extracted_message_id']?.toString() ?? '',
        'created_at': (local['created_at'] as num?)?.toInt() ?? 0,
        'updated_at': (local['updated_at'] as num?)?.toInt() ?? 0,
      };

  /// 本地消息行 → 线上字段
  static Map<String, dynamic> messageToWire(Map<String, dynamic> local) =>
      <String, dynamic>{
        'id': local['id']?.toString() ?? '',
        'conversation_id': local['session_id']?.toString() ?? '',
        'role': local['role']?.toString() ?? 'user',
        'content': local['content']?.toString() ?? '',
        'attachment_type': local['attachment_type']?.toString() ?? '',
        'attachment_path': local['attachment_path']?.toString() ?? '',
        'created_at': (local['created_at'] as num?)?.toInt() ?? 0,
      };

  /// 线上会话 → 本地行（补上租户）
  static Map<String, dynamic> sessionRowFromWire(
          Map<String, dynamic> wire, String tenant) =>
      <String, dynamic>{
        'id': wire['id']?.toString() ?? '',
        'tenant_id': tenant,
        'title': wire['title']?.toString() ?? '',
        'created_at': (wire['created_at'] as num?)?.toInt() ?? 0,
        'updated_at': (wire['updated_at'] as num?)?.toInt() ?? 0,
        'message_count': (wire['message_count'] as num?)?.toInt() ?? 0,
        'last_extracted_message_id':
            wire['last_extracted_message_id']?.toString() ?? '',
        'created_by': tenant,
        'business_tag': wire['business_tag']?.toString() ?? '',
      };

  /// 线上消息 → 本地行
  static Map<String, dynamic> messageRowFromWire(Map<String, dynamic> wire) {
    String? nullable(String? v) => (v == null || v.isEmpty) ? null : v;
    return <String, dynamic>{
      'id': wire['id']?.toString() ?? '',
      'session_id': wire['conversation_id']?.toString() ?? '',
      'role': wire['role']?.toString() ?? 'user',
      'content': wire['content']?.toString() ?? '',
      'attachment_type': nullable(wire['attachment_type']?.toString()),
      'attachment_path': nullable(wire['attachment_path']?.toString()),
      'created_at': (wire['created_at'] as num?)?.toInt() ?? 0,
    };
  }

  /// 仅测试使用：重置节流与进行中标记
  @visibleForTesting
  static void resetForTest() {
    _lastSyncAt = null;
    _syncing = false;
  }
}
