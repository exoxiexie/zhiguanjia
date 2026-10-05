/// 说说配图存储（职管家 · 个人职业版）
///
/// 职责：把用户选中的图片**复制**进应用私有目录并长期保存。
///
/// 为什么要复制：`image_picker` 返回的是系统相机 / 相册的**临时缓存路径**，
/// 系统随时可能清理；若直接把临时路径写进说说数据，过一段时间图片就会变成裂图。
/// 处理方式与 [AvatarStore] 完全一致，只是目录与命名策略不同。
///
/// 目录约定：`<应用文档目录>/post_images/` ——
/// 每次选图生成一个 `微秒时间戳.扩展名` 的唯一文件名，多条说说、多张配图互不覆盖。
///
/// 与 [AvatarStore] 的差异：头像是「一人一份、覆盖式命名」，配图是「每次新增、唯一命名」，
/// 因此本类不提供按账号索引，只负责保存与删除。
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PostImageStore {
  PostImageStore._();

  /// 配图目录名
  static const String _dirName = 'post_images';

  /// 支持的图片扩展名（非图片格式一律按 jpg 处理）
  static const List<String> _knownExts = [
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

  static String _normalizeExt(String sourcePath) {
    final ext = p.extension(sourcePath).toLowerCase();
    return _knownExts.contains(ext) ? ext : '.jpg';
  }

  /// 保存一张配图：把 [sourcePath] 复制进私有目录，返回保存后的绝对路径
  static Future<String> save(String sourcePath) async {
    final dir = await _dir();
    final ext = _normalizeExt(sourcePath);
    // 微秒时间戳在连续选图时也可能重复（尤其多选批量复制），补随机后缀兜底
    final name = '${DateTime.now().microsecondsSinceEpoch}'
        '_${_randomSuffix()}$ext';
    final target = File(p.join(dir.path, name));
    await File(sourcePath).copy(target.path);
    return target.path;
  }

  /// 批量保存（多选相册时使用），保持选中顺序
  static Future<List<String>> saveAll(Iterable<String> sourcePaths) async {
    final out = <String>[];
    for (final path in sourcePaths) {
      out.add(await save(path));
    }
    return out;
  }

  /// 删除配图文件（文件不存在时静默返回；单个失败不影响其他文件）
  ///
  /// 用于两种场景：编辑说说时移除某张已选图片、放弃发布时清理本次已落盘的文件。
  static Future<void> removeAll(Iterable<String> paths) async {
    for (final path in paths) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {
        // 忽略：清理失败不阻塞用户操作
      }
    }
  }

  /// 4 位随机后缀（避免同一微秒内的批量保存撞名）
  static String _randomSuffix() {
    final n = DateTime.now().hashCode & 0xffff;
    return n.toRadixString(36).padLeft(3, '0');
  }
}
