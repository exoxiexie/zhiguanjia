/// 联网搜索数据历史列表页
///
/// 按时间倒序展示所有自动沉淀的搜索数据。
/// 权重标签可点击弹出滑块直接调整，不用进详情页。
library;

import 'package:flutter/material.dart';

import '../storage/search_data_store.dart';
import 'search_data_detail_page.dart';
import 'search_data_edit_page.dart';

class SearchDataHistoryPage extends StatefulWidget {
  final String tenantId;

  const SearchDataHistoryPage({super.key, required this.tenantId});

  @override
  State<SearchDataHistoryPage> createState() => _SearchDataHistoryPageState();
}

class _SearchDataHistoryPageState extends State<SearchDataHistoryPage> {
  List<SearchDataItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    try {
      final list = await SearchDataStore.listAll(widget.tenantId);
      if (mounted) setState(() => _items = list);
    } catch (e) {
      debugPrint('加载搜索数据失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// 弹出权重调整滑块
  Future<void> _showWeightDialog(SearchDataItem item) async {
    double currentWeight = item.weight.toDouble();
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('调整权重'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('权重', style: TextStyle(fontSize: 14)),
                  Text(
                    '${currentWeight.toInt()}',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: _weightColor(currentWeight.toInt()),
                    ),
                  ),
                ],
              ),
              Slider(
                value: currentWeight,
                min: 0,
                max: 100,
                divisions: 100,
                label: '${currentWeight.toInt()}',
                activeColor: _weightColor(currentWeight.toInt()),
                onChanged: (val) => setDialogState(() => currentWeight = val),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  currentWeight >= 60
                      ? '当前权重 ≥ 60，会自动进入对话上下文'
                      : '当前权重 < 60，不会进入对话上下文',
                  style: TextStyle(
                    fontSize: 12,
                    color: currentWeight >= 60 ? const Color(0xFF059669) : const Color(0xFF6B7280),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(currentWeight),
              child: const Text('确认'),
            ),
          ],
        ),
      ),
    );

    if (result != null && result.toInt() != item.weight) {
      try {
        await SearchDataStore.updateWeight(widget.tenantId, item.id, result.toInt());
        _loadItems();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('权重已调整为 ${result.toInt()}')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('调整失败：$e')),
          );
        }
      }
    }
  }

  Color _weightColor(int weight) {
    if (weight >= 80) return const Color(0xFFDC2626);
    if (weight >= 60) return const Color(0xFFF59E0B);
    if (weight >= 40) return const Color(0xFF2563EB);
    return const Color(0xFF9CA3AF);
  }

  /// 删除确认
  Future<void> _confirmDelete(SearchDataItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除搜索数据'),
        content: Text('确定删除「${item.title}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await SearchDataStore.delete(widget.tenantId, item.id);
        _loadItems();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已删除')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败：$e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('联网搜索数据'),
        centerTitle: true,
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, size: 22),
            onPressed: () {
              Navigator.of(context)
                  .push(MaterialPageRoute(
                    builder: (_) => SearchDataEditPage(tenantId: widget.tenantId),
                  ))
                  .then((_) => _loadItems());
            },
            tooltip: '手动新建',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadItems,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? _buildEmpty()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    itemBuilder: (context, index) => _buildItemCard(_items[index]),
                  ),
      ),
    );
  }

  /// 空状态
  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text(
            '还没有搜索数据',
            style: TextStyle(fontSize: 15, color: Color(0xFF9CA3AF)),
          ),
          const SizedBox(height: 8),
          const Text(
            '在对话中使用联网搜索后\n会自动沉淀到这里',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFFC0C4CC)),
          ),
        ],
      ),
    );
  }

  /// 单条搜索数据卡片
  Widget _buildItemCard(SearchDataItem item) {
    final color = _weightColor(item.weight);
    return GestureDetector(
      onTap: () {
        Navigator.of(context)
            .push(MaterialPageRoute(
              builder: (_) => SearchDataDetailPage(
                tenantId: widget.tenantId,
                itemId: item.id,
              ),
            ))
            .then((_) => _loadItems());
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE4E3DD)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：权重标签（可点击）+ 标题
            Row(
              children: [
                // 权重标签 - 点击弹滑块
                GestureDetector(
                  onTap: () => _showWeightDialog(item),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: color.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tune, size: 12, color: color),
                        const SizedBox(width: 4),
                        Text(
                          '权重 ${item.weight}',
                          style: TextStyle(
                            fontSize: 12,
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 是否进上下文标记
                if (item.inContext)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '已进上下文',
                      style: TextStyle(fontSize: 10, color: Color(0xFF059669)),
                    ),
                  ),
                const Spacer(),
                // 删除按钮
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFC0C4CC)),
                  onPressed: () => _confirmDelete(item),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 标题
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1B1C),
              ),
            ),
            const SizedBox(height: 6),
            // 搜索关键词
            if (item.searchQuery.isNotEmpty)
              Row(
                children: [
                  const Icon(Icons.search, size: 12, color: Color(0xFF9CA3AF)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      item.searchQuery,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            // 内容摘要
            Text(
              item.content.replaceAll(RegExp(r'[#*\-\n]'), ' ').trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF), height: 1.4),
            ),
            const SizedBox(height: 10),
            // 标签 + 时间
            Row(
              children: [
                if (item.tags.isNotEmpty) ...[
                  Icon(Icons.label_outline, size: 12, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      item.tags.take(3).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ),
                ] else
                  const Spacer(),
                Icon(Icons.access_time, size: 12, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(
                  _formatDate(item.createdAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
