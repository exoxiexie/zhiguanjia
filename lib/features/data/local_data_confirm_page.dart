/// 确认沉淀页
///
/// 展示用户选择的文件列表，默认全选，用户可以取消某些文件不沉淀。
/// 单个文件大小限制 20MB，超限文件自动排除并提示。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../storage/local_file_store.dart';

class LocalDataConfirmPage extends StatefulWidget {
  final String tenantId;
  final String source; // device / usb
  final List<File> files;

  const LocalDataConfirmPage({
    super.key,
    required this.tenantId,
    required this.source,
    required this.files,
  });

  @override
  State<LocalDataConfirmPage> createState() => _LocalDataConfirmPageState();
}

class _LocalDataConfirmPageState extends State<LocalDataConfirmPage> {
  late Map<String, bool> _selected; // 文件路径 -> 是否选中
  late List<String> _overLimitFiles; // 超限文件名
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    // 检查文件大小限制
    _overLimitFiles = LocalFileStore.checkFileSizeLimit(widget.files);
    // 默认全选（排除超限文件）
    _selected = {
      for (final f in widget.files)
        if (!_overLimitFiles.contains(p.basename(f.path)))
          f.path: true
        else
          f.path: false,
    };
  }

  int get _selectedCount => _selected.values.where((v) => v).length;

  int get _selectedSize {
    int total = 0;
    for (final f in widget.files) {
      if (_selected[f.path] == true) {
        try {
          total += f.lengthSync();
        } catch (_) {}
      }
    }
    return total;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// 根据扩展名获取文件图标
  IconData _fileIcon(String path) {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icons.image;
      case 'zip':
      case 'rar':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _fileIconColor(String path) {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    switch (ext) {
      case 'pdf':
        return const Color(0xFFDC2626);
      case 'doc':
      case 'docx':
        return const Color(0xFF2563EB);
      case 'xls':
      case 'xlsx':
        return const Color(0xFF059669);
      case 'jpg':
      case 'jpeg':
      case 'png':
        return const Color(0xFF7C3AED);
      default:
        return const Color(0xFF6B7280);
    }
  }

  /// 执行沉淀
  Future<void> _doUpload() async {
    if (_selectedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一个文件')),
      );
      return;
    }

    setState(() => _uploading = true);
    try {
      final selectedFiles = widget.files.where((f) => _selected[f.path] == true).toList();
      await LocalFileStore.createSession(
        tenantId: widget.tenantId,
        source: widget.source,
        files: selectedFiles,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成功沉淀 $_selectedCount 个文件')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('沉淀失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('确认沉淀'),
        centerTitle: true,
        backgroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 超限提示
          if (_overLimitFiles.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: const Color(0xFFFEF3C7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber, size: 18, color: Color(0xFFD97706)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '以下 ${_overLimitFiles.length} 个文件超过 20MB 限制，已自动取消选择：\n${_overLimitFiles.take(3).join("、")}${_overLimitFiles.length > 3 ? "等" : ""}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF92400E), height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          // 统计栏
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE4E3DD))),
            ),
            child: Row(
              children: [
                Text(
                  '共 ${widget.files.length} 个文件，已选 $_selectedCount 个',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                ),
                const Spacer(),
                Text(
                  _formatSize(_selectedSize),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1B1C),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _toggleAll,
                  child: Text(
                    _isAllSelected ? '取消全选' : '全选',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          // 文件列表
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.files.length,
              itemBuilder: (context, index) {
                final file = widget.files[index];
                final fileName = p.basename(file.path);
                final isOverLimit = _overLimitFiles.contains(fileName);
                final isSelected = _selected[file.path] ?? false;

                return _buildFileItem(
                  file: file,
                  fileName: fileName,
                  isSelected: isSelected,
                  isOverLimit: isOverLimit,
                  onChanged: isOverLimit
                      ? null
                      : (val) {
                          setState(() => _selected[file.path] = val ?? false);
                        },
                );
              },
            ),
          ),
          // 底部按钮
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE4E3DD))),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _uploading ? null : _doUpload,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _uploading
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
                          Text('沉淀中...'),
                        ],
                      )
                    : Text('确认沉淀 $_selectedCount 个文件'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _isAllSelected {
    return widget.files.every((f) {
      final fileName = p.basename(f.path);
      if (_overLimitFiles.contains(fileName)) return true; // 超限文件不算
      return _selected[f.path] == true;
    });
  }

  void _toggleAll() {
    final target = !_isAllSelected;
    setState(() {
      for (final f in widget.files) {
        final fileName = p.basename(f.path);
        if (!_overLimitFiles.contains(fileName)) {
          _selected[f.path] = target;
        }
      }
    });
  }

  /// 文件列表项
  Widget _buildFileItem({
    required File file,
    required String fileName,
    required bool isSelected,
    required bool isOverLimit,
    required ValueChanged<bool?>? onChanged,
  }) {
    final iconColor = _fileIconColor(file.path);
    int fileSize = 0;
    try {
      fileSize = file.lengthSync();
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isOverLimit ? const Color(0xFFF9FAFB) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isOverLimit ? const Color(0xFFE4E3DD) : const Color(0xFFE4E3DD),
        ),
      ),
      child: Row(
        children: [
          // 复选框
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: isSelected,
              onChanged: onChanged,
              activeColor: const Color(0xFF059669),
            ),
          ),
          const SizedBox(width: 10),
          // 文件图标
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(_fileIcon(file.path), size: 18, color: iconColor),
          ),
          const SizedBox(width: 10),
          // 文件信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isOverLimit ? const Color(0xFF9CA3AF) : const Color(0xFF1A1B1C),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      _formatSize(fileSize),
                      style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                    ),
                    if (isOverLimit) ...[
                      const SizedBox(width: 8),
                      const Text(
                        '超过20MB',
                        style: TextStyle(fontSize: 11, color: Color(0xFFDC2626)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
