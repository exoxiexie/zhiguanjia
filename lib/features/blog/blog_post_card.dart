/// 博客卡片（职管家 · 个人职业版）
///
/// 「推荐」流与「我的」列表**共用**的展示单元：同一条博客在任何入口的呈现
/// 规则完全一致（单一事实来源），避免两处各写一套样式而产生偏差。
///
/// 标题规则（对应需求：无标题不显示占位标题与分隔线）：
/// - 有标题 → 先显示标题，再显示正文；
/// - 无标题（空标题，或历史版本自动填充的「无标题」）→ **直接显示正文**，
///   不显示任何占位标题，也不绘制标题下的分隔线。
library;

import 'package:flutter/material.dart';

import 'blog_store.dart';

/// 卡片文字色（与全站保持一致）
const Color _kTitleColor = Color(0xFF1A1B1C);
const Color _kBodyColor = Color(0xFF6B7280);
const Color _kTimeColor = Color(0xFFB5B9C0);

/// 发布日期格式：yyyy-MM-dd HH:mm
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

  const BlogPostCard({
    super.key,
    required this.post,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  @override
  Widget build(BuildContext context) {
    final hasTitle = post.showTitle;
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
          // 仅「有标题」时渲染标题与标题下的间距；无标题直接进正文
          if (hasTitle) ...[
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
            const SizedBox(height: 8),
          ],
          if (post.displayContent.isNotEmpty)
            Text(
              post.displayContent,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: _kBodyColor,
              ),
            ),
          const SizedBox(height: 10),
          Text(
            formatBlogTime(post.createdAt),
            style: const TextStyle(fontSize: 12, color: _kTimeColor),
          ),
        ],
      ),
    );
  }
}
