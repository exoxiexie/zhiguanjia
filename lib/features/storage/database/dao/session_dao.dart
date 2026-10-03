/// 会话 DAO
library;

import 'package:sqflite/sqflite.dart';
import '../app_database.dart';
import '../models/session_entity.dart';

class SessionDao {
  Database get _db => appDatabase.db;

  /// 创建会话
  Future<void> insert(SessionEntity session) async {
    await _db.insert(
      'sessions',
      session.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 获取指定租户的会话，按更新时间倒序
  /// [createdBy] 不为空时只查该人创建的会话（admin 视角）；为空时查全部（owner 视角）
  Future<List<SessionEntity>> findByTenant(String tenantId, {String? createdBy}) async {
    final maps = await _db.query(
      'sessions',
      where: createdBy != null ? 'tenant_id = ? AND created_by = ?' : 'tenant_id = ?',
      whereArgs: createdBy != null ? [tenantId, createdBy] : [tenantId],
      orderBy: 'updated_at DESC',
    );
    return maps.map((m) => SessionEntity.fromMap(m)).toList();
  }

  /// 获取指定租户+业务标签的会话（业务智能体历史对话），按更新时间倒序
  /// [createdBy] 不为空时只查该人创建的（admin 隔离）
  Future<List<SessionEntity>> findByTenantAndBusiness(
    String tenantId,
    String businessTag, {
    String? createdBy,
  }) async {
    final maps = await _db.query(
      'sessions',
      where: createdBy != null
          ? 'tenant_id = ? AND business_tag = ? AND created_by = ?'
          : 'tenant_id = ? AND business_tag = ?',
      whereArgs: createdBy != null
          ? [tenantId, businessTag, createdBy]
          : [tenantId, businessTag],
      orderBy: 'updated_at DESC',
    );
    return maps.map((m) => SessionEntity.fromMap(m)).toList();
  }

  /// 根据ID获取会话
  Future<SessionEntity?> findById(String id) async {
    final maps = await _db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return SessionEntity.fromMap(maps.first);
  }

  /// 更新会话标题和更新时间
  Future<void> update(SessionEntity session) async {
    await _db.update(
      'sessions',
      session.toMap(),
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  /// 增加消息计数
  Future<void> incrementMessageCount(String sessionId) async {
    await _db.rawUpdate(
      'UPDATE sessions SET message_count = message_count + 1, updated_at = ? WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch, sessionId],
    );
  }

  /// 更新最后提炼的消息ID（用于增量提炼）
  Future<void> updateLastExtractedMessageId(String sessionId, String messageId) async {
    await _db.rawUpdate(
      'UPDATE sessions SET last_extracted_message_id = ?, updated_at = ? WHERE id = ?',
      [messageId, DateTime.now().millisecondsSinceEpoch, sessionId],
    );
  }

  /// 删除会话（级联删除消息）
  Future<void> delete(String id) async {
    await _db.delete(
      'sessions',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
