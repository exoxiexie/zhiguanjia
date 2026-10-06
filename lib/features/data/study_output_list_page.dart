/// 自主学习 · 成果列表页（职管家 · 个人职业版）
///
/// **入口**：数据页「自主学习」通栏卡片（技能培训卡下方）。
///
/// **这里展示什么**：自主式学习的成果 —— 研究报告、论文，
/// 尤其是借助 AI 完成的研究式学习产出。每条成果可直接看到
/// **标题 + 文字 + 图片 + PDF 附件**，点卡片进编辑，右下角「＋」新增。
///
/// **PDF 的呈现方式**：项目未接入 PDF 预览组件（`syncfusion_flutter_pdf`
/// 只能提取文本、不能渲染页面），因此附件以「文件卡」形式展示，
/// 点击调用系统 PDF 阅读器打开 —— 与「我的」页打开简历、数据页打开
/// 本地资料用的是同一套 [OpenFilex] 机制，不引入任何新依赖。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../common/app_fab.dart';
import 'study_file_store.dart';
import 'study_output_edit_page.dart';
import 'study_output_store.dart';

/// 品牌活力橙
const Color _kBrandOrange = Color(0xFFFD5C13);

const Color _kPageBg = Color(0xFFF5F5F5);
const Color _kTitleColor = Color(0xFF1A1B1C);
const Color _kBodyColor = Color(0xFF6B7280);
const Color _kMetaColor = Color(0xFF9CA3AF);

/// 卡片内图片缩略图边长
const double _kThumbSize = 88;

class StudyOutputListPage extends StatefulWidget {
  const StudyOutputListPage({super.key});

  @override
  State<StudyOutputListPage> createState() => _StudyOutputListPageState();
}

class _StudyOutputListPageState extends State<StudyOutputListPage> {
  List<StudyOutput> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await StudyOutputStore.loadAll();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  /// 新增（output 为 null）或编辑；保存后重新拉取
  Future<void> _openEditor([StudyOutput? output]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StudyOutputEditPage(output: output),
      ),
    );
    if (changed == true) await _load();
  }

  /// 用系统阅读器打开附件（PDF）
  Future<void> _openAttachment(StudyAttachment f) async {
    if (f.path.isEmpty) return;
    try {
      final res = await OpenFilex.open(f.path);
      if (res.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开附件：${res.message}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开附件：$e')),
      );
    }
  }

  /// 全屏查看图片
  void _previewImages(List<String> images, int index) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (_) => _ImageViewer(images: images, initialIndex: index),
    );
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
        title: const Text(
          '自主学习',
          style: TextStyle(
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
                  children: [for (final o in _items) _buildCard(o)],
                ),
      floatingActionButton: AppFab(
        onPressed: () => _openEditor(),
        tooltip: '添加学习成果',
      ),
    );
  }

  /// 单条成果卡片：标题 + 时间 + 文字 + 图片 + 附件
  Widget _buildCard(StudyOutput o) {
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
          onTap: () => _openEditor(o),
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
                        o.displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _kTitleColor,
                        ),
                      ),
                    ),
                    if (_dateText(o.updatedAt).isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Text(
                        _dateText(o.updatedAt),
                        style: const TextStyle(
                            fontSize: 12, color: _kMetaColor),
                      ),
                    ],
                  ],
                ),
                if (o.content.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    o.content.replaceAll('\n', ' '),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, height: 1.5, color: _kBodyColor),
                  ),
                ],
                if (o.images.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (int i = 0; i < o.images.length; i++)
                        _buildThumb(o.images, i),
                    ],
                  ),
                ],
                for (final f in o.files) _buildAttachmentRow(f),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 图片缩略图（点击全屏查看）
  Widget _buildThumb(List<String> images, int index) {
    return GestureDetector(
      onTap: () => _previewImages(images, index),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(images[index]),
          width: _kThumbSize,
          height: _kThumbSize,
          fit: BoxFit.cover,
          // 文件被清理/解码失败时回落占位，避免裂图
          errorBuilder: (_, __, ___) => Container(
            width: _kThumbSize,
            height: _kThumbSize,
            color: const Color(0xFFF3F4F6),
            child: const Icon(Icons.broken_image_outlined,
                color: Color(0xFFB5B9C0)),
          ),
        ),
      ),
    );
  }

  /// 附件行（点击用系统阅读器打开）
  Widget _buildAttachmentRow(StudyAttachment f) {
    final size = StudyFileStore.formatSize(f.size);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: () => _openAttachment(f),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F8FA),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.picture_as_pdf_outlined,
                  size: 20, color: Color(0xFFE0563F)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  f.name.isEmpty ? 'PDF 附件' : f.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: _kTitleColor),
                ),
              ),
              if (size.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  size,
                  style: const TextStyle(fontSize: 12, color: _kMetaColor),
                ),
              ],
              const SizedBox(width: 6),
              const Icon(Icons.open_in_new, size: 15, color: _kMetaColor),
            ],
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
                  color: _kBrandOrange.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.science_outlined,
                    size: 34, color: _kBrandOrange),
              ),
              const SizedBox(height: 16),
              const Text(
                '还没有学习成果',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: _kTitleColor,
                ),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  '研究报告、论文，或借助 AI 完成的研究式学习产出\n都可以记在这里，支持文字、图片与 PDF 附件',
                  textAlign: TextAlign.center,
                  style: TextStyle(
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
                child: const Text('添加学习成果'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// `2026.10.06`（时间戳为 0 时返回空串）
  String _dateText(int ms) {
    if (ms <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year}.${d.month.toString().padLeft(2, '0')}'
        '.${d.day.toString().padLeft(2, '0')}';
  }
}

/// 全屏图片查看（黑底，支持双指缩放与多图左右翻页）
class _ImageViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _ImageViewer({required this.images, required this.initialIndex});

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: widget.images.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) => InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(
              child: Image.file(
                File(widget.images[i]),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image_outlined,
                  size: 48,
                  color: Colors.white54,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: SafeArea(
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white, size: 26),
            ),
          ),
        ),
        if (widget.images.length > 1)
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                '${_index + 1} / ${widget.images.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ),
      ],
    );
  }
}
