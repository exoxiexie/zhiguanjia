/// 对话记忆数据详情页
///
/// 可视化展示所有对话记忆条目，支持新建、查看、编辑。
library;

import 'package:flutter/material.dart';

import '../memory/memory_edit_page.dart';
import '../storage/memory_store.dart';

/// 对话记忆列表页
class MemoryDetailPage extends StatefulWidget {
  final String tenantId;

  const MemoryDetailPage({super.key, required this.tenantId});

  @override
  State<MemoryDetailPage> createState() => _MemoryDetailPageState();
}

class _MemoryDetailPageState extends State<MemoryDetailPage> {
  List<MemoryItem> _memories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  Future<void> _loadMemories() async {
    setState(() => _loading = true);
    try {
      final list = await MemoryStore.listAll(widget.tenantId);
      // 按权重降序、更新时间降序排列
      list.sort((a, b) {
        if (b.weight != a.weight) return b.weight.compareTo(a.weight);
        return b.updatedAt.compareTo(a.updatedAt);
      });
      if (mounted) setState(() => _memories = list);
    } catch (e) {
      debugPrint('加载记忆失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 权重颜色
  Color _weightColor(int weight) {
    if (weight >= 80) return const Color(0xFFDC2626);
    if (weight >= 60) return const Color(0xFFF59E0B);
    if (weight >= 40) return const Color(0xFF2563EB);
    return const Color(0xFF9CA3AF);
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('对话记忆数据'),
        centerTitle: true,
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, size: 22),
            onPressed: _openNewMemory,
            tooltip: '新建记忆',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadMemories,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _memories.isEmpty
                ? _buildEmpty()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _memories.length,
                    itemBuilder: (context, index) {
                      final m = _memories[index];
                      return _buildMemoryCard(m);
                    },
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
          Icon(Icons.auto_stories_outlined, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text(
            '还没有对话记忆',
            style: TextStyle(fontSize: 15, color: Color(0xFF9CA3AF)),
          ),
          const SizedBox(height: 8),
          const Text(
            '对话结束后 AI 会自动提炼记忆\n也可以点击右上角 + 手动新建',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFFC0C4CC)),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _openNewMemory,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新建第一条记忆'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  /// 单条记忆卡片
  Widget _buildMemoryCard(MemoryItem m) {
    final color = _weightColor(m.weight);
    return GestureDetector(
      onTap: () => _openMemoryDetail(m),
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
            // 标题行：权重 + 标题
            Row(
              children: [
                // 权重标签
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '权重 ${m.weight}',
                    style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    m.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1B1C),
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18, color: Color(0xFFC0C4CC)),
              ],
            ),
            const SizedBox(height: 10),
            // 内容摘要
            Text(
              m.content.replaceAll('\n', ' ').trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            // 标签 + 来源 + 时间
            Row(
              children: [
                // 标签
                if (m.tags.isNotEmpty) ...[
                  Icon(Icons.label_outline, size: 12, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      m.tags.take(3).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ),
                ] else
                  const Spacer(),
                // 来源标记
                if (m.source == '会话提炼') ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'AI 自动提炼',
                      style: TextStyle(fontSize: 10, color: Color(0xFF6366F1)),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (m.source == '手动提炼') ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '手动提炼',
                      style: TextStyle(fontSize: 10, color: Color(0xFF10B981)),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                // 更新时间
                Icon(Icons.access_time, size: 12, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(
                  _formatDate(m.updatedAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 打开新建记忆
  void _openNewMemory() {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => MemoryEditPage(tenantId: widget.tenantId),
        ))
        .then((saved) {
      if (saved == true) _loadMemories();
    });
  }

  /// 打开记忆详情（编辑页）
  void _openMemoryDetail(MemoryItem item) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => MemoryEditPage(
            tenantId: widget.tenantId,
            memory: item,
          ),
        ))
        .then((saved) {
      if (saved == true) _loadMemories();
    });
  }
}
