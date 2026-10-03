/// 联网搜索数据编辑页
///
/// 支持新建和编辑搜索数据，包含标题、权重滑块、标签、搜索关键词、MD内容。
library;

import 'package:flutter/material.dart';

import '../storage/search_data_store.dart';

class SearchDataEditPage extends StatefulWidget {
  final String tenantId;
  final SearchDataItem? item; // 为null时是新建

  const SearchDataEditPage({
    super.key,
    required this.tenantId,
    this.item,
  });

  @override
  State<SearchDataEditPage> createState() => _SearchDataEditPageState();
}

class _SearchDataEditPageState extends State<SearchDataEditPage> {
  late TextEditingController _titleController;
  late TextEditingController _queryController;
  late TextEditingController _tagsController;
  late TextEditingController _contentController;
  late double _weight;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _titleController = TextEditingController(text: item?.title ?? '');
    _queryController = TextEditingController(text: item?.searchQuery ?? '');
    _tagsController = TextEditingController(text: item?.tags.join(', ') ?? '');
    _contentController = TextEditingController(text: item?.content ?? '');
    _weight = (item?.weight ?? SearchDataStore.defaultWeight).toDouble();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _queryController.dispose();
    _tagsController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Color _weightColor(int weight) {
    if (weight >= 80) return const Color(0xFFDC2626);
    if (weight >= 60) return const Color(0xFFF59E0B);
    if (weight >= 40) return const Color(0xFF2563EB);
    return const Color(0xFF9CA3AF);
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final query = _queryController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入标题')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final tags = _tagsController.text
          .split(RegExp(r'[,，]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      if (widget.item == null) {
        // 新建
        await SearchDataStore.create(
          tenantId: widget.tenantId,
          title: title,
          searchQuery: query,
          content: content,
          tags: tags,
          weight: _weight.toInt(),
        );
      } else {
        // 编辑
        await SearchDataStore.update(
          widget.tenantId,
          widget.item!.copyWith(
            title: title,
            searchQuery: query,
            content: content,
            tags: tags,
            weight: _weight.toInt(),
          ),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存成功')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item == null ? '新建搜索数据' : '编辑搜索数据'),
        centerTitle: true,
        backgroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(
              '保存',
              style: TextStyle(
                fontSize: 15,
                color: _saving ? Colors.grey : const Color(0xFF059669),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 标题
          _buildSectionLabel('标题'),
          TextField(
            controller: _titleController,
            decoration: _inputDecoration('请输入标题'),
          ),
          const SizedBox(height: 16),
          // 搜索关键词
          _buildSectionLabel('搜索关键词'),
          TextField(
            controller: _queryController,
            decoration: _inputDecoration('请输入搜索关键词'),
          ),
          const SizedBox(height: 16),
          // 标签
          _buildSectionLabel('标签（用逗号分隔）'),
          TextField(
            controller: _tagsController,
            decoration: _inputDecoration('例如：行业动态, 政策, 新能源'),
          ),
          const SizedBox(height: 16),
          // 权重
          _buildSectionLabel('权重'),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE4E3DD)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('权重值', style: TextStyle(fontSize: 14)),
                    Text(
                      '${_weight.toInt()}',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: _weightColor(_weight.toInt()),
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _weight,
                  min: 0,
                  max: 100,
                  divisions: 100,
                  label: '${_weight.toInt()}',
                  activeColor: _weightColor(_weight.toInt()),
                  onChanged: (val) => setState(() => _weight = val),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _weight >= SearchDataStore.contextThreshold
                        ? '权重 ≥ ${SearchDataStore.contextThreshold}，会自动进入对话上下文'
                        : '权重 < ${SearchDataStore.contextThreshold}，不会进入对话上下文',
                    style: TextStyle(
                      fontSize: 12,
                      color: _weight >= SearchDataStore.contextThreshold
                          ? const Color(0xFF059669)
                          : const Color(0xFF6B7280),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 内容
          _buildSectionLabel('提炼内容（Markdown格式）'),
          TextField(
            controller: _contentController,
            maxLines: 15,
            decoration: _inputDecoration('请输入提炼后的搜索结果摘要，支持Markdown格式'),
          ),
          const SizedBox(height: 24),
          // 保存按钮
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _saving
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        SizedBox(width: 8),
                        Text('保存中...'),
                      ],
                    )
                  : const Text('保存'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF6B7280),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFC0C4CC)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE4E3DD)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE4E3DD)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF059669)),
      ),
    );
  }
}
