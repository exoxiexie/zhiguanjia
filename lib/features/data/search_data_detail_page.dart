/// 联网搜索数据详情页
///
/// 展示单条搜索数据的MD内容和元数据，支持编辑和删除。
library;

import 'package:flutter/material.dart';

import '../../contracts/chat_service.dart';
import '../storage/search_data_store.dart';
import 'search_data_edit_page.dart';

class SearchDataDetailPage extends StatefulWidget {
  final String tenantId;
  final String itemId;

  const SearchDataDetailPage({
    super.key,
    required this.tenantId,
    required this.itemId,
  });

  @override
  State<SearchDataDetailPage> createState() => _SearchDataDetailPageState();
}

class _SearchDataDetailPageState extends State<SearchDataDetailPage> {
  SearchDataItem? _item;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadItem();
  }

  Future<void> _loadItem() async {
    setState(() => _loading = true);
    try {
      final item = await SearchDataStore.getById(widget.tenantId, widget.itemId);
      if (mounted) setState(() => _item = item);
    } catch (e) {
      debugPrint('加载搜索数据详情失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// 简单的MD渲染（处理标题、列表、粗体等基本格式）
  Widget _renderMarkdown(String content) {
    final lines = content.split('\n');
    final widgets = <Widget>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }
      // 标题
      if (trimmed.startsWith('# ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Text(
            trimmed.substring(2),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1B1C)),
          ),
        ));
        continue;
      }
      if (trimmed.startsWith('## ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Text(
            trimmed.substring(3),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1B1C)),
          ),
        ));
        continue;
      }
      if (trimmed.startsWith('### ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            trimmed.substring(4),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
          ),
        ));
        continue;
      }
      // 无序列表
      if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('• ', style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
              Expanded(child: Text(trimmed.substring(2), style: const TextStyle(fontSize: 14, color: Color(0xFF374151), height: 1.5))),
            ],
          ),
        ));
        continue;
      }
      // 有序列表
      if (RegExp(r'^\d+\.\s').hasMatch(trimmed)) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${trimmed.split('.').first}. ', style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
              Expanded(child: Text(trimmed.replaceFirst(RegExp(r'^\d+\.\s'), ''), style: const TextStyle(fontSize: 14, color: Color(0xFF374151), height: 1.5))),
            ],
          ),
        ));
        continue;
      }
      // 普通段落
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(trimmed, style: const TextStyle(fontSize: 14, color: Color(0xFF374151), height: 1.6)),
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索数据详情'),
        centerTitle: true,
        backgroundColor: Colors.white,
        actions: [
          if (_item != null)
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              onPressed: () {
                Navigator.of(context)
                    .push(MaterialPageRoute(
                      builder: (_) => SearchDataEditPage(
                        tenantId: widget.tenantId,
                        item: _item,
                      ),
                    ))
                    .then((_) => _loadItem());
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _item == null
              ? const Center(child: Text('数据不存在'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // 元数据卡片
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE4E3DD)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 权重 + 进上下文标记
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _item!.weightColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '权重 ${_item!.weight}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: _item!.weightColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (_item!.inContext)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFECFDF5),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    '已进入对话上下文',
                                    style: TextStyle(fontSize: 11, color: Color(0xFF059669)),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildMetaRow('搜索关键词', _item!.searchQuery),
                          _buildMetaRow('搜索来源', _item!.source),
                          if (_item!.tags.isNotEmpty) _buildMetaRow('标签', _item!.tags.join('、')),
                          _buildMetaRow('创建时间', _formatDate(_item!.createdAt)),
                          _buildMetaRow('更新时间', _formatDate(_item!.updatedAt)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 内容标题
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        '提炼内容',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF6B7280)),
                      ),
                    ),
                    // MD内容
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE4E3DD)),
                      ),
                      child: _renderMarkdown(_item!.content),
                    ),
                    const SizedBox(height: 16),
                    // 信源列表（备注，可折叠）
                    if (_item!.sources.isNotEmpty)
                      _buildSourcesSection(_item!.sources),
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }

  Widget _buildMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
            ),
          ),
        ],
      ),
    );
  }

  /// 信源列表折叠区域
  Widget _buildSourcesSection(List<SearchSource> sources) {
    return StatefulBuilder(
      builder: (context, setDialogState) {
        bool expanded = false;
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE4E3DD)),
              ),
              child: Column(
                children: [
                  // 标题行（可点击展开/折叠）
                  GestureDetector(
                    onTap: () => setState(() => expanded = !expanded),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.link, size: 18, color: Color(0xFF6B7280)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '本次搜索信源（${sources.length}个）',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ),
                          Icon(
                            expanded ? Icons.expand_less : Icons.expand_more,
                            size: 20,
                            color: const Color(0xFF9CA3AF),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 展开后的信源列表
                  if (expanded)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(height: 1, color: Color(0xFFF0F0F0)),
                          const SizedBox(height: 12),
                          for (var i = 0; i < sources.length; i++) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${i + 1}.',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          sources[i].title,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: Color(0xFF374151),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          sources[i].url,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF2563EB),
                                            decoration: TextDecoration.underline,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
