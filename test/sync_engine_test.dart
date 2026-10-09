/// 对话同步引擎测试（P4）
///
/// 覆盖最容易出错、也最难在真机上排查的部分：
/// 1. outbox 行 → 推送载荷的归并（含删除项、未知项忽略）
/// 2. 本地行 → 线上字段映射（列名不同：session_id ↔ conversation_id 等）
/// 3. 线上字段 → 本地行映射（补租户、空附件转 null）
/// 4. 往返一致性：本地 → 线上 → 本地 不丢关键字段
///
/// 说明：outbox 的读写与 applyChanges 落到 SQLite，由真机验证覆盖；
/// 这里集中验证纯映射逻辑（bug 多数出在这一层）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zhiguanjia/contracts/sync_api.dart';
import 'package:zhiguanjia/features/storage/database/dao/outbox_dao.dart';
import 'package:zhiguanjia/features/sync/sync_engine.dart';

void main() {
  test('buildPayload：按类型归并 outbox 行，删除项单独归集', () {
    final rows = <OutboxRow>[
      OutboxRow(1, 'conversation', {'id': 'c1'}),
      OutboxRow(2, 'message', {'id': 'm1'}),
      OutboxRow(3, 'message', {'id': 'm2'}),
      OutboxRow(4, 'memory', {'id': 'mem1'}),
      OutboxRow(5, 'search_item', {'id': 's1'}),
      OutboxRow(6, 'delete_conversation', {'id': 'c9'}),
      OutboxRow(7, 'delete_message', {'id': 'm9'}),
      OutboxRow(8, '未知类型', {'id': 'x'}),
    ];

    final payload = SyncEngine.buildPayload(rows);

    expect(payload.conversations.length, 1);
    expect(payload.messages.length, 2);
    expect(payload.memories.length, 1);
    expect(payload.searchItems.length, 1);
    expect(payload.deletedConversations, ['c9']);
    expect(payload.deletedMessages, ['m9']);
    expect(payload.isEmpty, isFalse);
  });

  test('buildPayload：空 id 的删除项被过滤，空载荷 isEmpty=true', () {
    final payload = SyncEngine.buildPayload(<OutboxRow>[
      OutboxRow(1, 'delete_conversation', {'id': ''}),
      OutboxRow(2, '不认识的类型', {}),
    ]);
    expect(payload.deletedConversations, isEmpty);
    expect(payload.isEmpty, isTrue);
  });

  test('本地行 → 线上字段：列名映射正确（session_id → conversation_id）', () {
    final wire = SyncEngine.conversationToWire(<String, dynamic>{
      'id': 'c1',
      'tenant_id': '13800001111',
      'title': '我的会话',
      'created_at': 100,
      'updated_at': 200,
      'message_count': 3,
      'last_extracted_message_id': 'm2',
      'created_by': '13800001111',
      'business_tag': '职业规划',
    });
    expect(wire['id'], 'c1');
    expect(wire['title'], '我的会话');
    expect(wire['business_tag'], '职业规划');
    expect(wire['message_count'], 3);
    expect(wire['updated_at'], 200);
    expect(wire.containsKey('tenant_id'), isFalse, reason: '线上不带租户字段');

    final msg = SyncEngine.messageToWire(<String, dynamic>{
      'id': 'm1',
      'session_id': 'c1',
      'role': 'assistant',
      'content': '回答',
      'attachment_type': 'image',
      'attachment_path': '/x/a.png',
      'created_at': 300,
    });
    expect(msg['conversation_id'], 'c1');
    expect(msg['role'], 'assistant');
    expect(msg['content'], '回答');
    expect(msg['created_at'], 300);
  });

  test('线上字段 → 本地行：补租户，空附件转 null', () {
    final row = SyncEngine.sessionRowFromWire(<String, dynamic>{
      'id': 'c2',
      'title': '云端会话',
      'business_tag': '',
      'message_count': 5,
      'last_extracted_message_id': '',
      'created_at': 10,
      'updated_at': 20,
      'deleted': false,
    }, '13800002222');
    expect(row['tenant_id'], '13800002222');
    expect(row['created_by'], '13800002222');
    expect(row['title'], '云端会话');
    expect(row['message_count'], 5);

    final msg = SyncEngine.messageRowFromWire(<String, dynamic>{
      'id': 'm2',
      'conversation_id': 'c2',
      'role': 'user',
      'content': '问题',
      'attachment_type': '',
      'attachment_path': '',
      'created_at': 30,
    });
    expect(msg['session_id'], 'c2');
    expect(msg['attachment_type'], isNull, reason: '空附件应为 null（本地列可空）');
    expect(msg['attachment_path'], isNull);
  });

  test('往返一致性：本地 → 线上 → 本地 不丢关键字段', () {
    final local = <String, dynamic>{
      'id': 'c3',
      'tenant_id': '13800001111',
      'title': '往返测试',
      'created_at': 111,
      'updated_at': 222,
      'message_count': 7,
      'last_extracted_message_id': 'm7',
      'created_by': '13800001111',
      'business_tag': '求职面试',
    };
    final back = SyncEngine.sessionRowFromWire(
        SyncEngine.conversationToWire(local), '13800001111');

    expect(back['id'], local['id']);
    expect(back['title'], local['title']);
    expect(back['created_at'], local['created_at']);
    expect(back['updated_at'], local['updated_at']);
    expect(back['message_count'], local['message_count']);
    expect(back['last_extracted_message_id'], local['last_extracted_message_id']);
    expect(back['business_tag'], local['business_tag']);
    expect(back['tenant_id'], '13800001111');
  });

  test('SyncChanges.fromWire：解析四类数据与游标', () {
    final changes = SyncChanges.fromWire(<String, dynamic>{
      'seq': 42,
      'has_more': true,
      'conversations': [
        {'id': 'c1', 'deleted': false}
      ],
      'messages': [
        {'id': 'm1', 'deleted': false},
        {'id': 'm2', 'deleted': true},
      ],
      'memories': [],
      'search_items': [
        {'id': 's1'}
      ],
    });

    expect(changes.seq, 42);
    expect(changes.hasMore, isTrue);
    expect(changes.conversations.length, 1);
    expect(changes.messages.length, 2);
    expect(changes.searchItems.length, 1);
    expect(changes.isEmpty, isFalse);
  });

  test('SyncPushPayload.toWire：删除项按类型归入 deleted', () {
    const payload = SyncPushPayload(
      conversations: [
        {'id': 'c1'}
      ],
      deletedMessages: ['m1', 'm2'],
    );
    final wire = payload.toWire();
    expect((wire['conversations'] as List).length, 1);
    final deleted = wire['deleted'] as Map;
    expect((deleted['messages'] as List).length, 2);
    expect((deleted['conversations'] as List), isEmpty);
    expect(payload.isEmpty, isFalse);
  });
}
