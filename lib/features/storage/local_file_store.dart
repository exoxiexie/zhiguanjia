/// 本地私有文件存储服务
///
/// 管理用户从本设备/U盘/移动硬盘沉淀到云端的私有文件。
/// - SQLite 存储文件元数据和沉淀会话记录
/// - 文件系统存储实际文件内容，按租户（手机号）+ 会话ID隔离
/// - 单个文件大小限制 20MB
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../data/data_tags.dart';
import 'database/app_database.dart';

/// 单个文件记录
class LocalFileItem {
  final String id; // 文件唯一ID
  final String sessionId; // 所属沉淀会话ID
  final String name; // 文件名
  final int size; // 文件大小（字节）
  final String extension; // 文件扩展名（不含点）
  final String relativePath; // 相对于租户目录的存储路径
  final String source; // 来源：device（本设备）/ usb（U盘/移动硬盘）
  final DateTime uploadedAt; // 沉淀时间

  /// 统一数据标签（来源/业务等维度，可持续扩展）
  final DataTags dataTags;

  LocalFileItem({
    required this.id,
    required this.sessionId,
    required this.name,
    required this.size,
    required this.extension,
    required this.relativePath,
    required this.source,
    required this.uploadedAt,
    DataTags? dataTags,
  }) : dataTags = dataTags ?? DataTags();

  /// 格式化文件大小
  String get sizeFormatted {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'session_id': sessionId,
        'name': name,
        'size': size,
        'extension': extension,
        'relative_path': relativePath,
        'source': source,
        'uploaded_at': uploadedAt.toIso8601String(),
        if (!dataTags.isEmpty) 'data_tags': dataTags.toJsonString(),
      };

  factory LocalFileItem.fromMap(Map<String, dynamic> map) => LocalFileItem(
        id: map['id'] as String,
        sessionId: map['session_id'] as String,
        name: map['name'] as String,
        size: map['size'] as int,
        extension: map['extension'] as String,
        relativePath: map['relative_path'] as String,
        source: map['source'] as String,
        uploadedAt: DateTime.parse(map['uploaded_at'] as String),
        dataTags: DataTags.fromJsonString(map['data_tags'] as String?),
      );
}

/// 一次沉淀会话
class LocalUploadSession {
  final String id; // 会话唯一ID
  final DateTime createdAt; // 沉淀时间
  final int fileCount; // 文件数量
  final int totalSize; // 总大小（字节）
  final String source; // 来源：device / usb
  final List<LocalFileItem> files; // 包含的文件列表

  const LocalUploadSession({
    required this.id,
    required this.createdAt,
    required this.fileCount,
    required this.totalSize,
    required this.source,
    required this.files,
  });

  String get totalSizeFormatted {
    if (totalSize < 1024) return '$totalSize B';
    if (totalSize < 1024 * 1024)
      return '${(totalSize / 1024).toStringAsFixed(1)} KB';
    return '${(totalSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get sourceLabel => source == 'usb' ? 'U盘/移动硬盘' : '本设备';
}

/// 本地文件存储服务
class LocalFileStore {
  /// 单个文件大小限制：20MB
  static const int maxFileSize = 20 * 1024 * 1024;

  /// 获取租户的本地文件存储根目录
  static Future<String> _tenantRoot(String tenantId) async {
    final docDir = await getApplicationDocumentsDirectory();
    final root = p.join(docDir.path, 'tenants', tenantId, 'local_files');
    await Directory(root).create(recursive: true);
    return root;
  }

  /// 获取数据库（确保已打开）
  static Future<Database> _getDb(String tenantId) async {
    return AppDatabase.instance.open(tenantId);
  }

  /// 创建沉淀会话，保存文件
  static Future<LocalUploadSession> createSession({
    required String tenantId,
    required String source,
    required List<File> files,
  }) async {
    final db = await _getDb(tenantId);
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final sessionDir = p.join(await _tenantRoot(tenantId), sessionId);
    await Directory(sessionDir).create(recursive: true);

    final now = DateTime.now();
    final fileItems = <LocalFileItem>[];
    int totalSize = 0;

    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final fileSize = await file.length();
      final fileName = p.basename(file.path);
      final ext = p.extension(fileName).replaceFirst('.', '').toLowerCase();
      final fileId = '${sessionId}_$i';
      final destPath = p.join(sessionDir, fileName);

      // 复制文件到存储目录
      await file.copy(destPath);

      final relativePath = p.join('local_files', sessionId, fileName);
      // 业务标签：根据文件名关键词匹配（零模型成本，用户可手改）
      final businessTags = DataBusinessTag.matchFromText(fileName);
      final item = LocalFileItem(
        id: fileId,
        sessionId: sessionId,
        name: fileName,
        size: fileSize,
        extension: ext,
        relativePath: relativePath,
        source: source,
        uploadedAt: now,
        // 统一标签：来源标签固定为"本地私有"（业务标签由关键词规则打）
        dataTags: DataTags()
          ..set(DataTagDimension.source, [DataSourceTag.localPrivate])
          ..set(DataTagDimension.business, businessTags),
      );
      fileItems.add(item);
      totalSize += fileSize;

      // 写入文件记录表
      await db.insert('local_files', item.toMap());
    }

