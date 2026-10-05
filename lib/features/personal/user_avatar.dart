/// 用户头像（全站统一）
///
/// **唯一事实来源**：同一个用户在任何页面（「我的」页、博客信息流卡片…）
/// 的头像都由本组件渲染，规则一致：
/// 1. 设置了本地头像文件 → 显示该图片；
/// 2. 未设置、或文件已失效（被清理/迁移）→ 回落「昵称首字 + 由手机号决定的稳定底色」。
///
/// 这样「我的」页与博客推荐/关注信息流里的头像天然一致，不需要两处各写一套。
library;

import 'dart:io';

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

/// 由种子（通常是手机号）计算回落头像的底色：同一种子结果恒定
///
/// 用 FNV-1a 32 位哈希 + 尾部混淆：朴素的 `h*31+c` 取模只依赖低位，
/// 而手机号这类前缀高度相似、尾部相邻的字符串低位区分度很差，
/// 会导致大量用户拿到同一底色。混淆后相似号码也能落到不同底色。
Color userAvatarColor(String seed) {
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

/// 用户头像
class UserAvatar extends StatelessWidget {
  /// 本地头像文件路径（空=未设置，回落首字头像）
  final String avatarPath;

  /// 昵称（回落时取首字）
  final String name;

  /// 取色种子（通常传手机号，保证同一用户颜色恒定）
  final String seed;

  /// 直径
  final double size;

  /// 是否显示右下角相机角标（仅「我的」页用于提示可更换）
  final bool editable;

  const UserAvatar({
    super.key,
    this.avatarPath = '',
    this.name = '',
    this.seed = '',
    this.size = 56,
    this.editable = false,
  });

  /// 昵称首字；昵称为空时用「匿」
  String get initial {
    final n = name.trim();
    if (n.isEmpty) return '匿';
    return n.substring(0, 1).toUpperCase();
  }

  /// 回落头像：首字 + 稳定底色
  Widget _fallback() {
    final color = userAvatarColor(seed.isEmpty ? name.trim() : seed);
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

  @override
  Widget build(BuildContext context) {
    final image = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        // 文件缺失/解码失败时回落首字头像，避免裂图
        child: avatarPath.isEmpty
            ? _fallback()
            : Image.file(
                File(avatarPath),
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback(),
              ),
      ),
    );

    if (!editable) return SizedBox(width: size, height: size, child: image);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          image,
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: const Color(0xFF5B7FD4),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child:
                  const Icon(Icons.photo_camera, size: 10, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
