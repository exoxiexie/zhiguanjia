/// 同步引擎「真库」测试（SQLite via FFI）
///
/// 之前的测试只覆盖纯映射逻辑，而"回填→推送"和"拉取→写库"这两条路径
/// 必须碰真实数据库 —— 上一轮线上问题（历史数据从没上传）正出在这一层。
///
/// 覆盖：
/// 1. outbox 入队 → sync() 推送（整条链路）
/// 2. 历史回填：本地已有会话/消息会被分批推上去
/// 3. 拉取合并：云端变更写入本地库，删除标记生效
/// 4. 消息幂等：重复合并同一条消息不抛异常、不产生重复行
/// 5. 游标按账号隔离（换账号不串用）
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zhiguanjia/contracts/auth_api.dart';
import 'package:zhiguanjia/contracts/sync_api.dart';
import 'package:zhiguanjia/features/storage/database/app_database.dart';
import 'package:zhiguanjia/features/storage/database/dao/message_dao.dart';
import 'package:zhiguanjia/features/storage/database/dao/outbox_dao.dart';
import 'package:zhiguanjia/features/storage/database/dao/session_dao.dart';
import 'package:zhiguanjia/features/storage/database/models/message_entity.dart';
import 'package:zhiguanjia/features/storage/database/models/session_entity.dart';
import 'package:zhiguanjia/features/sync/sync_engine.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String root;
  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

class FakeSyncApi implements SyncApi {
  final List<SyncPushPayload> pushed = <SyncPushPayload>[];
  SyncChanges pullResult = const SyncChanges();
  bool online = true;

  /// 模拟"批里有畸形数据 → 服务端整批 422"（S-2 的线上场景）
  bool rejectBatches = false;

  int get pushedConversations =>
      pushed.fold(0, (n, p) => n + p.conversations.length);
  int get pushedMessages => pushed.fold(0, (n, p) => n + p.messages.length);

  ApiError get _offline =>
      const ApiError(statusCode: 0, code: 'network', message: '离线');

  @override
  Future<ApiResult<int>> push(SyncPushPayload payload) async {
    if (!online) return ApiResult.failure(_offline);
    final rows = payload.conversations.length +
        payload.messages.length +
        payload.memories.length +
        payload.searchItems.length;
    if (rejectBatches && rows > 1) {
      return const ApiResult.failure(ApiError(
          statusCode: 422,
          code: 'invalid_request',
          message: 'conversations.0.title: String should have at most 200 characters'));
    }
    pushed.add(payload);
    return const ApiResult.success(1);
  }

  @override
  Future<ApiResult<SyncChanges>> pull({required int since, int limit = 500}) async {
    if (!online) return ApiResult.failure(_offline);
    return ApiResult.success(pullResult);
  }

  @override
  Future<ApiResult<SyncServerStatus>> status() async {
    if (!online) return ApiResult.failure(_offline);
    return const ApiResult.success(SyncServerStatus(
        seq: 42, conversations: 2, messages: 3, memories: 0, searchItems: 0));
  }
}

const String _phone = '13800138000';

