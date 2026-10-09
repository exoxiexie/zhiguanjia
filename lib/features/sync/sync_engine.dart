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

  /// 增量游标（服务端 seq）——**按账号隔离**
  ///
  /// 曾经用单一全局键，导致同一台设备换账号时新账号沿用旧账号的游标而漏数据。
  static String cursorKeyFor(String phone) => 'zhiguanjia.sync.cursor.$phone';

  /// 历史回填标记（按账号）：老版本升级上来的历史数据只会补一次
  static String backfillKeyFor(String phone) =>
      'zhiguanjia.sync.backfilled.$phone';

  /// 两次同步的最小间隔（进会话页、切后台回来都不至于狂发请求）
  static const Duration minInterval = Duration(seconds: 45);

  /// 单次请求硬超时
  static const Duration requestTimeout = Duration(seconds: 12);

  static bool _syncing = false;

  /// 同步被锁挡回时置位：当前这轮结束后**补跑一次**，
  /// 否则"一条消息触发的同步"可能被在途同步挡掉，变更要等到下次 App 启动才发出去。
  static bool _rerunRequested = false;

  /// 节流时间按账号记录（换账号后新账号应立即同步，而不是等满 45 秒）
  static final Map<String, DateTime> _lastSyncAt = <String, DateTime>{};

  /// **远端变更通知**：云端拉取到「本地原本没有」的数据时自增，
  /// 供对话页监听后自动刷新列表（S-3）。
  ///
  /// 只在确有新增/删除时自增（不是每次拉取都通知），
  /// 避免把自己刚推上去又拉回来的数据当成"新消息"反复刷新界面。
  static final ValueNotifier<int> remoteChanges = ValueNotifier<int>(0);

  // ── 诊断信息（同步诊断页展示；排查线上问题时靠它，不再"静默吞异常"）──
  static DateTime? lastSyncAt;

  /// 推送/拉取错误**分开记**：曾经用同一个字段，结果"拉取成功"把推送错误覆盖掉，
  /// 诊断页显示不出失败原因（S-2 排查时踩的坑）。
  static String lastPushError = '';
  static String lastPullError = '';
  static int lastPushedCount = 0;
  static int lastPulledCount = 0;

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

  /// 当前登录手机号（未登录返回 null）
  static Future<String?> currentPhone() async {
    final auth = await PersonalAuthService.getAuth();
    final phone = auth?.phone ?? '';
    return phone.isEmpty ? null : phone;
  }

  /// 一次完整同步：先补发本地变更，再拉取云端增量
  ///
  /// [force] 为 true 时忽略最小间隔（进入会话页时用）。
  static Future<bool> sync({bool force = false}) async {
    // 入口**同步**上锁：必须在任何 await 之前置位，否则两个并发调用会同时
    // 通过检查（enqueue 触发的后台同步 + 页面触发的同步），同一批变更被重复推送。
    if (_syncing) {
      // 已有同步在跑：请求补跑，避免本次变更被永远搁置
      _rerunRequested = true;
      return false;
    }
    _syncing = true;
    try {
      final phone = await currentPhone();
      if (phone == null || AppDatabase.instance.tenantId == null) return false;

      final last = _lastSyncAt[phone];
      if (!force &&
          last != null &&
          DateTime.now().difference(last) < minInterval) {
        return false;
      }

      // 1) 补发本地待发变更
      lastPushedCount = await _flush();
      // 2) 首次同步做一次历史回填（老版本升级上来的数据只会补一次）
      await _maybeBackfill(phone);
      lastPushedCount += await _flush();
      // 3) 拉取云端增量
      final pulled = await _pull(phone);
      _lastSyncAt[phone] = DateTime.now();
      lastSyncAt = DateTime.now();
      // 推送错误**不因拉取成功而清除**（否则诊断页看不到真正的失败原因）
      lastPullError = pulled ? '' : lastPullError;
      return pulled;
    } catch (e) {
      lastPushError = '同步异常：$e';
      return false;
    } finally {
      _syncing = false;
      if (_rerunRequested) {
        _rerunRequested = false;
        unawaited(sync()); // 补跑：把被挡掉的那次变更补上
      }
    }
  }

  /// 首次同步：把本地已有历史全量推一次
  ///
  /// 为什么需要：outbox 只记录**升级之后新产生**的写入，升级前已有的会话、
  /// 消息、记忆、搜索沉淀从未上传过 —— 于是"老设备有历史、新设备看不到"。
  /// 回填是幂等的（服务端按 id 去重、按 updated_at 做 last-write-wins），
  /// 中途失败会在下次同步重试（重复推送无副作用）。
  static Future<void> _maybeBackfill(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(backfillKeyFor(phone)) == true) return;
    final ok = await backfillLocalHistory();
    if (ok) await prefs.setBool(backfillKeyFor(phone), true);
  }

  /// 全量回填本地历史（会话 / 消息 / 记忆 / 搜索沉淀），返回是否全部成功
  @visibleForTesting
  static Future<bool> backfillLocalHistory({int batchSize = 200}) async {
    final tenant = AppDatabase.instance.tenantId;
    if (tenant == null) return false;

    Future<bool> send(SyncPushPayload payload) async {
      if (payload.isEmpty) return true;
      final res = await _api.push(payload).timeout(requestTimeout);
      return res.ok;
    }

    try {
      final sessions = await SessionDao().findByTenant(tenant);

      // 会话
      for (var i = 0; i < sessions.length; i += batchSize) {
        final slice = sessions.sublist(
            i, (i + batchSize).clamp(0, sessions.length));
        if (!await send(SyncPushPayload(
            conversations: [for (final s in slice) conversationToWire(s.toMap())]))) {
          return false;
        }
      }

      // 消息（按会话读取，分批推送）
      var batch = <Map<String, dynamic>>[];
      Future<bool> flushBatch() async {
        if (batch.isEmpty) return true;
        final payload = SyncPushPayload(messages: List.of(batch));
        batch = <Map<String, dynamic>>[];
        return send(payload);
      }

      for (final s in sessions) {
        final msgs = await MessageDao().findBySession(s.id);
        for (final m in msgs) {
          batch.add(messageToWire(m.toMap()));
          if (batch.length >= batchSize && !await flushBatch()) return false;
        }
      }
      if (!await flushBatch()) return false;

      // 记忆（文件型）
      final memories = await MemoryStore.listAll(tenant);
      for (var i = 0; i < memories.length; i += batchSize) {
        final slice =
            memories.sublist(i, (i + batchSize).clamp(0, memories.length));
        if (!await send(SyncPushPayload(
            memories: [for (final m in slice) memoryToWire(m)]))) {
          return false;
        }
      }

      // 联网搜索沉淀（文件型）
      final items = await SearchDataStore.listAll(tenant);
      for (var i = 0; i < items.length; i += batchSize) {
        final slice = items.sublist(i, (i + batchSize).clamp(0, items.length));
        if (!await send(SyncPushPayload(
            searchItems: [for (final it in slice) searchItemToWire(it)]))) {
          return false;
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 补发 outbox 里的本地变更
  static Future<int> _flush() async {
    final dao = OutboxDao();
    final rows = await dao.pending();
    if (rows.isEmpty) return 0;

    final payload = buildPayload(rows);
    if (payload.isEmpty) {
      await dao.removeUpTo(rows.last.seq);
      return rows.length;
    }
    final res = await _api.push(payload).timeout(requestTimeout);
    if (res.ok) {
      await dao.removeUpTo(rows.last.seq);
      lastPushError = '';
      return rows.length;
    }

    // ── 整批失败 → 降级为逐条补发 ──
    // 教训（S-2）：一条超长/畸形的记录会让整批被服务端拒绝，
    // 于是整个发件箱永远清不掉、新数据再也同步不出去。
    // 逐条重试可以"跳过坏行"，保证其余变更照常同步。
    final code = res.error?.code ?? '未知';
    lastPushError = '整批推送失败（$code）：${res.error?.message ?? ''}；已改为逐条补发';

    var pushed = 0;
    final doneSeqs = <int>[];
    for (final row in rows) {
      final single = buildPayload(<OutboxRow>[row]);
      if (single.isEmpty) {
        doneSeqs.add(row.seq); // 未知类型：丢弃，避免永久占位
        continue;
      }
      try {
        final one = await _api.push(single).timeout(requestTimeout);
        if (one.ok) {
          pushed++;
          doneSeqs.add(row.seq);
        } else {
          lastPushError = '第 ${row.seq} 条（${row.kind}）推送失败：'
              '${one.error?.code ?? ''} ${one.error?.message ?? ''}';
        }
      } catch (e) {
        lastPushError = '逐条补发中断：$e';
        break;
      }
    }
    if (doneSeqs.isNotEmpty) await dao.removeSeqs(doneSeqs);
    return pushed;
  }

  /// 拉取云端增量并合并进本地库
  static Future<bool> _pull(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    final key = cursorKeyFor(phone);
    var cursor = prefs.getInt(key) ?? 0;

    // 循环拉取，直到没有更多（limit=500/次）
    for (var round = 0; round < 20; round++) {
      final res = await _api.pull(since: cursor).timeout(requestTimeout);
      if (!res.ok || res.data == null) {
        lastPullError = '拉取失败：${res.error?.message ?? '未知原因'}（游标 $cursor）';
        return false;
      }
      final changes = res.data!;
      await applyChanges(changes);
      cursor = changes.seq;
      lastPulledCount += changes.conversations.length +
          changes.messages.length +
          changes.memories.length +
          changes.searchItems.length;
      await prefs.setInt(key, cursor);
      if (!changes.hasMore || changes.isEmpty) break;
    }
    return true;
  }

  /// 把云端变更合并进本地库（公开以便单测直接验证）
  static Future<void> applyChanges(SyncChanges changes) async {
    final tenant = AppDatabase.instance.tenantId;
    if (tenant == null) return;

    // 统计"确实变化"的条数：只有本地没有过的（或需要删除的）才算变化
    var changed = 0;

    final sessionDao = SessionDao();
    for (final row in changes.conversations) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      if (row['deleted'] == true) {
        await sessionDao.delete(id);
        changed++;
        continue;
      }
      if (await sessionDao.findById(id) == null) changed++;
      await sessionDao.insert(SessionEntity.fromMap(sessionRowFromWire(row, tenant)));
    }

    final messageDao = MessageDao();
    for (final row in changes.messages) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      if (row['deleted'] == true) {
        await AppDatabase.instance.db
            .delete('messages', where: 'id = ?', whereArgs: [id]);
        changed++;
        continue;
      }
      if (!await messageDao.exists(id)) changed++;
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

    // 有真实变化才通知界面（对话页据此自动刷新，S-3）
    if (changed > 0) remoteChanges.value++;
  }

  // ────────────────────────── 记忆 / 搜索沉淀映射 ──────────────────────────

  /// 记忆 → 线上字段
  static Map<String, dynamic> memoryToWire(MemoryItem item) =>
      <String, dynamic>{
        'id': item.id,
        'title': _clamp(item.title, 200),
        'content': _clamp(item.content, 600000),
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
        'title': _clamp(item.title, 200),
        'content': _clamp(item.content, 600000),
        'search_query': _clamp(item.searchQuery, 300),
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

  /// 按服务端可接受的长度截断（本地不做截断，只在上传时裁剪）
  static String _clamp(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);

  /// 本地会话行 → 线上字段（本地用 session_id/tenant_id，线上用 conversation_id/user_id）
  static Map<String, dynamic> conversationToWire(Map<String, dynamic> local) =>
      <String, dynamic>{
        'id': local['id']?.toString() ?? '',
        // 标题由首条消息自动生成，可能很长 → 上传前裁剪，避免整批被拒
        'title': _clamp(local['title']?.toString() ?? '', 200),
        'business_tag': _clamp(local['business_tag']?.toString() ?? '', 32),
        'message_count': (local['message_count'] as num?)?.toInt() ?? 0,
        'last_extracted_message_id': _clamp(
            local['last_extracted_message_id']?.toString() ?? '', 128),
        'created_at': (local['created_at'] as num?)?.toInt() ?? 0,
        'updated_at': (local['updated_at'] as num?)?.toInt() ?? 0,
      };

  /// 本地消息行 → 线上字段
  static Map<String, dynamic> messageToWire(Map<String, dynamic> local) =>
      <String, dynamic>{
        'id': local['id']?.toString() ?? '',
        'conversation_id': local['session_id']?.toString() ?? '',
        'role': local['role']?.toString() ?? 'user',
        'content': _clamp(local['content']?.toString() ?? '', 600000),
        'attachment_type': _clamp(local['attachment_type']?.toString() ?? '', 16),
        'attachment_path': _clamp(local['attachment_path']?.toString() ?? '', 512),
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

  /// 同步诊断：把两端数量、待发队列、游标与最近错误汇总成可读报告
  ///
  /// 存在的意义：同步失败原本全部静默，线上只能靠猜；有了它，
  /// 用户复制一段文字就能定位是"推送不出去"还是"拉不下来"。
  static Future<Map<String, dynamic>> diagnose() async {
    final phone = await currentPhone() ?? '';
    final tenant = AppDatabase.instance.tenantId ?? '';

    int localConversations = 0;
    int localMessages = 0;
    int outbox = 0;
    int cursor = 0;
    try {
      if (tenant.isNotEmpty) {
        localConversations = (await SessionDao().findByTenant(tenant)).length;
        localMessages = await MessageDao().count();
      }
    } catch (_) {
      // 本机库未打开
    }
    try {
      outbox = await OutboxDao().count();
    } catch (_) {
      // 忽略
    }
    if (phone.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      cursor = prefs.getInt(cursorKeyFor(phone)) ?? 0;
    }

    final statusRes = await _api.status();
    final server = statusRes.ok ? statusRes.data : null;

    return <String, dynamic>{
      'phone': phone,
      'tenant': tenant,
      'local_conversations': localConversations,
      'local_messages': localMessages,
      'outbox_pending': outbox,
      'local_cursor': cursor,
      'server_ok': statusRes.ok,
      'server_error': statusRes.ok ? '' : (statusRes.error?.message ?? ''),
      'server_seq': server?.seq ?? -1,
      'server_conversations': server?.conversations ?? -1,
      'server_messages': server?.messages ?? -1,
      'server_memories': server?.memories ?? -1,
      'server_search_items': server?.searchItems ?? -1,
      'last_sync_at': lastSyncAt?.toIso8601String() ?? '',
      'last_push_error': lastPushError,
      'last_pull_error': lastPullError,
      'last_pushed': lastPushedCount,
      'last_pulled': lastPulledCount,
    };
  }

  /// 仅测试使用：重置节流与进行中标记
  @visibleForTesting
  static void resetForTest() {
    _lastSyncAt.clear();
    _syncing = false;
    _rerunRequested = false;
    lastSyncAt = null;
    lastPushError = '';
    lastPullError = '';
    lastPushedCount = 0;
    lastPulledCount = 0;
  }
}
