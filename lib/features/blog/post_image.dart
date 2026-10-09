/// 说说配图渲染：自动区分「本机文件」与「服务端地址」
///
/// P3 起图片会上传到服务端（跨设备可见），因此同一个 `images` 字段
/// 里可能同时存在两种形态：
/// - 本机路径（刚发布、尚未上传成功，或离线状态）
/// - 服务端地址（`http…` 或 `/uploads/…`）
///
/// 集中在这里判断，避免各页面各写一套 `Image.file` / `Image.network`。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../contracts/api_config.dart';

/// 把服务端返回的相对地址补全成完整 URL
String resolveImageUrl(String path) {
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  if (path.startsWith('/')) return '${ApiConfig.mediaBaseUrl}$path';
  return path;
}

/// 是否为服务端图片（相对路径或 http 地址）
bool isRemoteImage(String path) =>
    path.startsWith('http://') || path.startsWith('https://') || path.startsWith('/uploads/');

class PostImage extends StatelessWidget {
  final String path;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// 加载失败/加载中的占位（不传则用内置的浅灰占位）
  final Widget Function()? placeholder;

  const PostImage(
    this.path, {
    super.key,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    final w = width;
    final h = height;
    if (isRemoteImage(path)) {
      return Image.network(
        resolveImageUrl(path),
        fit: fit,
        width: w,
        height: h,
        // 弱网/失败时不留白块，给一个明确的占位
        errorBuilder: (_, __, ___) => _placeholder(context),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _placeholder(context),
      );
    }
    return Image.file(
      File(path),
      fit: fit,
      width: w,
      height: h,
      errorBuilder: (_, __, ___) => _placeholder(context),
    );
  }

  Widget _placeholder(BuildContext context) =>
      placeholder?.call() ??
      Container(
        width: width,
        height: height,
        color: Colors.black.withOpacity(0.06),
        alignment: Alignment.center,
        child: Icon(Icons.image_not_supported_outlined,
            size: 20, color: Colors.black.withOpacity(0.3)),
      );
}
