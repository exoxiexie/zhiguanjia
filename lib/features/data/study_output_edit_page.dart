/// 自主学习 · 成果编辑页（职管家 · 个人职业版）
///
/// **一条成果由四部分组成**：标题（必填）、文字说明、图片、附件（PDF）。
/// 图片与附件都先经 [StudyFileStore] 复制进应用私有目录再入库，
/// 不能直接存系统临时路径 —— 否则过一段时间图片会裂、PDF 会打不开。
///
/// **孤儿文件处理**（这里比写说说多一种情况，因为要编辑"旧文件"）：
/// - 本次**新加入**的文件登记在 `_added`，未保存就退出时在 dispose 里回收；
/// - 从**已有成果**里移出的旧文件只登记在 `_removed`、**不立即删**，
///   等保存成功后才真正删除 —— 否则用户中途放弃编辑，
///   原成果引用的文件已经没了，回来就是一条裂图成果。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'study_file_store.dart';
import 'study_output_store.dart';

/// 品牌活力橙
const Color _kBrandOrange = Color(0xFFFD5C13);

const Color _kPageBg = Color(0xFFF5F5F5);
const Color _kTitleColor = Color(0xFF1A1B1C);
const Color _kLabelColor = Color(0xFF6B7280);
const Color _kHintColor = Color(0xFFB5B9C0);
const Color _kInputBg = Color(0xFFF7F8FA);
const Color _kDanger = Color(0xFFEF4444);

/// 图片方块边长（图片方块与「＋」方块**等大**，视觉上成一组）
const double _kTileSize = 88;

/// 图片与附件数量上限
const int _kMaxImages = 9;
const int _kMaxFiles = 9;

class StudyOutputEditPage extends StatefulWidget {
  /// 被编辑的成果；为 null 表示新增
  final StudyOutput? output;

  const StudyOutputEditPage({super.key, this.output});

  @override
  State<StudyOutputEditPage> createState() => _StudyOutputEditPageState();
}