/// 等待条件成立（enqueue 会立刻触发一次后台同步，测试需要等它跑完）
Future<void> waitUntil(Future<bool> Function() cond,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (await cond()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempRoot;
  late FakeSyncApi api;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('sync_db_test');
    PathProviderPlatform.instance = _FakePathProvider(tempRoot.path);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'zhiguanjia.personal.auth':
          '{"token":"t","phone":"$_phone","name":"我","idCard":"","gender":"","birthday":"","province":"","verifiedAt":"","avatarPath":""}',
    });
    api = FakeSyncApi();
    SyncEngine.apiForTest = api;
    SyncEngine.resetForTest();
    await AppDatabase.instance.open(_phone);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  Future<void> seedLocal() async {
    final sessionDao = SessionDao();
    final messageDao = MessageDao();
    await sessionDao.insert(SessionEntity(
      id: 's1',
      tenantId: _phone,
      title: '老会话一',
      createdAt: 100,
      updatedAt: 200,
      messageCount: 2,
    ));
    await sessionDao.insert(SessionEntity(
      id: 's2',
      tenantId: _phone,
      title: '老会话二',
      createdAt: 300,
      updatedAt: 400,
    ));
    await messageDao.insert(MessageEntity(
        id: 'm1', sessionId: 's1', role: 'user', content: '你好', createdAt: 110));
    await messageDao.insert(MessageEntity(
        id: 'm2', sessionId: 's1', role: 'assistant', content: '你好呀', createdAt: 120));
    await messageDao.insert(MessageEntity(
        id: 'm3', sessionId: 's2', role: 'user', content: '在吗', createdAt: 310));
  }

  test('outbox → sync() 推送：本地新写入能补发上去', () async {
    await SyncEngine.enqueueConversation(<String, dynamic>{
      'id': 'c9',
      'tenant_id': _phone,
      'title': '新会话',
      'created_at': 1,
      'updated_at': 2,
      'message_count': 0,
    });

    // enqueue 后会自动触发一次后台同步：等队列排空
    await waitUntil(() async => await OutboxDao().count() == 0);

    expect(api.pushedConversations, 1, reason: '同一条变更只应推送一次（并发锁生效）');
    expect(api.pushed.first.conversations.first['id'], 'c9');
    expect(await OutboxDao().count(), 0, reason: '推送成功后应出队');
  });

  test('历史回填：本地已有会话与消息会被全量推上去（本轮线上问题所在）', () async {
    await seedLocal();

    final ok = await SyncEngine.backfillLocalHistory();
    expect(ok, isTrue);
    expect(api.pushedConversations, 2, reason: '两条历史会话都要上传');
    expect(api.pushedMessages, 3, reason: '三条历史消息都要上传');

    // 回填走的是直推而非 outbox，不应污染发件箱
    expect(await OutboxDao().count(), 0);
  });

  test('历史回填分批：batchSize 生效，不把全部塞进一个请求', () async {
    await seedLocal();

    await SyncEngine.backfillLocalHistory(batchSize: 1);
    // 2 会话 + 3 消息 = 5 个批次（每批 1 条）
    expect(api.pushed.length, 5);
  });

  test('拉取合并：云端会话与消息写入本地库，删除标记生效', () async {
    api.pullResult = SyncChanges(
      seq: 7,
      conversations: [
        {'id': 's9', 'title': '云端来的会话', 'created_at': 1, 'updated_at': 2,
         'message_count': 1, 'last_extracted_message_id': '', 'business_tag': '',
         'deleted': false},
        {'id': 's1', 'title': '被删掉的', 'created_at': 1, 'updated_at': 2,
         'message_count': 0, 'last_extracted_message_id': '', 'business_tag': '',
         'deleted': true},
      ],
      messages: [
        {'id': 'm9', 'conversation_id': 's9', 'role': 'user', 'content': '云端消息',
         'attachment_type': '', 'attachment_path': '', 'created_at': 5, 'deleted': false},
      ],
    );
    await seedLocal();

    await SyncEngine.sync(force: true);

    final sessions = await SessionDao().findByTenant(_phone);
    final ids = sessions.map((s) => s.id).toList();
    expect(ids, contains('s9'), reason: '云端会话应写入本地');
    expect(ids, isNot(contains('s1')), reason: '删除标记应删除本地会话');

    final msgs = await MessageDao().findBySession('s9');
    expect(msgs.length, 1);
    expect(msgs.first.content, '云端消息');
  });

  test('消息幂等：重复合并同一条消息不抛异常、不产生重复行', () async {
    api.pullResult = SyncChanges(
      seq: 3,
      conversations: [
        {'id': 's9', 'title': '会话', 'created_at': 1, 'updated_at': 2,
         'message_count': 1, 'last_extracted_message_id': '', 'business_tag': '',
         'deleted': false},
      ],
      messages: [
        {'id': 'm9', 'conversation_id': 's9', 'role': 'user', 'content': '同一内容',
         'attachment_type': '', 'attachment_path': '', 'created_at': 5, 'deleted': false},
      ],
    );

    await SyncEngine.sync(force: true);
    // 再来一次同样的数据（模拟重装后重新拉取 / 游标被重置）
    api.pullResult = SyncChanges(seq: 3, messages: api.pullResult.messages);
    await SyncEngine.sync(force: true);

    final msgs = await MessageDao().findBySession('s9');
    expect(msgs.length, 1, reason: '幂等 upsert，不应产生重复行');
  });

  test('游标按账号隔离：不同账号用不同键', () {
    expect(SyncEngine.cursorKeyFor('13800000001'),
        isNot(SyncEngine.cursorKeyFor('13800000002')));
    expect(SyncEngine.cursorKeyFor('13800000001'),
        contains('13800000001'));
  });

  test('同步游标前移：拉取后再次拉取从新游标继续', () async {
    api.pullResult = const SyncChanges(seq: 42);
    await SyncEngine.sync(force: true);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(SyncEngine.cursorKeyFor(_phone)), 42);
  });

  test('离线：推送失败不出队，变更留在 outbox 等下次重试', () async {
    api.online = false; // 先离线，再入队
    await SyncEngine.enqueueMessage(<String, dynamic>{
      'id': 'm99',
      'session_id': 's1',
      'role': 'user',
      'content': '离线消息',
      'created_at': 1,
    });
    await Future<void>.delayed(const Duration(milliseconds: 80)); // 等后台同步失败

    expect(api.pushed, isEmpty);
    expect(await OutboxDao().count(), 1, reason: '失败必须保留，不能丢变更');
  });

  test('并发同步：被挡掉的那次会在当前同步结束后补跑，发件箱不会滞留', () async {
    // 连续两条变更：第二条很可能撞上"第一次同步在途"而被锁挡回，
    // 补跑机制必须保证它最终仍被推送出去（这是"新消息不同步"的关键修复）
    await SyncEngine.enqueueConversation(<String, dynamic>{
      'id': 'c-race',
      'tenant_id': _phone,
      'title': '并发会话',
      'created_at': 1,
      'updated_at': 1,
      'message_count': 1,
    });
    await SyncEngine.enqueueMessage(<String, dynamic>{
      'id': 'm-race',
      'session_id': 'c-race',
      'role': 'user',
      'content': '并发消息',
      'created_at': 2,
    });

    await waitUntil(() async => await OutboxDao().count() == 0);

    expect(await OutboxDao().count(), 0, reason: '发件箱必须最终清空');
    expect(api.pushedConversations, greaterThanOrEqualTo(1));
    expect(api.pushedMessages, greaterThanOrEqualTo(1));
  });

  test('诊断：输出本机与会端的数量、待发队列与游标', () async {
    await seedLocal();

    final d = await SyncEngine.diagnose();

    expect(d['phone'], _phone);
    expect(d['local_conversations'], 2);
    expect(d['local_messages'], 3);
    expect(d['outbox_pending'], 0);
    expect(d['server_ok'], isTrue);
    expect(d['server_conversations'], 2);
    expect(d['server_seq'], 42);
    expect(d.containsKey('last_push_error'), isTrue);
    expect(d.containsKey('last_pull_error'), isTrue);
  });

  test('诊断：离线时服务端标记为不可访问但仍能给出本机数据', () async {
    await seedLocal();
    api.online = false;

    final d = await SyncEngine.diagnose();

    expect(d['server_ok'], isFalse);
    expect((d['server_error'] as String).isNotEmpty, isTrue);
    expect(d['local_conversations'], 2, reason: '服务端不可达也要能报本机数量');
  });

  test('整批被拒时降级为逐条补发：坏行不阻塞其余变更（S-2 根因修复）', () async {
    api.rejectBatches = true; // 服务端拒绝任何"多于一行的批次"

    await SyncEngine.enqueueConversation(<String, dynamic>{
      'id': 'k1', 'tenant_id': _phone, 'title': '批一',
      'created_at': 1, 'updated_at': 1, 'message_count': 0,
    });
    await SyncEngine.enqueueMessage(<String, dynamic>{
      'id': 'km1', 'session_id': 'k1', 'role': 'user', 'content': '批二', 'created_at': 2,
    });
    await SyncEngine.enqueueMessage(<String, dynamic>{
      'id': 'km2', 'session_id': 'k1', 'role': 'user', 'content': '批三', 'created_at': 3,
    });

    await waitUntil(() async => await OutboxDao().count() == 0);

    expect(await OutboxDao().count(), 0, reason: '整批失败后必须逐条补发、最终清空队列');
    // 逐条降级后，单行批次应该出现（说明确实走了降级路径）
    expect(api.pushed.where((p) => p.conversations.length + p.messages.length == 1).length,
        greaterThanOrEqualTo(3));
  });

  test('上传前截断：超长会话标题被裁到 200 字（本地标题不变）', () async {
    final longTitle = '标' * 250;
    await SyncEngine.enqueueConversation(<String, dynamic>{
      'id': 'long1', 'tenant_id': _phone, 'title': longTitle,
      'created_at': 1, 'updated_at': 1, 'message_count': 0,
    });

    await waitUntil(() async => await OutboxDao().count() == 0);

    final sent = api.pushed.firstWhere((p) => p.conversations.isNotEmpty);
    expect(sent.conversations.first['title'].toString().length, 200,
        reason: '上传前必须裁剪，否则服务端整批 422');
  });

  test('上传前截断：超长附件路径被裁到 512 字', () async {
    await SyncEngine.enqueueMessage(<String, dynamic>{
      'id': 'longm', 'session_id': 's1', 'role': 'user', 'content': 'x',
      'attachment_path': '/a' * 400, 'created_at': 1,
    });

    await waitUntil(() async => await OutboxDao().count() == 0);

    final sent = api.pushed.firstWhere((p) => p.messages.isNotEmpty);
    expect(sent.messages.first['attachment_path'].toString().length, 512);
  });
}
