/// 博客卡片（职管家 · 个人职业版）
///
/// 「推荐」「关注」「我的」三处**共用**的展示单元：同一条博客在任何入口的呈现
/// 规则完全一致（单一事实来源），避免多处各写一套样式而产生偏差。
///
/// **排版结构**（自上而下）：
/// 1. 作者信息行：头像 + 昵称 + 发布时间；
/// 2. 标题（**仅有标题时**才渲染）；
/// 3. 正文。
///
/// 标题规则：空标题、纯空白，以及历史版本自动填充的「无标题」，都视为无标题 ——
/// 不渲染标题元素、不留下任何占位文字或分隔线，直接展示正文。
library;

import 'package:flutter/material.dart';

import '../personal/user_avatar.dart';
import 'blog_store.dart';

/// 卡片文字色（与全站保持一致）
const Color _kTitleColor = Color(0xFF1A1B1C);
const Color _kBodyColor = Color(0xFF6B7280);
const Color _kMetaColor = Color(0xFF9CA3AF);

/// 发布时间格式：yyyy-MM-dd HH:mm
String formatBlogTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} '
      '${two(d.hour)}:${two(d.minute)}';
}

/// 博客卡片
class BlogPostCard extends StatelessWidget {
  final BlogPost post;

  /// 卡片外边距（列表里统一用底部间距）
  final EdgeInsetsGeometry margin;

  /// 头像直径
  final double avatarSize;

  const BlogPostCard({
    super.key,
    required this.post,
    this.margin = const EdgeInsets.only(bottom: 12),
    this.avatarSize = 40,
  });

  @override
  Widget build(BuildContext context) {
    final hasTitle = post.showTitle;
    final body = post.displayContent;

    return Container(
      margin: margin,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── ① 作者信息行：头像 + 昵称 + 发布时间 ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              UserAvatar(
                avatarPath: post.authorAvatarPath,
                name: post.displayAuthor,
                seed: post.avatarSeed,
                size: avatarSize,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      post.displayAuthor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _kTitleColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatBlogTime(post.createdAt),
                      style: const TextStyle(fontSize: 12, color: _kMetaColor),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── ② 标题（仅有标题时渲染）──
          if (hasTitle) ...[
            const SizedBox(height: 12),
            Text(
              post.title.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _kTitleColor,
              ),
            ),
          ],

          // ── ③ 正文 ──
          if (body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: _kBodyColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
