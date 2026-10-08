/// AI 回复气泡操作条（复制 / 收藏）
///
/// 所有 AI 回复气泡底部统一挂这一条 —— 对话首页（懂你）的气泡统一使用。
/// 与 [MessageActionButton] 共用同一实现，避免出现两套行为
/// （本项目「避免第二套实现」的既有约定）。
///
/// 尺寸（v1.0.25 放大一档，与正文 15px 拉近距离）：
/// 图标 18 / 文字 14 / 图标-文字间距 4 / 按钮内边距 上下 6·左右 8 / 按钮间距 8。
/// 行内小按钮本体是 [MessageActionButton]，收藏列表页与详情页复用同一实现。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/favorite_store.dart';

class MessageActionBar extends StatefulWidget {
  /// 要复制 / 收藏的正文
  final String content;

  /// 来源标签（写进收藏记录，如 '通用对话' / '学习'）
  final String source;

  const MessageActionBar({
    super.key,
    required this.content,
    required this.source,
  });

  @override
  State<MessageActionBar> createState() => _MessageActionBarState();
}

class _MessageActionBarState extends State<MessageActionBar> {
  bool _fav = false;

  @override
  void initState() {
    super.initState();
    _checkFav();
  }

  @override
  void didUpdateWidget(covariant MessageActionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 流式气泡内容会持续变化，内容变了要重新判定收藏态
    if (oldWidget.content != widget.content) _checkFav();
  }

  Future<void> _checkFav() async {
    final has = await FavoriteStore.contains(widget.content);
    if (mounted) setState(() => _fav = has);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.content));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已复制'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _toggleFav() async {
    if (_fav) {
      await FavoriteStore.removeByContent(widget.content);
      if (mounted) {
        setState(() => _fav = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已取消收藏'),
            duration: Duration(seconds: 1),
          ),
        );
      }
      return;
    }
    final ok = await FavoriteStore.add(
      content: widget.content,
      source: widget.source,
    );
    if (mounted) {
      setState(() => _fav = ok);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? '已收藏，可在「我的 · 收藏」查看' : '该内容已在收藏中'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MessageActionButton(
            icon: Icons.copy_rounded,
            label: '复制',
            onTap: _copy,
          ),
          const SizedBox(width: 8),
          MessageActionButton(
            icon: _fav ? Icons.star_rounded : Icons.star_border_rounded,
            label: _fav ? '已收藏' : '收藏',
            color: _fav ? const Color(0xFFF59E0B) : null,
            onTap: _toggleFav,
          ),
        ],
      ),
    );
  }
}

/// 行内小按钮：图标 + 文字（如「复制」「收藏」）
///
/// 全站同类小按钮的**唯一实现**——气泡操作条、收藏列表页、收藏详情页共用，
/// 避免三处各写一份尺寸、改一处漏两处。
class MessageActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// 不传则用默认中灰（`#6B7280`）
  final Color? color;

  const MessageActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF6B7280);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: c),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 14, color: c)),
          ],
        ),
      ),
    );
  }
}
