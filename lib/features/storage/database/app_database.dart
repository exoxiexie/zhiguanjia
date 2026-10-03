/// 应用数据库管理
///
/// 每个租户一个独立的 SQLite 数据库文件，物理隔离。
/// 表结构：
///   sessions              会话表
///   messages              消息表
///   memory                记忆表
///   local_upload_sessions 本地文件沉淀会话表
///   local_files           本地文件记录表
///   {domain}_data         业务域数据表（12 张，三位一体：业务智能体↔标签↔数据表，
///                         由 kBusinessDomains 注册表驱动建表，可随注册增长）
library;

import 'package:sqflite/sqflite.dart';

import '../../data/business_domain.dart';
import '../tenant_storage.dart';

class AppDatabase {
  Database? _db;
  String? _tenantId;

  /// 全局单例
  static final AppDatabase instance = AppDatabase();

  /// 打开指定租户的数据库
  Future<Database> open(String tenantId) async {
    if (_db != null && _tenantId == tenantId) {
      return _db!;
    }
    await close();
    final path = await TenantStorage.getDatabasePath(tenantId);
    _db = await openDatabase(
      path,
      version: 7,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    _tenantId = tenantId;
    return _db!;
  }

  /// 获取当前已打开的数据库
  Database get db {
    if (_db == null) {
      throw StateError('Database not opened. Call open(tenantId) first.');
    }
    return _db!;
  }

  /// 当前租户ID
  String? get tenantId => _tenantId;

  /// 关闭数据库
  Future<void> close() async {
    await _db?.close();
    _db = null;
    _tenantId = null;
  }

  /// 创建表
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        title TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        message_count INTEGER DEFAULT 0,
        last_extracted_message_id TEXT,
        created_by TEXT,
        business_tag TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        attachment_type TEXT,
        attachment_path TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_messages_session_id ON messages(session_id)',
    );

    await db.execute(
      'CREATE INDEX idx_sessions_tenant_id ON sessions(tenant_id)',
    );

    // 记忆表
    await db.execute('''
      CREATE TABLE memory (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        title TEXT NOT NULL,
        weight INTEGER DEFAULT 50,
        tags TEXT,
        category TEXT,
        source TEXT,
        file_path TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // 本地文件沉淀会话表
    await db.execute('''
      CREATE TABLE local_upload_sessions (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        file_count INTEGER DEFAULT 0,
        total_size INTEGER DEFAULT 0,
        source TEXT NOT NULL
      )
    ''');

    // 本地文件记录表
    await db.execute('''
      CREATE TABLE local_files (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        name TEXT NOT NULL,
        size INTEGER DEFAULT 0,
        extension TEXT,
        relative_path TEXT NOT NULL,
        source TEXT NOT NULL,
        uploaded_at TEXT NOT NULL,
        data_tags TEXT,
        FOREIGN KEY (session_id) REFERENCES local_upload_sessions(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_local_files_session_id ON local_files(session_id)',
    );
    await db.execute(
      'CREATE INDEX idx_local_sessions_tenant_id ON local_upload_sessions(tenant_id)',
    );

    // 业务域数据表（12 张，三位一体，统一 schema）
    await _createBusinessDomainTables(db);
  }

  /// 按三位一体注册表创建业务域数据表（统一 schema）
  Future<void> _createBusinessDomainTables(Database db) async {
    for (final domain in kBusinessDomains) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ${domain.table} (
          id TEXT PRIMARY KEY,
          credit_code TEXT NOT NULL,
          domain_id TEXT NOT NULL,
          title TEXT NOT NULL,
          detail TEXT,
          weight INTEGER DEFAULT 50,
          data_tags TEXT,
          source TEXT DEFAULT '模拟数据',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${domain.table}_credit ON ${domain.table}(credit_code)',
      );
    }
  }

  /// 数据库升级
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v1 → v2：添加本地文件沉淀相关表
      await db.execute('''
        CREATE TABLE IF NOT EXISTS local_upload_sessions (
          id TEXT PRIMARY KEY,
          tenant_id TEXT NOT NULL,
          created_at TEXT NOT NULL,
          file_count INTEGER DEFAULT 0,
          total_size INTEGER DEFAULT 0,
          source TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS local_files (
          id TEXT PRIMARY KEY,
          session_id TEXT NOT NULL,
          name TEXT NOT NULL,
          size INTEGER DEFAULT 0,
          extension TEXT,
          relative_path TEXT NOT NULL,
          source TEXT NOT NULL,
          uploaded_at TEXT NOT NULL,
          data_tags TEXT,
          FOREIGN KEY (session_id) REFERENCES local_upload_sessions(id) ON DELETE CASCADE
        )
      ''');

      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_local_files_session_id ON local_files(session_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_local_sessions_tenant_id ON local_upload_sessions(tenant_id)',
      );
    }

    if (oldVersion < 3) {
      // v2 → v3：sessions 表添加最后提炼消息ID字段（用于增量提炼）
      await db.execute(
        'ALTER TABLE sessions ADD COLUMN last_extracted_message_id TEXT',
      );
    }

    if (oldVersion < 4) {
      // v3 → v4：local_files 表添加统一数据标签列（来源/业务等维度）
      await db.execute(
        'ALTER TABLE local_files ADD COLUMN data_tags TEXT',
      );
    }

    if (oldVersion < 5) {
      // v4 → v5：按三位一体注册表创建 12 张业务域数据表
      await _createBusinessDomainTables(db);
    }

    if (oldVersion < 6) {
      // v5 → v6：sessions 表添加 created_by 字段（记录创建人手机号，用于按人隔离对话）
      await db.execute(
        'ALTER TABLE sessions ADD COLUMN created_by TEXT',
      );
    }

    if (oldVersion < 7) {
      // v6 → v7：sessions 表添加 business_tag 字段（区分通用对话/各业务智能体会话）
      await db.execute(
        'ALTER TABLE sessions ADD COLUMN business_tag TEXT',
      );
    }
  }
}

/// 全局单例（兼容旧代码）
final appDatabase = AppDatabase.instance;
