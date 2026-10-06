/// 自我评价页（职管家 · 个人职业版）
///
/// **入口**：数据页「自我评价」通栏卡片（实名卡下方）。
///
/// 与三类经历不同，这里只有**一段自由文本**，所以不需要列表页 ——
/// 进来就是编辑态，写完点右上角「保存」返回，数据页据此刷新卡片状态。
library;

import 'package:flutter/material.dart';

import 'self_evaluation_store.dart';

/// 品牌活力橙
const Color _kBrandOrange = Color(0xFFFD5C13);

const Color _kPageBg = Color(0xFFF5F5F5);
const Color _kTitleColor = Color(0xFF1A1B1C);
const Color _kLabelColor = Color(0xFF6B7280);
const Color _kHintColor = Color(0xFFB5B9C0);
const Color _kInputBg = Color(0xFFF7F8FA);

/// 字数上限（与主流招聘平台的「自我评价」字段量级一致）
const int _kMaxLength = 500;

class SelfEvaluationPage extends StatefulWidget {
  const SelfEvaluationPage({super.key});

  @override
  State<SelfEvaluationPage> createState() => _SelfEvaluationPageState();
}

class _SelfEvaluationPageState extends State<SelfEvaluationPage> {
  final TextEditingController _ctrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final text = await SelfEvaluationStore.load();
    if (!mounted) return;
    setState(() {
      _ctrl.text = text;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await SelfEvaluationStore.save(_ctrl.text);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _saving || _loading;
    return Scaffold(
      backgroundColor: _kPageBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: _kTitleColor),
        title: const Text(
          '自我评价',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: _kTitleColor,
          ),
        ),
        actions: [
          TextButton(
            onPressed: disabled ? null : _save,
            child: Text(
              '保存',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: disabled ? _kHintColor : _kBrandOrange,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '用几句话概括你的职业优势、专业特长与发展方向',
                        style: TextStyle(fontSize: 13, color: _kLabelColor),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _ctrl,
                        maxLines: 10,
                        maxLength: _kMaxLength,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.6,
                          color: _kTitleColor,
                        ),
                        decoration: const InputDecoration(
                          hintText: '例如：8 年 ToB 产品经验，擅长从 0 到 1 搭建业务中台……',
                          hintStyle:
                              TextStyle(fontSize: 15, color: _kHintColor),
                          filled: true,
                          fillColor: _kInputBg,
                          contentPadding: EdgeInsets.all(12),
                          border: OutlineInputBorder(
                            borderSide: BorderSide.none,
                            borderRadius:
                                BorderRadius.all(Radius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
