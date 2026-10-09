/// 消息 DAO
library;

import 'package:sqflite/sqflite.dart';
import '../app_database.dart';
import '../models/message_entity.dart';

class MessageDao {
  Database get _db => appDatabase.db;

  /// 插入消息
  Future<void> insert(MessageEntity message) async {
    await _db.insert(
      'messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 批量插入消息
  Future<void> insertAll(List<MessageEntity> messages) async {
    final batch = _db.batch();
    for (final msg in messages) {
      batch.insert('messages', msg.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// 获取指定会话的所有消息，按创建时间正序
  /// 该消息是否已在本地（同步合并时用于判断"是否新增"）
  Future<bool> exists(String id) async {
    final r = await _db.query('messages',
        columns: <String>['id'], where: 'id = ?', whereArgs: <Object>[id], limit: 1);
    return r.isNotEmpty;
  }

  /// 消息总数（同步诊断用）
  Future<int> count() async {
    final r = await _db.rawQuery('SELECT COUNT(*) AS n FROM messages');
    return (r.first['n'] as num?)?.toInt() ?? 0;
  }

  Future<List<MessageEntity>> findBySession(String sessionId) async {
    final maps = await _db.query(
      'messages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at ASC',
    );
    return maps.map((m) => MessageEntity.fromMap(m)).toList();
  }

  /// 删除指定会话的所有消息
  Future<void> deleteBySession(String sessionId) async {
    await _db.delete(
      'messages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }
}
