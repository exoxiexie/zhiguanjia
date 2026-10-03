/// 记忆详情/编辑页
library;

import 'package:flutter/material.dart';

import '../storage/memory_store.dart';

class MemoryEditPage extends StatefulWidget {
  final String tenantId;
  final MemoryItem? memory; // 为 null 表示新建

  const MemoryEditPage({
    super.key,
    required this.tenantId,
    this.memory,
  });

  @override
  State<MemoryEditPage> createState() => _MemoryEditPageState();
}

class _MemoryEditPageState extends State<MemoryEditPage> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late TextEditingController _tagsController;
  late double _weight;
  bool _isNew = false;

  @override
  void initState() {
    super.initState();
    _isNew = widget.memory == null;
    final m = widget.memory;
    _titleController = TextEditingController(text: m?.title ?? '');
    _contentController = TextEditingController(text: m?.content ?? '');
    _tagsController = TextEditingController(text: m?.tags.join(', ') ?? '');
    _weight = (m?.weight ?? 50).toDouble();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入标题')),
      );
      return;
    }

    final item = MemoryItem(
      id: widget.memory?.id ?? MemoryItem.safeId(title),
      title: title,
      weight: _weight.round(),
      tags: _tagsController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      content: _contentController.text,
      createdAt: widget.memory?.createdAt ?? DateTime.now(),
    );

    await MemoryStore.save(widget.tenantId, item);
    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _delete() async {
    if (widget.memory == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除「${widget.memory!.title}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await MemoryStore.delete(widget.tenantId, widget.memory!.id);
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? '新建记忆' : '编辑记忆'),
        actions: [
          if (!_isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _save,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            const Text('标题', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                hintText: '输入记忆标题',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 20),

            // 权重
            Row(
              children: [
                const Text('权重', style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${_weight.round()} 分',
                    style: const TextStyle(color: Colors.blue)),
              ],
            ),
            Slider(
              value: _weight,
              min: 0,
              max: 100,
              divisions: 100,
              label: '${_weight.round()}',
              onChanged: (v) => setState(() => _weight = v),
            ),
            const SizedBox(height: 12),

            // 标签
            const Text('标签（用逗号分隔）',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _tagsController,
              decoration: const InputDecoration(
                hintText: '例如：产品定位, AI管家, 主动式',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 20),

            // 内容
            const Text('内容（Markdown）',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _contentController,
              maxLines: 15,
              decoration: const InputDecoration(
                hintText: '输入记忆内容，支持 Markdown 格式',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),

            // 元信息
            if (widget.memory != null) ...[
              Text(
                '创建于 ${_formatDate(widget.memory!.createdAt)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              Text(
                '更新于 ${_formatDate(widget.memory!.updatedAt)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
