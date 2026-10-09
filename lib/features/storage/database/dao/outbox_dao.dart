/// 同步发件箱（outbox） DAO
///
/// 本地写成功后把变更记一行，联网后由同步引擎按 seq 顺序补发；补发成功即删除。
/// 放在**同一个 SQLite 库**里，保证与业务写入同一事务边界，
/// 不会出现"数据写了却没进发件箱"的丢更新。
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../app_database.dart';

class OutboxRow {
  final int seq;
  final String kind;
  final Map<String, dynamic> payload;

  const OutboxRow(this.seq, this.kind, this.payload);
}

class OutboxDao {
  Database get _db => AppDatabase.instance.db;

  /// 入队一条变更
  Future<void> add(String kind, Map<String, dynamic> payload) async {
    await _db.insert('outbox', <String, dynamic>{
      'kind': kind,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 取最早的一批待发送变更（按入队顺序）
  Future<List<OutboxRow>> pending({int limit = 200}) async {
    final rows = await _db.query('outbox', orderBy: 'seq ASC', limit: limit);
    final out = <OutboxRow>[];
    for (final r in rows) {
      Map<String, dynamic>? payload;
      try {
        final v = jsonDecode(r['payload']?.toString() ?? '');
        payload = v is Map ? v.cast<String, dynamic>() : null;
      } catch (_) {
        payload = null;
      }
      if (payload == null) {
        // 载荷损坏：直接丢弃，避免一行坏数据卡死整个队列
        await _db.delete('outbox', where: 'seq = ?', whereArgs: [r['seq']]);
        continue;
      }
      out.add(OutboxRow(
        (r['seq'] as num).toInt(),
        r['kind']?.toString() ?? '',
        payload,
      ));
    }
    return out;
  }

  /// 已成功补发的行出队
  Future<void> removeUpTo(int maxSeq) async {
    await _db.delete('outbox', where: 'seq <= ?', whereArgs: [maxSeq]);
  }

  /// 精确移除指定 seq 的行（逐条降级补发时用：成功哪条删哪条，绝不误删失败项）
  Future<void> removeSeqs(List<int> seqs) async {
    if (seqs.isEmpty) return;
    final batch = _db.batch();
    for (final seq in seqs) {
      batch.delete('outbox', where: 'seq = ?', whereArgs: <Object>[seq]);
    }
    await batch.commit(noResult: true);
  }

  /// 待发送条数
  Future<int> count() async {
    final r = await _db.rawQuery('SELECT COUNT(*) AS n FROM outbox');
    return (r.first['n'] as num?)?.toInt() ?? 0;
  }
}
