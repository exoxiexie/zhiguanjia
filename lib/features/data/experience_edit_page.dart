/// 经历编辑页（新增 / 修改，教育 · 工作 · 培训共用）
///
/// **表单不写死字段**：整页由 [ExperienceKind.fields] 描述表生成 ——
/// 字段类型决定控件（单行文本 / 多行文本 / 选项芯片 / 年月选择），
/// 必填校验也来自描述表。因此新增一类经历不需要再写一套表单。
///
/// 保存后 pop(true)，由列表页重新拉取；删除需二次确认。
library;

import 'package:flutter/material.dart';

import '../common/month_picker.dart';
import 'experience_models.dart';
import 'experience_store.dart';

/// 品牌活力橙
const Color _kBrandOrange = Color(0xFFFD5C13);

const Color _kPageBg = Color(0xFFF5F5F5);
const Color _kTitleColor = Color(0xFF1A1B1C);
const Color _kLabelColor = Color(0xFF6B7280);
const Color _kHintColor = Color(0xFFB5B9C0);
const Color _kInputBg = Color(0xFFF7F8FA);
const Color _kDanger = Color(0xFFEF4444);

class ExperienceEditPage extends StatefulWidget {
  /// 经历类型（决定字段清单）
  final ExperienceKind kind;

  /// 被编辑的经历；为 null 表示新增
  final ExperienceEntry? entry;

  const ExperienceEditPage({super.key, required this.kind, this.entry});

  @override
  State<ExperienceEditPage> createState() => _ExperienceEditPageState();
}

class _ExperienceEditPageState extends State<ExperienceEditPage> {
  /// 当前值（文本类字段会随输入实时同步进来）
  final Map<String, String> _values = {};

  /// 文本类字段的输入控制器
  final Map<String, TextEditingController> _ctrls = {};

  bool _saving = false;

  bool get _isNew => widget.entry == null;

  @override
  void initState() {
    super.initState();
    for (final f in widget.kind.fields) {
      final v = widget.entry?.values[f.key] ?? '';
      _values[f.key] = v;
      if (f.type == ExperienceFieldType.text ||
          f.type == ExperienceFieldType.multiline) {
        _ctrls[f.key] = TextEditingController(text: v);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// 把文本控件的当前输入同步进 [_values]
  void _syncTextFields() {
    for (final e in _ctrls.entries) {
      _values[e.key] = e.value.text.trim();
    }
  }

  Future<void> _save() async {
    _syncTextFields();

    // 必填校验（来自描述表，不写死在页面里）
    for (final f in widget.kind.fields) {
      if (f.required && (_values[f.key] ?? '').isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('请填写「${f.label}」')),
        );
        return;
      }
    }

    setState(() => _saving = true);
    final now = DateTime.now().millisecondsSinceEpoch;
    final entry = ExperienceEntry(
      id: widget.entry?.id ?? '${now}_${widget.kind.id}',
      kindId: widget.kind.id,
      values: Map.of(_values),
      createdAt: widget.entry?.createdAt ?? now,
      updatedAt: now,
    );
    await ExperienceStore.save(entry);
    if (mounted) Navigator.pop(context, true);
  }

  /// 删除（二次确认）
  Future<void> _delete() async {
    final id = widget.entry?.id;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条经历？'),
        content: const Text('删除后不可恢复。'),
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
    await ExperienceStore.delete(id);
    if (mounted) Navigator.pop(context, true);
  }

  /// 选年月
  Future<void> _pickMonth(ExperienceField field) async {
    final picked = await showMonthPicker(
      context,
      initial: _values[field.key] ?? '',
    );
    if (picked == null) return;
    setState(() => _values[field.key] = picked);
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
          '${_isNew ? '新增' : '编辑'}${widget.kind.label}',
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
                for (var i = 0; i < widget.kind.fields.length; i++) ...[
                  if (i > 0) const SizedBox(height: 18),
                  _buildField(widget.kind.fields[i]),
                ],
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
                        '删除这条经历',
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

  /// 按字段类型渲染控件
  Widget _buildField(ExperienceField field) {
    switch (field.type) {
      case ExperienceFieldType.text:
        return _buildText(field, maxLines: 1);
      case ExperienceFieldType.multiline:
        return _buildText(field, maxLines: 4);
      case ExperienceFieldType.select:
        return _buildSelect(field);
      case ExperienceFieldType.month:
        return _buildMonth(field);
    }
  }

  /// 字段标签（必填带 *）
  Widget _buildLabel(ExperienceField field) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          text: field.label,
          style: const TextStyle(fontSize: 13, color: _kLabelColor),
          children: [
            if (field.required)
              const TextSpan(
                text: ' *',
                style: TextStyle(color: _kDanger, fontSize: 13),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildText(ExperienceField field, {required int maxLines}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(field),
        TextField(
          controller: _ctrls[field.key],
          maxLines: maxLines,
          style: const TextStyle(fontSize: 15, color: _kTitleColor),
          decoration: InputDecoration(
            hintText: field.hint,
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
        ),
      ],
    );
  }

  Widget _buildSelect(ExperienceField field) {
    final current = _values[field.key] ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(field),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final opt in field.options)
              GestureDetector(
                onTap: () => setState(() {
                  // 再点一次取消选择（学历允许留空）
                  _values[field.key] = current == opt ? '' : opt;
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: current == opt
                        ? _kBrandOrange.withOpacity(0.10)
                        : _kInputBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: current == opt ? _kBrandOrange : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    opt,
                    style: TextStyle(
                      fontSize: 14,
                      color: current == opt ? _kBrandOrange : _kLabelColor,
                      fontWeight:
                          current == opt ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildMonth(ExperienceField field) {
    final value = _values[field.key] ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(field),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _pickMonth(field),
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: _kInputBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value.isEmpty ? (field.hint.isEmpty ? '请选择' : field.hint) : formatMonth(value),
                      style: TextStyle(
                        fontSize: 15,
                        color: value.isEmpty ? _kHintColor : _kTitleColor,
                      ),
                    ),
                  ),
                  if (value.isNotEmpty)
                    GestureDetector(
                      onTap: () => setState(() => _values[field.key] = ''),
                      child: const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child:
                            Icon(Icons.close, size: 16, color: _kHintColor),
                      ),
                    ),
                  const Icon(Icons.calendar_today_outlined,
                      size: 16, color: _kHintColor),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
