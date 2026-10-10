/// 博客卡片（职管家 · 个人职业版）
///
/// 「推荐」「关注」「我的」三处**共用**的展示单元：同一条博客在任何入口的呈现
/// 规则完全一致（单一事实来源），避免多处各写一套样式而产生偏差。
///
/// **排版结构**（自上而下）：
/// 1. 作者信息行：头像 + 昵称 + 发布时间（整行可点击 → 进入作者主页）；
/// 2. 标题（**仅有标题时**才渲染）；
/// 3. 正文；
/// 4. 配图（仅有配图时渲染）：单图走大图，多图走九宫格缩略图，点击进全屏预览。
///
/// 标题规则：空标题、纯空白，以及历史版本自动填充的「无标题」，都视为无标题 ——
/// 不渲染标题元素、不留下任何占位文字或分隔线，直接展示正文。
library;


import 'package:flutter/material.dart';

import '../personal/user_avatar.dart';
import 'blog_store.dart';
import 'post_image.dart';

/// 卡片文字色（与全站保持一致）
const Color _kTitleColor = Color(0xFF1A1B1C);
const Color _kBodyColor = Color(0xFF6B7280);
const Color _kMetaColor = Color(0xFF9CA3AF);

/// 配图加载失败时的占位底色
const Color _kImagePlaceholder = Color(0xFFF3F4F6);

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

  /// 点击**作者信息行**（头像 + 昵称那一整横栏）的回调：进入作者主页。
  ///
  /// 为 null 时不响应点击（例如作者主页内的卡片，避免自己跳自己）。
  /// 注意：标题与正文区**不在**本回调范围内。
  final VoidCallback? onTapAuthor;

  const BlogPostCard({
    super.key,
    required this.post,
    this.margin = const EdgeInsets.only(bottom: 12),
    this.avatarSize = 40,
    this.onTapAuthor,
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
          // 整行可点击（进入作者主页）；标题与正文区不在点击范围内。
          GestureDetector(
            onTap: onTapAuthor,
            behavior: HitTestBehavior.opaque,
            child: Row(
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
                        style:
                            const TextStyle(fontSize: 12, color: _kMetaColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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

          // ── ④ 配图（纯图片说说在此直接呈现）──
          if (post.hasImages) ...[
            const SizedBox(height: 10),
            _PostImages(images: post.images),
          ],
        ],
      ),
    );
  }
}

/// 说说配图区
///
/// 布局规则：单图走 4:3 大图（观感更好），多图走九宫格缩略图
/// （4 张时用 2 列，避免第三格空着难看）；
/// 点击任意一张进入全屏预览，可在多图之间左右翻页。
class _PostImages extends StatelessWidget {
  final List<String> images;

  const _PostImages({required this.images});

  void _openViewer(BuildContext context, int index) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _PostImageViewer(images: images, initialIndex: index),
      ),
    );
  }

  /// 单张图片：本机文件与云端图片统一渲染（P3 起配图可能来自服务端）
  Widget _image(String path, BoxFit fit) => PostImage(
        path,
        fit: fit,
        placeholder: () => Container(
          color: _kImagePlaceholder,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image_outlined,
              color: Color(0xFFB5B9C0)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (images.length == 1) {
      return GestureDetector(
        onTap: () => _openViewer(context, 0),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _image(images.first, BoxFit.cover),
          ),
        ),
      );
    }

    final columns = images.length == 4 ? 2 : 3;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: images.length,
      itemBuilder: (context, i) => GestureDetector(
        onTap: () => _openViewer(context, i),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: _image(images[i], BoxFit.cover),
        ),
      ),
    );
  }
}

/// 配图全屏预览：黑底、可双指缩放、多图可左右翻页
class _PostImageViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _PostImageViewer({required this.images, this.initialIndex = 0});

  @override
  State<_PostImageViewer> createState() => _PostImageViewerState();
}

class _PostImageViewerState extends State<_PostImageViewer> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final multi = widget.images.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          multi ? '${_index + 1} / ${widget.images.length}' : '图片',
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        onPageChanged: (i) => setState(() => _index = i),
        itemCount: widget.images.length,
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: PostImage(
              widget.images[i],
              fit: BoxFit.contain,
              placeholder: () => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
