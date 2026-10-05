/// 博客作者头像（职管家 · 个人职业版）
///
/// 当前版本没有头像上传能力，因此用「昵称首字 + 由手机号决定的稳定底色」
/// 生成作者头像：同一作者颜色恒定、不同作者易于区分，且不依赖任何图片资源。
library;

import 'package:flutter/material.dart';

/// 头像底色候选（与品牌色系协调）
const List<Color> _kAvatarColors = [
  Color(0xFFFD5C13), // 品牌活力橙
  Color(0xFF5B7FD4),
  Color(0xFF16B89C),
  Color(0xFF8B5CF6),
  Color(0xFFF59E0B),
  Color(0xFFEC4899),
  Color(0xFF0EA5E9),
  Color(0xFF10B981),
];

/// 由种子（通常是作者手机号）计算头像底色：同一种子结果恒定
///
/// 用 FNV-1a 32 位哈希 + 尾部混淆：朴素的 `h*31+c` 取模只依赖低位，
/// 而手机号这类前缀高度相似、尾部相邻的字符串低位区分度很差，
/// 会导致大量作者拿到同一底色。混淆后相似号码也能落到不同底色。
Color blogAvatarColor(String seed) {
  if (seed.isEmpty) return _kAvatarColors.first;
  var hash = 0x811c9dc5; // FNV offset basis
  for (final unit in seed.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff; // FNV prime
  }
  // 尾部混淆（avalanche），让高位参与取模
  hash ^= hash >> 15;
  hash = (hash * 0x2c1b3c6d) & 0xffffffff;
  hash ^= hash >> 12;
  return _kAvatarColors[hash % _kAvatarColors.length];
}

/// 作者头像：圆形底色 + 昵称首字
class BlogAuthorAvatar extends StatelessWidget {
  /// 作者昵称（取首字作为文字）
  final String name;

  /// 取色种子（同一作者应恒定，通常传手机号）
  final String seed;

  /// 直径
  final double size;

  const BlogAuthorAvatar({
    super.key,
    required this.name,
    this.seed = '',
    this.size = 40,
  });

  /// 昵称首字；昵称为空时用「匿」
  String get initial {
    final n = name.trim();
    if (n.isEmpty) return '匿';
    return n.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final color = blogAvatarColor(seed.isEmpty ? name.trim() : seed);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
