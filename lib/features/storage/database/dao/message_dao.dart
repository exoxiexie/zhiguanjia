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
      batch.insert('messages', msg.toMap());
    }
    await batch.commit(noResult: true);
  }

  /// 获取指定会话的所有消息，按创建时间正序
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
