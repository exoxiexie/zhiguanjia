/// 业务域数据表通用 DAO
///
/// 通过三位一体注册表（[BusinessDomain]）操作对应数据表，
/// 表结构统一，新增业务域自动跟随，无需新写代码。
/// 一条记录 = 该业务域下的一条业务数据（如一笔贷款、一项专利、一份合同）。
library;

import 'package:sqflite/sqflite.dart';

import '../data/business_domain.dart';
import '../data/data_tags.dart';
import 'database/app_database.dart';

/// 业务域数据记录
class BusinessDomainRecord {
  final String id;
  final String creditCode;
  final String domainId;
  final String title;
  final String detail;
  final int weight;
  final DataTags dataTags;
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;

  BusinessDomainRecord({
    required this.id,
    required this.creditCode,
    required this.domainId,
    required this.title,
    this.detail = '',
    this.weight = 50,
    DataTags? dataTags,
    this.source = '模拟数据',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : dataTags = dataTags ?? DataTags(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory BusinessDomainRecord.fromMap(Map<String, dynamic> map) {
    return BusinessDomainRecord(
      id: map['id'] as String,
      creditCode: map['credit_code'] as String,
      domainId: map['domain_id'] as String,
      title: map['title'] as String,
      detail: map['detail'] as String? ?? '',
      weight: map['weight'] as int? ?? 50,
      dataTags: DataTags.fromJsonString(map['data_tags'] as String?),
      source: map['source'] as String? ?? '模拟数据',
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime(1970),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          DateTime(1970),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'credit_code': creditCode,
        'domain_id': domainId,
        'title': title,
        'detail': detail,
        'weight': weight,
        'data_tags': dataTags.toJsonString(),
        'source': source,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

/// 业务域数据表通用 DAO
class BusinessDomainStore {
  static Future<Database> _db(String tenantId) =>
      AppDatabase.instance.open(tenantId);

  /// 插入一条业务域记录（按统一ID映射数据表）
  static Future<void> insert(
      String tenantId, BusinessDomainRecord record) async {
    final domain = BusinessDomain.byId(record.domainId);
    if (domain == null) return;
    final db = await _db(tenantId);
    await db.insert(domain.table, record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 按租户列出记录（可限定业务域统一ID / 权重下限 / 条数上限，默认按权重降序）
  static Future<List<BusinessDomainRecord>> listByTenant(
    String tenantId, {
    String? domainId,
    int? weightMin,
    int limit = 100,
  }) async {
    final db = await _db(tenantId);
    final result = <BusinessDomainRecord>[];
    final domains = domainId != null
        ? [
            if (BusinessDomain.byId(domainId) != null)
              BusinessDomain.byId(domainId)!
          ]
        : kBusinessDomains;
    for (final domain in domains) {
      final where = <String>['credit_code = ?'];
      final args = <Object?>[tenantId];
      if (weightMin != null) {
        where.add('weight >= ?');
        args.add(weightMin);
      }
      final rows = await db.query(
        domain.table,
        where: where.join(' AND '),
        whereArgs: args,
        orderBy: 'weight DESC, created_at DESC',
        limit: limit,
      );
      result.addAll(rows.map(BusinessDomainRecord.fromMap));
    }
    return result;
  }

  /// 统计某租户某业务域记录数
  static Future<int> countByDomain(String tenantId, String domainId) async {
    final domain = BusinessDomain.byId(domainId);
    if (domain == null) return 0;
    final db = await _db(tenantId);
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${domain.table} WHERE credit_code = ?',
      [tenantId],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// 删除一条记录
  static Future<void> delete(
      String tenantId, String domainId, String id) async {
    final domain = BusinessDomain.byId(domainId);
    if (domain == null) return;
    final db = await _db(tenantId);
    await db.delete(
      domain.table,
      where: 'id = ? AND credit_code = ?',
      whereArgs: [id, tenantId],
    );
  }
}
