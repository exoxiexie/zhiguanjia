/// 自主学习成果的文件落盘（职管家 · 个人职业版）
///
/// 职责：把用户选中的**图片 / PDF 附件**复制进应用私有目录并长期保存，
/// 返回可直接入库的绝对路径。
///
/// **为什么必须复制**：`image_picker` / `file_picker` 返回的多是系统相机、
/// 相册或文件选择器的**临时缓存路径**（部分机型还是外部存储 / `content://`），
/// 系统随时可能清理或失联；若直接把这类路径写进成果数据，过一段时间
/// 成果里的图片会裂、PDF 点开提示"文件不存在"。
/// 处理方式与 [PostImageStore] / [AvatarStore] 完全一致，只是目录不同。
///
/// 目录约定：`<应用文档目录>/study_files/` ——
/// 每次新增生成一个「微秒时间戳 + 随机后缀 + 原扩展名」的唯一文件名，
/// 多条成果、多张图片、多个 PDF 互不覆盖。
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class StudyFileStore {
  StudyFileStore._();

  /// 成果文件目录名
  static const String _dirName = 'study_files';

  /// 图片扩展名（用于区分图片与附件）
  static const List<String> _imageExts = [
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
  ];

  static Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _dirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 是否为图片（按扩展名判断）
  static bool isImage(String path) =>
      _imageExts.contains(p.extension(path).toLowerCase());

  /// 文件原名（展示用）
  static String baseName(String path) => p.basename(path);

  /// 保存一个文件：把 [sourcePath] 复制进私有目录，返回保存后的绝对路径
  static Future<String> save(String sourcePath) async {
    final dir = await _dir();
    final ext = p.extension(sourcePath).toLowerCase();
    // 微秒时间戳在连续选择时也可能重复，补随机后缀兜底
    final name =
        '${DateTime.now().microsecondsSinceEpoch}_${_randomSuffix()}$ext';
    final target = File(p.join(dir.path, name));
    await File(sourcePath).copy(target.path);
    return target.path;
  }

  /// 批量保存（保持选中顺序）
  static Future<List<String>> saveAll(Iterable<String> sourcePaths) async {
    final out = <String>[];
    for (final path in sourcePaths) {
      out.add(await save(path));
    }
    return out;
  }

  /// 删除文件（不存在或删除失败一律静默跳过，不阻塞用户操作）
  static Future<void> removeAll(Iterable<String> paths) async {
    for (final path in paths) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {
        // 忽略：清理失败不影响用户操作
      }
    }
  }

  /// 文件字节数（文件不存在或读取失败返回 0）
  static Future<int> sizeOf(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) return await f.length();
    } catch (_) {
      // 忽略：体积仅用于展示
    }
    return 0;
  }

  /// 体积文案：`900 B` / `2 KB` / `3.0 MB`（0 或负数返回空串）
  static String formatSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// 3 位随机后缀（避免同一微秒内的批量保存撞名）
  static String _randomSuffix() {
    final n = DateTime.now().hashCode & 0xffff;
    return n.toRadixString(36).padLeft(3, '0');
  }
}