class _StudyOutputEditPageState extends State<StudyOutputEditPage> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;

  /// 图片（私有目录绝对路径）
  final List<String> _images = [];

  /// 附件（PDF 等）
  final List<StudyAttachment> _files = [];

  /// 本次新落盘、尚未归属成果的文件 —— 未保存退出时回收
  final List<String> _added = [];

  /// 本次从成果里移出的旧文件 —— 保存成功后才真正删除
  final List<String> _removed = [];

  bool _saving = false;

  /// 是否已成功保存：为 true 时退出不回收 `_added`（文件已归成果所有）
  bool _saved = false;

  /// 选图 / 选文件期间忽略重复点击
  bool _picking = false;

  bool get _isNew => widget.output == null;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.output?.title ?? '');
    _contentCtrl = TextEditingController(text: widget.output?.content ?? '');
    _images.addAll(widget.output?.images ?? const <String>[]);
    _files.addAll(widget.output?.files ?? const <StudyAttachment>[]);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    // 未保存就退出 → 回收本次新落盘的文件，避免私有目录堆积孤儿文件
    if (!_saved && _added.isNotEmpty) {
      StudyFileStore.removeAll(List.of(_added));
    }
    super.dispose();
  }

  // ── 选图 ────────────────────────────────────────────────────

  /// 弹出图片来源选择（拍照 / 从相册选择），与「更换头像」「写说说」同一交互
  Future<void> _showImageSheet() async {
    if (_images.length >= _kMaxImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最多添加 $_kMaxImages 张图片')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                '添加图片',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _kTitleColor,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: Color(0xFF5B7FD4)),
              title: const Text('拍照'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImages(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: Color(0xFF5B7FD4)),
              title: const Text('从相册选择'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImages(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  /// 选图 → 复制进私有目录 → 追加到预览列表
  Future<void> _pickImages(ImageSource source) async {
    if (_picking) return;
    _picking = true;
    try {
      final picker = ImagePicker();
      final List<XFile> picked;
      if (source == ImageSource.gallery) {
        // 相册支持多选，便于一次挑好几张
        picked = await picker.pickMultiImage(
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
        );
      } else {
        final one = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
        );
        picked = one == null ? const <XFile>[] : [one];
      }
      if (picked.isEmpty) return; // 用户取消

      final remain = _kMaxImages - _images.length;
      final saved = await StudyFileStore.saveAll(
        picked.take(remain).map((e) => e.path),
      );
      if (!mounted) return;
      setState(() {
        _images.addAll(saved);
        _added.addAll(saved);
      });
      if (picked.length > remain) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('最多添加 $_kMaxImages 张图片，多余的已忽略')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('添加图片失败：$e')),
      );
    } finally {
      _picking = false;
    }
  }

  /// 移除一张图片
  void _removeImage(int index) {
    final path = _images.removeAt(index);
    if (_added.remove(path)) {
      // 本次新加的：直接删文件
      StudyFileStore.removeAll([path]);
    } else {
      // 成果原有的：登记，保存成功后再删
      _removed.add(path);
    }
    setState(() {});
  }

  // ── 选 PDF 附件 ─────────────────────────────────────────────

  /// 选 PDF → 复制进私有目录 → 追加到附件列表
  Future<void> _pickFiles() async {
    if (_picking) return;
    if (_files.length >= _kMaxFiles) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最多添加 $_kMaxFiles 个附件')),
      );
      return;
    }
    _picking = true;
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true,
      );
      final picked = res?.files ?? const <PlatformFile>[];
      if (picked.isEmpty) return; // 用户取消

      final remain = _kMaxFiles - _files.length;
      final out = <StudyAttachment>[];
      for (final f in picked.take(remain)) {
        final path = f.path;
        if (path == null || path.isEmpty) continue;
        final savedPath = await StudyFileStore.save(path);
        out.add(StudyAttachment(path: savedPath, name: f.name, size: f.size));
      }
      if (!mounted || out.isEmpty) return;
      setState(() {
        _files.addAll(out);
        _added.addAll(out.map((e) => e.path));
      });
      if (picked.length > remain) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('最多添加 $_kMaxFiles 个附件，多余的已忽略')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('添加附件失败：$e')),
      );
    } finally {
      _picking = false;
    }
  }

  /// 移除一个附件
  void _removeFile(int index) {
    final f = _files.removeAt(index);
    if (_added.remove(f.path)) {
      StudyFileStore.removeAll([f.path]);
    } else {
      _removed.add(f.path);
    }
    setState(() {});
  }

  // ── 保存 / 删除 ─────────────────────────────────────────────

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写「标题」')),
      );
      return;
    }

    setState(() => _saving = true);
    final now = DateTime.now().millisecondsSinceEpoch;
    await StudyOutputStore.save(StudyOutput(
      id: widget.output?.id ?? '${now}_study',
      title: title,
      content: _contentCtrl.text.trim(),
      images: List.of(_images),
      files: List.of(_files),
      createdAt: widget.output?.createdAt ?? now,
      updatedAt: now,
    ));
    _saved = true; // 文件已归属这条成果，退出时不再回收
    // 保存成功后才真正删除本次从成果里移出的旧文件
    if (_removed.isNotEmpty) {
      await StudyFileStore.removeAll(List.of(_removed));
    }
    if (mounted) Navigator.pop(context, true);
  }

  /// 删除成果（连同它的图片与附件一起删，二次确认）
  Future<void> _delete() async {
    final output = widget.output;
    if (output == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条学习成果？'),
        content: const Text('成果里的图片与附件会一并删除，不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: _kLabelColor)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: _kDanger)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await StudyOutputStore.delete(output.id);
    await StudyFileStore.removeAll([
      ...output.images,
      ...output.files.map((e) => e.path),
      ..._added,
    ]);
    _added.clear();
    _saved = true; // 文件已随成果删掉，退出时不再重复清理
    if (mounted) Navigator.pop(context, true);
  }

  // ── 视图 ────────────────────────────────────────────────────

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
          _isNew ? '新增学习成果' : '编辑学习成果',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: _kTitleColor,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(
              '保存',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _saving ? _kHintColor : _kBrandOrange,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLabel('标题', isRequired: true),
                _buildInput(
                  _titleCtrl,
                  hint: '如：基于大模型的简历智能优化研究',
                  maxLines: 1,
                ),
                const SizedBox(height: 18),
                _buildLabel('内容'),
                _buildInput(
                  _contentCtrl,
                  hint: '研究背景、方法、结论，或这段学习的收获…',
                  maxLines: 5,
                ),
                const SizedBox(height: 18),
                _buildLabel('图片'),
                _buildImageGrid(),
                const SizedBox(height: 18),
                _buildLabel('附件（PDF）'),
                _buildFileList(),
              ],
            ),
          ),
          if (!_isNew) ...[
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _delete,
                  child: const SizedBox(
                    height: 52,
                    child: Center(
                      child: Text(
                        '删除这条学习成果',
                        style: TextStyle(fontSize: 15, color: _kDanger),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 字段标签（必填带 *）
  Widget _buildLabel(String text, {bool isRequired = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          text: text,
          style: const TextStyle(fontSize: 13, color: _kLabelColor),
          children: [
            if (isRequired)
              const TextSpan(
                text: ' *',
                style: TextStyle(color: _kDanger, fontSize: 13),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(
    TextEditingController controller, {
    required String hint,
    required int maxLines,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 15, color: _kTitleColor),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 15, color: _kHintColor),
        filled: true,
        fillColor: _kInputBg,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  /// 配图区：已选图片方块 + 「＋」方块（与写说说同一形态）
  Widget _buildImageGrid() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int i = 0; i < _images.length; i++) _buildImageTile(i),
        if (_images.length < _kMaxImages) _buildAddImageTile(),
      ],
    );
  }

  Widget _buildImageTile(int index) {
    return SizedBox(
      width: _kTileSize,
      height: _kTileSize,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(_images[index]),
              width: _kTileSize,
              height: _kTileSize,
              fit: BoxFit.cover,
              // 文件被清理/解码失败时回落占位，避免裂图
              errorBuilder: (_, __, ___) => Container(
                width: _kTileSize,
                height: _kTileSize,
                color: const Color(0xFFF3F4F6),
                child: const Icon(Icons.broken_image_outlined,
                    color: Color(0xFFB5B9C0)),
              ),
            ),
          ),
          Positioned(
            right: 2,
            top: 2,
            child: GestureDetector(
              onTap: () => _removeImage(index),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 「＋」方块：与图片方块**等大**，点一下即进入选图
  Widget _buildAddImageTile() {
    return GestureDetector(
      onTap: _showImageSheet,
      child: Container(
        width: _kTileSize,
        height: _kTileSize,
        decoration: BoxDecoration(
          color: const Color(0xFFF2F3F5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.add, size: 34, color: Color(0xFF8A8F98)),
      ),
    );
  }

  /// 附件区：已选附件列表 + 「添加 PDF 附件」入口
  Widget _buildFileList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < _files.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildFileRow(i),
          ),
        if (_files.length < _kMaxFiles)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _pickFiles,
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: const Text('添加 PDF 附件'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kBrandOrange,
                side: const BorderSide(color: Color(0xFFE5E7EB)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFileRow(int index) {
    final f = _files[index];
    final size = StudyFileStore.formatSize(f.size);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kInputBg,
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
              style: const TextStyle(fontSize: 12, color: _kHintColor),
            ),
          ],
          GestureDetector(
            onTap: () => _removeFile(index),
            child: const Padding(
              padding: EdgeInsets.only(left: 10),
              child: Icon(Icons.close, size: 18, color: _kHintColor),
            ),
          ),
        ],
      ),
    );
  }
}
