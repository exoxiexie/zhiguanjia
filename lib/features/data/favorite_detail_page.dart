/// 收藏详情页（从「我的 · 收藏」列表点卡片进入）
///
/// 列表页每条卡片只显示 3 行摘要、超出截断；本页负责**全量显示**全文，
/// 支持选中文字 / 复制全文 / 删除该条（删除后回列表并刷新）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat/message_action_bar.dart';
import 'favorite_store.dart';

class FavoriteDetailPage extends StatefulWidget {
  final FavoriteItem item;

  const FavoriteDetailPage({super.key, required this.item});

  @override
  State<FavoriteDetailPage> createState() => _FavoriteDetailPageState();
}

class _FavoriteDetailPageState extends State<FavoriteDetailPage> {
  bool _busy = false;

  String _fmt(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.item.content));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _remove() async {
    if (_busy) return;
    setState(() => _busy = true);
    await FavoriteStore.removeById(widget.item.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已删除'), duration: Duration(seconds: 1)),
    );
    // 带 true 回列表，通知其重新加载
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('收藏详情'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1B1C),
        actions: [
          IconButton(
            onPressed: _busy ? null : _remove,
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF5B7FD4).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.source.isEmpty ? '对话' : item.source,
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF5B7FD4),
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_fmt(item.createdAt),
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF9CA3AF))),
                  ],
                ),
                const SizedBox(height: 14),
                SelectableText(
                  item.content,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.6,
                    color: Color(0xFF1A1B1C),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: MessageActionButton(
              icon: Icons.copy_rounded,
              label: '复制全文',
              onTap: _copy,
            ),
          ),
        ],
      ),
    );
  }
}