    // 写入会话记录表
    await db.insert('local_upload_sessions', {
      'id': sessionId,
      'tenant_id': tenantId,
      'created_at': now.toIso8601String(),
      'file_count': fileItems.length,
      'total_size': totalSize,
      'source': source,
    });

    return LocalUploadSession(
      id: sessionId,
      createdAt: now,
      fileCount: fileItems.length,
      totalSize: totalSize,
      source: source,
      files: fileItems,
    );
  }

  /// 获取所有沉淀会话（按时间倒序）
  static Future<List<LocalUploadSession>> listSessions(String tenantId) async {
    final db = await _getDb(tenantId);
    final sessionMaps = await db.query(
      'local_upload_sessions',
      where: 'tenant_id = ?',
      whereArgs: [tenantId],
      orderBy: 'created_at DESC',
    );

    final sessions = <LocalUploadSession>[];
    for (final sm in sessionMaps) {
      final sessionId = sm['id'] as String;
      final fileMaps = await db.query(
        'local_files',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'uploaded_at ASC',
      );
      final files = fileMaps.map((fm) => LocalFileItem.fromMap(fm)).toList();

      sessions.add(LocalUploadSession(
        id: sessionId,
        createdAt: DateTime.parse(sm['created_at'] as String),
        fileCount: sm['file_count'] as int,
        totalSize: sm['total_size'] as int,
        source: sm['source'] as String,
        files: files,
      ));
    }
    return sessions;
  }

  /// 获取单个会话详情
  static Future<LocalUploadSession?> getSession(
      String tenantId, String sessionId) async {
    final db = await _getDb(tenantId);
    final sessionMaps = await db.query(
      'local_upload_sessions',
      where: 'tenant_id = ? AND id = ?',
      whereArgs: [tenantId, sessionId],
      limit: 1,
    );
    if (sessionMaps.isEmpty) return null;

    final sm = sessionMaps.first;
    final fileMaps = await db.query(
      'local_files',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'uploaded_at ASC',
    );
    final files = fileMaps.map((fm) => LocalFileItem.fromMap(fm)).toList();

    return LocalUploadSession(
      id: sessionId,
      createdAt: DateTime.parse(sm['created_at'] as String),
      fileCount: sm['file_count'] as int,
      totalSize: sm['total_size'] as int,
      source: sm['source'] as String,
      files: files,
    );
  }

  /// 删除沉淀会话（同时删除文件和数据库记录）
  static Future<void> deleteSession(String tenantId, String sessionId) async {
    final db = await _getDb(tenantId);

    // 删除文件
    final sessionDir =
        Directory(p.join(await _tenantRoot(tenantId), sessionId));
    if (await sessionDir.exists()) {
      await sessionDir.delete(recursive: true);
    }

    // 删除数据库记录
    await db
        .delete('local_files', where: 'session_id = ?', whereArgs: [sessionId]);
    await db.delete('local_upload_sessions',
        where: 'id = ?', whereArgs: [sessionId]);
  }

  /// 获取已沉淀文件总数
  static Future<int> getTotalFileCount(String tenantId) async {
    final db = await _getDb(tenantId);
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM local_files f '
      'JOIN local_upload_sessions s ON f.session_id = s.id '
      'WHERE s.tenant_id = ?',
      [tenantId],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// 获取最近一次沉淀时间
  static Future<DateTime?> getLastUploadTime(String tenantId) async {
    final db = await _getDb(tenantId);
    final result = await db.query(
      'local_upload_sessions',
      columns: ['created_at'],
      where: 'tenant_id = ?',
      whereArgs: [tenantId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (result.isEmpty) return null;
    return DateTime.parse(result.first['created_at'] as String);
  }

  /// 校验文件大小，返回超限的文件名列表
  static List<String> checkFileSizeLimit(List<File> files) {
    return files
        .where((f) {
          try {
            return f.lengthSync() > maxFileSize;
          } catch (_) {
            return false;
          }
        })
        .map((f) => p.basename(f.path))
        .toList();
  }
}
