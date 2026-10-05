/// 多租户存储管理
///
/// 按个人手机号隔离数据目录：
/// tenants/{phone}/sessions/   原始会话
/// tenants/{phone}/memory/     记忆层MD文件
/// tenants/{phone}/database.db SQLite数据库
library;

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class TenantStorage {
  /// 获取租户根目录
  static Future<Directory> getTenantDir(String creditCode) async {
    final base = await getApplicationDocumentsDirectory();
    final dir =
        Directory(p.join(base.path, 'tenants', _safeDirName(creditCode)));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 获取租户的原始会话目录
  static Future<Directory> getSessionsDir(String creditCode) async {
    final tenantDir = await getTenantDir(creditCode);
    final dir = Directory(p.join(tenantDir.path, 'sessions'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 获取租户的记忆层目录
  static Future<Directory> getMemoryDir(String creditCode) async {
    final tenantDir = await getTenantDir(creditCode);
    final dir = Directory(p.join(tenantDir.path, 'memory'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 获取租户的数据库文件路径
  static Future<String> getDatabasePath(String creditCode) async {
    final tenantDir = await getTenantDir(creditCode);
    return p.join(tenantDir.path, 'database.db');
  }

  /// 安全的目录名（对租户ID做脱敏，避免特殊字符）
  static String _safeDirName(String code) {
    return code.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
  }
}
