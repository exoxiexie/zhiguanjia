/// 经历详情页（教育 / 工作 / 培训共用）
///
/// **入口**：数据页的三张通栏卡片（教育经历 / 工作经历 / 培训经历）。
///
/// **这是「详情」而非「列表」**：每条经历卡片直接把该类型的**全部已填字段**
/// 平铺出来（主字段 + 起止时间 + 其余字段），用户点进来就能看全，
/// 不需要再点第二层；点击卡片进入编辑，右下角「＋」新增。
///
/// 同一份 UI 由 [ExperienceKind] 的描述表驱动，三类经历零重复代码。
library;

import 'package:flutter/material.dart';

import 'experience_edit_page.dart';
import 'experience_models.dart';
import 'experience_store.dart';

/// 品牌活力橙
const Color _kBrandOrange = Color(0xFFFD5C13);

const Color _kPageBg = Color(0xFFF5F5F5);
const Color _kTitleColor = Color(0xFF1A1B1C);
const Color _kBodyColor = Color(0xFF6B7280);
const Color _kMetaColor = Color(0xFF9CA3AF);

class ExperienceListPage extends StatefulWidget {
  /// 经历类型（决定标题、字段与卡片摘要）
  final ExperienceKind kind;

  const ExperienceListPage({super.key, required this.kind});

  @override
  State<ExperienceListPage> createState() => _ExperienceListPageState();
}

class _ExperienceListPageState extends State<ExperienceListPage> {
  List<ExperienceEntry> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await ExperienceStore.listByKind(widget.kind.id);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  /// 新增（entry 为 null）或编辑；保存后重新拉取
  Future<void> _openEditor([ExperienceEntry? entry]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ExperienceEditPage(kind: widget.kind, entry: entry),
      ),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kPageBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: _kTitleColor),
        title: Text(
          widget.kind.label,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: _kTitleColor,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _buildEmpty()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                  children: [for (final e in _items) _buildCard(e)],
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        backgroundColor: _kBrandOrange,
        foregroundColor: Colors.white,
        elevation: 4,
        tooltip: '添加${widget.kind.label}',
        child: const Icon(Icons.add, size: 30),
      ),
    );
  }

  /// 单条经历卡片：主字段 + 起止时间 + 其余已填字段
  Widget _buildCard(ExperienceEntry entry) {
    final kind = widget.kind;
    final range = entry.rangeText(kind);

    // 除主字段与时间字段外，其余已填字段平铺展示
    final extras = <Widget>[];
    for (final f in kind.fields) {
      if (f.primary || f.type == ExperienceFieldType.month) continue;
      final v = entry.v(f.key);
      if (v.isEmpty) continue;
      extras.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 60,
              child: Text(
                f.label,
                style: const TextStyle(fontSize: 13, color: _kMetaColor),
              ),
            ),
            Expanded(
              child: Text(
                f.type == ExperienceFieldType.multiline
                    ? v.replaceAll('\n', ' ')
                    : v,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14, height: 1.4, color: _kBodyColor),
              ),
            ),
          ],
        ),
      ));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openEditor(entry),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        entry.primaryOf(kind),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _kTitleColor,
                        ),
                      ),
                    ),
                    if (range.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Text(
                        range,
                        style:
                            const TextStyle(fontSize: 12, color: _kMetaColor),
                      ),
                    ],
                  ],
                ),
                ...extras,
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 空态：引导点右下角「＋」新增第一条
  Widget _buildEmpty() {
    return ListView(
      children: [
        const SizedBox(height: 100),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: widget.kind.color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.kind.icon,
                    size: 34, color: widget.kind.color),
              ),
              const SizedBox(height: 16),
              Text(
                '还没有${widget.kind.label}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: _kTitleColor,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  widget.kind.subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, color: _kMetaColor, height: 1.6),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => _openEditor(),
                style: FilledButton.styleFrom(
                  backgroundColor: _kBrandOrange,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 10),
                ),
                child: Text('添加${widget.kind.label}'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
