/// 本地私有数据详情页
///
/// 三个卡片：
/// 1. 上传历史 — 已沉淀到云端的文件记录
/// 2. 打开本设备文件夹 — 从手机/电脑选择文件
/// 3. 插入U盘或移动硬盘 — 外接存储设备选择文件
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../storage/local_file_store.dart';
import 'local_data_history_page.dart';
import 'local_data_confirm_page.dart';

class LocalDataDetailPage extends StatefulWidget {
  final String tenantId;

  const LocalDataDetailPage({super.key, required this.tenantId});

  @override
  State<LocalDataDetailPage> createState() => _LocalDataDetailPageState();
}

class _LocalDataDetailPageState extends State<LocalDataDetailPage> {
  int _totalFileCount = 0;
  DateTime? _lastUploadTime;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    try {
      final count = await LocalFileStore.getTotalFileCount(widget.tenantId);
      final lastTime = await LocalFileStore.getLastUploadTime(widget.tenantId);
      if (mounted) {
        setState(() {
          _totalFileCount = count;
          _lastUploadTime = lastTime;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// 从本设备选择文件
  Future<void> _pickFromDevice() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) return;

      final files = result.files
          .where((f) => f.path != null)
          .map((f) => File(f.path!))
          .toList();

      if (!mounted) return;
      Navigator.of(context)
          .push(MaterialPageRoute(
            builder: (_) => LocalDataConfirmPage(
              tenantId: widget.tenantId,
              source: 'device',
              files: files,
            ),
          ))
          .then((_) => _loadStats());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择文件失败：$e')),
      );
    }
  }

  /// 从U盘/移动硬盘选择文件
  Future<void> _pickFromUsb() async {
    // 移动端U盘需要OTG，file_picker 可以访问外接存储
    // 先提示用户插入设备，然后调用文件选择器
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('插入U盘或移动硬盘'),
        content: const Text('请将U盘或移动硬盘插入设备，插入后点击"继续"选择文件。\n\n注意：手机需要支持OTG功能才能读取U盘。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                final result = await FilePicker.platform.pickFiles(
                  allowMultiple: true,
                  type: FileType.any,
                );
                if (result == null || result.files.isEmpty) return;

                final files = result.files
                    .where((f) => f.path != null)
                    .map((f) => File(f.path!))
                    .toList();

                if (!mounted) return;
                Navigator.of(context)
                    .push(MaterialPageRoute(
                      builder: (_) => LocalDataConfirmPage(
                        tenantId: widget.tenantId,
                        source: 'usb',
                        files: files,
                      ),
                    ))
                    .then((_) => _loadStats());
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('选择文件失败：$e')),
                );
              }
            },
            child: const Text('继续'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地私有数据'),
        centerTitle: true,
        backgroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _loadStats,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 卡片1：上传历史
            _buildActionCard(
              icon: Icons.history,
              color: const Color(0xFF059669),
              title: '上传历史',
              subtitle: _loading
                  ? '加载中...'
                  : _totalFileCount == 0
                      ? '还没有沉淀的文件'
                      : '已沉淀 $_totalFileCount 个文件'
                          '${_lastUploadTime != null ? '\n最近沉淀：${_formatDate(_lastUploadTime!)}' : ''}',
              onTap: () {
                Navigator.of(context)
                    .push(MaterialPageRoute(
                      builder: (_) => LocalDataHistoryPage(tenantId: widget.tenantId),
                    ))
                    .then((_) => _loadStats());
              },
            ),
            const SizedBox(height: 12),
            // 卡片2：打开本设备文件夹
            _buildActionCard(
              icon: Icons.folder_open,
              color: const Color(0xFF2563EB),
              title: '从手机/电脑选择文件',
              subtitle: '打开本设备的文件管理器，选择文件后沉淀到云端',
              onTap: _pickFromDevice,
            ),
            const SizedBox(height: 12),
            // 卡片3：插入U盘或移动硬盘
            _buildActionCard(
              icon: Icons.usb,
              color: const Color(0xFF7C3AED),
              title: '插入U盘或移动硬盘',
              subtitle: '插入外接存储设备，选择文件后沉淀到云端',
              onTap: _pickFromUsb,
            ),
            const SizedBox(height: 24),
            // 提示信息
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE4E3DD)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: Color(0xFF6B7280)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '单个文件大小限制 20MB，文件数量和类型不限制。选择文件后可确认哪些需要沉淀，默认全部沉淀。',
                      style: TextStyle(fontSize: 12, color: Color(0xFF6B7280), height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 操作卡片
  Widget _buildActionCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE4E3DD)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 24, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Color(0xFFC0C4CC)),
          ],
        ),
      ),
    );
  }
}
