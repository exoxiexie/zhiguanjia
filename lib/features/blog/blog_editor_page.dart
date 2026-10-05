/// 写博客页（职管家 · 个人职业版）
///
/// 极简编辑器：标题 + 正文，点「发布」存入本地（[BlogStore]），
/// 发布成功后 pop 并返回 true，由博客页刷新「我的」列表。
library;

import 'package:flutter/material.dart';

import 'blog_store.dart';

/// 品牌活力橙
const Color _kBrandOrange = Color(0xFFFD5C13);

class BlogEditorPage extends StatefulWidget {
  const BlogEditorPage({super.key});

  @override
  State<BlogEditorPage> createState() => _BlogEditorPageState();
}

class _BlogEditorPageState extends State<BlogEditorPage> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _contentCtrl = TextEditingController();
  bool _publishing = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (title.isEmpty && content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入博客内容')),
      );
      return;
    }

    setState(() => _publishing = true);
    final now = DateTime.now().millisecondsSinceEpoch;
    await BlogStore.addPost(BlogPost(
      id: '$now',
      title: title.isEmpty ? '无标题' : title,
      content: content,
      createdAt: now,
    ));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('写博客'),
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
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleCtrl,
              maxLines: 1,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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
            Expanded(
              child: TextField(
                controller: _contentCtrl,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontSize: 15, height: 1.6),
                decoration: const InputDecoration(
                  hintText: '分享你的职业见解、经验或思考…',
                  hintStyle: TextStyle(fontSize: 15, color: Color(0xFFB5B9C0)),
                  border: InputBorder.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
