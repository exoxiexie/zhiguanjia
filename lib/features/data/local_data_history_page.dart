/// 本地文件上传历史列表页
///
/// 展示所有沉淀会话，按时间倒序排列。
/// 点击会话进入详情页，展示该次沉淀的所有文件。
library;

import 'package:flutter/material.dart';

import '../storage/local_file_store.dart';
import 'local_data_session_detail_page.dart';

class LocalDataHistoryPage extends StatefulWidget {
  final String tenantId;

  const LocalDataHistoryPage({super.key, required this.tenantId});

  @override
  State<LocalDataHistoryPage> createState() => _LocalDataHistoryPageState();
}

class _LocalDataHistoryPageState extends State<LocalDataHistoryPage> {
  List<LocalUploadSession> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _loading = true);
    try {
      final list = await LocalFileStore.listSessions(widget.tenantId);
      if (mounted) setState(() => _sessions = list);
    } catch (e) {
      debugPrint('加载历史失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// 删除会话确认
  Future<void> _confirmDelete(LocalUploadSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除沉淀记录'),
        content: Text('确定删除 ${_formatDate(session.createdAt)} 的沉淀记录吗？\n\n该次沉淀的 ${session.fileCount} 个文件将一并删除，无法恢复。'),
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
        await LocalFileStore.deleteSession(widget.tenantId, session.id);
        _loadSessions();
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
        title: const Text('上传历史'),
        centerTitle: true,
        backgroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _loadSessions,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _sessions.isEmpty
                ? _buildEmpty()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _sessions.length,
                    itemBuilder: (context, index) {
                      final session = _sessions[index];
                      return _buildSessionCard(session);
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
          Icon(Icons.inbox_outlined, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text(
            '还没有沉淀记录',
            style: TextStyle(fontSize: 15, color: Color(0xFF9CA3AF)),
          ),
          const SizedBox(height: 8),
          const Text(
            '从本设备或U盘选择文件后\n文件会沉淀到这里',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFFC0C4CC)),
          ),
        ],
      ),
    );
  }

  /// 单次沉淀会话卡片
  Widget _buildSessionCard(LocalUploadSession session) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context)
            .push(MaterialPageRoute(
              builder: (_) => LocalDataSessionDetailPage(
                tenantId: widget.tenantId,
                sessionId: session.id,
              ),
            ))
            .then((_) => _loadSessions());
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
            // 标题行：时间 + 来源
            Row(
              children: [
                Icon(
                  session.source == 'usb' ? Icons.usb : Icons.phone_android,
                  size: 16,
                  color: const Color(0xFF6B7280),
                ),
                const SizedBox(width: 6),
                Text(
                  session.sourceLabel,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
                const Spacer(),
                // 删除按钮
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFC0C4CC)),
                  onPressed: () => _confirmDelete(session),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _formatDate(session.createdAt),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1B1C),
              ),
            ),
            const SizedBox(height: 8),
            // 统计信息
            Row(
              children: [
                _buildStatItem('文件数量', '${session.fileCount} 个'),
                const SizedBox(width: 24),
                _buildStatItem('总大小', session.totalSizeFormatted),
              ],
            ),
            const SizedBox(height: 12),
            // 文件预览（前3个）
            if (session.files.isNotEmpty) ...[
              const Divider(height: 1, color: Color(0xFFF0F0F0)),
              const SizedBox(height: 10),
              ...session.files.take(3).map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(Icons.insert_drive_file, size: 14, color: Colors.grey.shade400),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                          ),
                        ),
                        Text(
                          f.sizeFormatted,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                        ),
                      ],
                    ),
                  )),
              if (session.files.length > 3)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '...还有 ${session.files.length - 3} 个文件',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1B1C),
          ),
        ),
      ],
    );
  }
}
