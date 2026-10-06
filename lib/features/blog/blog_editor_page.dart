/// 写说说页（职管家 · 个人职业版）
///
/// 极简编辑器：标题 + 正文 + 配图，点「发布」存入本地（[BlogStore]），
/// 发布成功后 pop 并返回 true，由说说页刷新「我的」列表。
///
/// **内容形态**：一条说说可以是「纯文字」「纯图片」或「文字 + 图片」，
/// 因此校验条件是三者不能同时为空；标题始终可选。
///
/// **版面**（自上而下）：标题 → 分隔线 → 正文（固定 5 行高）→ 配图区。
/// 配图区紧跟正文下方，由「已选图片方块 + 一个等大的＋方块」组成，
/// 点「＋」进入选图；图片多了由 [Wrap] 自动换行向下铺开，整页可滚动。
///
/// **配图落盘**：选中的图片由 [PostImageStore] 复制进应用私有目录后，
/// 再以绝对路径写入说说数据（不能直接存系统临时路径，会被清理成裂图）。
/// 若用户中途放弃（未点发布就退出），dispose 时清理本次已落盘的文件，不留孤儿图片。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../personal/personal_auth_service.dart';
import 'blog_store.dart';
import 'post_image_store.dart';

/// 品牌活力橙
const Color _kBrandOrange = Color(0xFFFD5C13);

/// 配图数量上限（与主流信息流一致：最多 9 张）
const int _kMaxImages = 9;

/// 配图方块边长：图片方块与「＋」方块**等大**，视觉上成一组
const double _kTileSize = 88;

/// 正文输入区行数：固定 5 行高，不撑满整屏，把下半屏留给配图
const int _kContentLines = 5;

class BlogEditorPage extends StatefulWidget {
  const BlogEditorPage({super.key});

  @override
  State<BlogEditorPage> createState() => _BlogEditorPageState();
}

class _BlogEditorPageState extends State<BlogEditorPage> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _contentCtrl = TextEditingController();

  /// 已选配图的**私有目录绝对路径**（选一张即落盘一张）
  final List<String> _images = [];

  bool _publishing = false;

  /// 是否已成功发布：为 true 时退出不清理图片（图片已归说说所有）
  bool _published = false;

  /// 选图期间忽略重复点击
  bool _picking = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    // 未发布就退出 → 回收本次选中的图片文件，避免私有目录堆积孤儿图
    if (!_published && _images.isNotEmpty) {
      PostImageStore.removeAll(List.of(_images));
    }
    super.dispose();
  }

  /// 弹出图片来源选择（拍照 / 从相册选择），与「更换头像」保持同一交互
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
                  color: Color(0xFF1A1B1C),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: Color(0xFF5B7FD4)),
              title: const Text('拍照'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSave(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: Color(0xFF5B7FD4)),
              title: const Text('从相册选择'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSave(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  /// 选图 → 复制进私有目录 → 追加到预览列表
  Future<void> _pickAndSave(ImageSource source) async {
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
        picked = one == null ? const [] : [one];
      }
      if (picked.isEmpty) return; // 用户取消

      final remain = _kMaxImages - _images.length;
      final take = picked.take(remain).toList();
      final saved = await PostImageStore.saveAll(take.map((e) => e.path));
      if (!mounted) return;
      setState(() => _images.addAll(saved));
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

  /// 移除一张已选图片：同时删除已落盘的文件
  void _removeImage(int index) {
    final path = _images.removeAt(index);
    setState(() {});
    PostImageStore.removeAll([path]);
  }

  Future<void> _publish() async {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (title.isEmpty && content.isEmpty && _images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入说说内容或添加图片')),
      );
      return;
    }

    setState(() => _publishing = true);
    final auth = await PersonalAuthService.getAuth();
    final now = DateTime.now().millisecondsSinceEpoch;
    // 标题允许为空：展示层按「无标题」规则直接显示正文，
    // 不再填充「无标题」占位文字（避免污染数据与列表展示）。
    // id 拼接作者手机号，保证全站时间线里不同作者同一毫秒发布不会撞号；
    // 作者信息随文章快照存储，时间线展示头像/昵称时无需回查用户表。
    await BlogStore.addPost(BlogPost(
      id: '${now}_${auth?.phone ?? ''}',
      title: title,
      content: content,
      images: List.of(_images),
      createdAt: now,
      authorPhone: auth?.phone ?? '',
      authorName: auth?.name ?? '',
    ));
    _published = true; // 图片已归属这条说说，退出时不再清理
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('写说说'),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          TextButton(
            onPressed: _publishing ? null : _publish,
            child: Text(
              '发布',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _publishing ? Colors.grey : _kBrandOrange,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      // 正文固定约 5 行高，配图区紧随正文之后；配图较多时整页可滚动
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleCtrl,
              maxLines: 1,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                hintText: '请输入标题',
                hintStyle: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFB5B9C0)),
                border: InputBorder.none,
              ),
            ),
            const Divider(height: 1, color: Color(0xFFEEEEEE)),
            const SizedBox(height: 8),

            // ── 正文：固定 5 行高（不撑满整屏，把下半屏留给配图）──
            TextField(
              controller: _contentCtrl,
              minLines: _kContentLines,
              maxLines: _kContentLines,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontSize: 15, height: 1.6),
              decoration: const InputDecoration(
                hintText: '分享你的职业见解、经验或思考…',
                hintStyle: TextStyle(fontSize: 15, color: Color(0xFFB5B9C0)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 6),

            // ── 配图：紧跟正文下方，图片方块 + 「＋」方块 ──
            _buildImageGrid(),
          ],
        ),
      ),
    );
  }

  /// 配图区：已选图片方块 + 「＋」方块（参考主流信息流的发布器形态）
  ///
  /// 用 [Wrap] 而不是横向滚动条：图片多了自动换行向下铺开，
  /// 与正文连成一片，而不是被压在页面底部的一条横向带里。
  Widget _buildImageGrid() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int i = 0; i < _images.length; i++) _buildImageTile(i),
        // 达上限后隐藏「＋」，避免误以为还能继续加
        if (_images.length < _kMaxImages) _buildAddTile(),
      ],
    );
  }

  /// 已选图片方块（右上角可移除）
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
  Widget _buildAddTile() {
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
}
