/// 原始会话 JSON 存档
///
/// 每个会话一个 JSON 文件，保存完整对话内容：
///   tenants/{creditCode}/sessions/{sessionId}.json
///
/// 与 SQLite 互为冗余：
///   - SQLite 是加载源（首页快速读取历史会话/消息）
///   - JSON 是原始完整存档（备份、迁移、后续自动提炼的输入）
///
/// 存档触发时机：每条消息写入 SQLite 成功后，把整个会话覆盖写一次。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'tenant_storage.dart';
import 'database/models/message_entity.dart';
import 'database/models/session_entity.dart';

/// 存档格式版本
const int kSessionArchiveVersion = 1;

class SessionArchive {
  /// 写队列：串行化写操作，避免同一会话并发覆盖写
  Future<void> _writeQueue = Future.value();

  /// 保存（覆盖写）一个会话的完整存档。
  /// [session] 与 [messages] 来自 SQLite 实体，字段完整、带时间戳。
  Future<void> save({
    required String tenantId,
    required SessionEntity session,
    required List<MessageEntity> messages,
  }) {
    final task = _writeQueue.then(
      (_) => _doSave(
        tenantId: tenantId,
        session: session,
        messages: messages,
      ),
    );
    // 队列吞掉异常避免断链；原始异常仍由调用方 await 捕获
    _writeQueue = task.then((_) {}, onError: (_) {});
    return task;
  }

  Future<void> _doSave({
    required String tenantId,
    required SessionEntity session,
    required List<MessageEntity> messages,
  }) async {
    final dir = await TenantStorage.getSessionsDir(tenantId);
    final file = File(p.join(dir.path, '${session.id}.json'));
    final data = <String, dynamic>{
      'version': kSessionArchiveVersion,
      'session': session.toMap(),
      'messages': messages.map((m) => m.toMap()).toList(),
    };
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      encoding: utf8,
      flush: true,
    );
  }

  /// 读取某个会话的存档 JSON；不存在或损坏返回 null
  Future<Map<String, dynamic>?> read({
    required String tenantId,
    required String sessionId,
  }) async {
    final dir = await TenantStorage.getSessionsDir(tenantId);
    final file = File(p.join(dir.path, '$sessionId.json'));
    if (!await file.exists()) return null;
    try {
      final text = await file.readAsString(encoding: utf8);
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 列出某租户的全部存档文件路径（按修改时间倒序）
  Future<List<File>> listFiles(String tenantId) async {
    final dir = await TenantStorage.getSessionsDir(tenantId);
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.json'))
        .toList();
    files.sort((a, b) {
      final sa = a.statSync().modified;
      final sb = b.statSync().modified;
      return sb.compareTo(sa);
    });
    return files.cast<File>();
  }

  /// 删除某个会话的存档文件
  Future<void> delete({
    required String tenantId,
    required String sessionId,
  }) async {
    final dir = await TenantStorage.getSessionsDir(tenantId);
    final file = File(p.join(dir.path, '$sessionId.json'));
    if (await file.exists()) {
      await file.delete();
    }
  }
}

/// 全局单例
final sessionArchive = SessionArchive();
