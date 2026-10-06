/// AI 回复气泡操作条（复制 / 收藏）
///
/// 所有 AI 回复气泡底部统一挂这一条 —— 通用对话与专业智能体两处对话页
/// 共用同一实现，避免出现两套行为（本项目「避免第二套实现」的既有约定）。
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
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _action(icon: Icons.copy_rounded, label: '复制', onTap: _copy),
          const SizedBox(width: 4),
          _action(
            icon: _fav ? Icons.star_rounded : Icons.star_border_rounded,
            label: _fav ? '已收藏' : '收藏',
            color: _fav ? const Color(0xFFF59E0B) : null,
            onTap: _toggleFav,
          ),
        ],
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final c = color ?? const Color(0xFF6B7280);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 12, color: c)),
          ],
        ),
      ),
    );
  }
}
