/// 头像文件存储（职管家 · 个人职业版）
///
/// 职责：把用户选中的图片**复制**进应用私有目录并长期保存。
///
/// 为什么要复制：`image_picker` 返回的是系统相机/相册的**临时缓存路径**，
/// 系统随时可能清理，若直接把它存进用户档案，过一段时间头像就会变成裂图。
///
/// 目录约定：`<应用文档目录>/avatars/<手机号>.<扩展名>` ——
/// 按手机号命名，天然按账号隔离，且同一账号只保留一份（换格式时删旧文件）。
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AvatarStore {
  AvatarStore._();

  /// 头像目录名
  static const String _dirName = 'avatars';

  /// 支持的头像扩展名（非图片格式一律按 jpg 处理）
  static const List<String> _knownExts = [
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif'
  ];

  static Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _dirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _normalizeExt(String sourcePath) {
    final ext = p.extension(sourcePath).toLowerCase();
    return _knownExts.contains(ext) ? ext : '.jpg';
  }

  /// 保存头像：把 [sourcePath] 复制进私有目录，返回保存后的绝对路径
  ///
  /// 同一手机号只保留一份：扩展名变化时删除旧文件，避免残留。
  static Future<String> save({
    required String phone,
    required String sourcePath,
  }) async {
    final dir = await _dir();
    final ext = _normalizeExt(sourcePath);
    final target = File(p.join(dir.path, '$phone$ext'));

    // 清理该账号的其他格式旧头像
    for (final old in _knownExts) {
      final f = File(p.join(dir.path, '$phone$old'));
      if (old != ext && await f.exists()) {
        await f.delete();
      }
    }

    await File(sourcePath).copy(target.path);
    return target.path;
  }

  /// 移除头像文件（文件不存在时静默返回）
  static Future<void> remove(String phone) async {
    final dir = await _dir();
    for (final ext in _knownExts) {
      final f = File(p.join(dir.path, '$phone$ext'));
      if (await f.exists()) await f.delete();
    }
  }

  /// 头像文件是否存在（用于界面判断是否回落默认图标）
  static Future<bool> exists(String avatarPath) async {
    if (avatarPath.isEmpty) return false;
    return File(avatarPath).exists();
  }
}
