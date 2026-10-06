/// 收藏列表页（从「我的 · 收藏」卡进入）
///
/// 时间线倒序展示全部收藏的 AI 输出；每条支持复制 / 删除。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'favorite_store.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<FavoriteItem>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await FavoriteStore.list();
    if (mounted) setState(() => _items = list);
  }

  String _fmt(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _remove(FavoriteItem item) async {
    await FavoriteStore.removeById(item.id);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已删除'), duration: Duration(seconds: 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('收藏'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1B1C),
      ),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? _empty()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _card(items[i]),
                ),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF5B7FD4).withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.star_border_rounded,
                size: 32, color: Color(0xFF5B7FD4)),
          ),
          const SizedBox(height: 14),
          const Text(
            '还没有收藏',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1A1B1C)),
          ),
          const SizedBox(height: 6),
          const Text(
            '点击 AI 回复下方的「收藏」，内容就会收拢到这里',
            style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
          ),
        ],
      ),
    );
  }

  Widget _card(FavoriteItem item) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(14),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
              const Spacer(),
              InkWell(
                onTap: () => _remove(item),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Icon(Icons.delete_outline,
                      size: 16, color: Color(0xFF9CA3AF)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.content,
            style: const TextStyle(
                fontSize: 14, height: 1.5, color: Color(0xFF1A1B1C)),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: item.content));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('已复制'),
                        duration: Duration(seconds: 1)),
                  );
                }
              },
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.copy_rounded,
                        size: 14, color: Color(0xFF6B7280)),
                    SizedBox(width: 3),
                    Text('复制',
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
