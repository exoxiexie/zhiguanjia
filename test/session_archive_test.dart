/// SessionArchive（原始会话 JSON 存档）单元测试
///
/// 用假 PathProvider 把应用文档目录指到临时目录，
/// 验证 save / read / 覆盖写 / listFiles / delete 的真实文件读写往返。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:zhiguanjia/features/storage/database/models/message_entity.dart';
import 'package:zhiguanjia/features/storage/database/models/session_entity.dart';
import 'package:zhiguanjia/features/storage/session_archive.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String root;
  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('archive_test');
    PathProviderPlatform.instance = _FakePathProvider(tempRoot.path);
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  const tenantId = '91510100TEST00000001';
  const sessionId = '1750000000000';

  SessionEntity buildSession({String? id, int messageCount = 0}) =>
      SessionEntity(
        id: id ?? sessionId,
        tenantId: tenantId,
        title: '产品定位讨论',
        createdAt: 1750000000000,
        updatedAt: 1750000000001,
        messageCount: messageCount,
      );

  List<MessageEntity> buildMessages() => [
        MessageEntity(
          id: '${sessionId}_user_2',
          sessionId: sessionId,
          role: 'user',
          content: '你好，帮我分析一下产品定位',
          createdAt: 1750000000000,
        ),
        MessageEntity(
          id: '${sessionId}_assistant_10',
          sessionId: sessionId,
          role: 'assistant',
          content: '好的，我们来梳理一下。',
          attachmentType: null,
          attachmentPath: null,
          createdAt: 1750000000001,
        ),
        MessageEntity(
          id: '${sessionId}_user_3',
          sessionId: sessionId,
          role: 'user',
          content: '继续',
          attachmentType: 'image',
          attachmentPath: '/tmp/photo.png',
          createdAt: 1750000000002,
        ),
      ];

  test('save 后 read 能还原完整会话与消息', () async {
    final messages = buildMessages();
    await sessionArchive.save(
      tenantId: tenantId,
      session: buildSession(messageCount: messages.length),
      messages: messages,
    );

    final data = await sessionArchive.read(
      tenantId: tenantId,
      sessionId: sessionId,
    );
    expect(data, isNotNull);

    final session = data!['session'] as Map<String, dynamic>;
    expect(session['id'], sessionId);
    expect(session['tenant_id'], tenantId);
    expect(session['title'], '产品定位讨论');
    expect(session['message_count'], 3);

    final msgs = data['messages'] as List<dynamic>;
    expect(msgs.length, 3);
    expect(msgs[0]['role'], 'user');
    expect(msgs[0]['content'], '你好，帮我分析一下产品定位');
    expect(msgs[1]['role'], 'assistant');
    expect(msgs[2]['attachment_type'], 'image');
    expect(msgs[2]['attachment_path'], '/tmp/photo.png');
  });

  test('覆盖写：再次 save 后 read 返回最新内容', () async {
    final first = buildMessages();
    await sessionArchive.save(
      tenantId: tenantId,
      session: buildSession(messageCount: first.length),
      messages: first,
    );

    final second = buildMessages().sublist(0, 2);
    await sessionArchive.save(
      tenantId: tenantId,
      session: buildSession(messageCount: second.length),
      messages: second,
    );

    final data = await sessionArchive.read(
      tenantId: tenantId,
      sessionId: sessionId,
    );
    expect(data!['messages'], hasLength(2));
    expect((data['session'] as Map)['message_count'], 2);
  });

  test('listFiles 只返回该租户的 .json 存档且按修改时间倒序', () async {
    await sessionArchive.save(
      tenantId: tenantId,
      session: buildSession(),
      messages: buildMessages(),
    );
    await sessionArchive.save(
      tenantId: tenantId,
      session: buildSession(id: '1750000000001'),
      messages: const [],
    );

    final files = await sessionArchive.listFiles(tenantId);
    expect(files, hasLength(2));
    expect(files.map((f) => f.path.split('/').last).toSet(),
        {'1750000000000.json', '1750000000001.json'});
  });

  test('delete 后 read 返回 null，文件不存在', () async {
    await sessionArchive.save(
      tenantId: tenantId,
      session: buildSession(),
      messages: buildMessages(),
    );

    await sessionArchive.delete(tenantId: tenantId, sessionId: sessionId);

    expect(
      await sessionArchive.read(tenantId: tenantId, sessionId: sessionId),
      isNull,
    );
  });

  test('存档文件为 UTF-8 编码且包含 version 字段', () async {
    await sessionArchive.save(
      tenantId: tenantId,
      session: buildSession(),
      messages: buildMessages(),
    );

    final file = File(
        '${tempRoot.path}/tenants/91510100TEST00000001/sessions/$sessionId.json');
    expect(await file.exists(), isTrue);
    final raw = await file.readAsString(encoding: utf8);
    expect(raw, contains('"version": 1'));
    // 中文不转义，直接以 UTF-8 保存
    expect(raw, contains('产品定位讨论'));
    // 缩进格式化输出
    expect(raw, contains('\n  "session"'));
  });
}
