/// 基础信息页（职管家 · 个人职业版）
///
/// **入口**：数据页「基础信息」通栏卡片（实名卡下方、自我评价上方）。
///
/// **内容**：现在住址（省 / 市 / 区三级选择器 + 详细地址）、工作状态、婚姻状况。
/// 进来即编辑态，改完点右上角「保存」返回，数据页据此刷新卡片状态。
library;

import 'package:flutter/material.dart';

import 'basic_info_store.dart';
import 'region_picker.dart';

/// 品牌活力橙
const Color _kBrandOrange = Color(0xFFFD5C13);

const Color _kPageBg = Color(0xFFF5F5F5);
const Color _kTitleColor = Color(0xFF1A1B1C);
const Color _kLabelColor = Color(0xFF6B7280);
const Color _kHintColor = Color(0xFFB5B9C0);
const Color _kInputBg = Color(0xFFF7F8FA);
const Color _kBorder = Color(0xFFECEEF1);

class BasicInfoPage extends StatefulWidget {
  const BasicInfoPage({super.key});

  @override
  State<BasicInfoPage> createState() => _BasicInfoPageState();
}

class _BasicInfoPageState extends State<BasicInfoPage> {
  final TextEditingController _addrCtrl = TextEditingController();

  String _province = '';
  String _city = '';
  String _district = '';

  WorkStatus? _work;
  MaritalStatus? _marital;

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _addrCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final info = await BasicInfoStore.load();
    if (!mounted) return;
    setState(() {
      _province = info.province;
      _city = info.city;
      _district = info.district;
      _addrCtrl.text = info.address;
      _work = info.workStatus;
      _marital = info.maritalStatus;
      _loading = false;
    });
  }

  /// 已选中的省市区（未选返回 null）
  RegionSelection? get _region => _province.isEmpty
      ? null
      : RegionSelection(
          province: _province, city: _city, district: _district);

  Future<void> _pickRegion() async {
    final r = await showRegionPicker(context, initial: _region);
    if (r == null || !mounted) return;
    setState(() {
      _province = r.province;
      _city = r.city;
      _district = r.district;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await BasicInfoStore.save(BasicInfo(
      province: _province,
      city: _city,
      district: _district,
      address: _addrCtrl.text.trim(),
      workStatus: _work,
      maritalStatus: _marital,
    ));
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
          '基础信息',
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
                _card(
                  children: [
                    _sectionTitle('现在住址'),
                    const SizedBox(height: 12),
                    _regionRow(),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _addrCtrl,
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: _kTitleColor,
                      ),
                      decoration: const InputDecoration(
                        hintText: '街道、门牌号等详细地址',
                        hintStyle: TextStyle(fontSize: 15, color: _kHintColor),
                        filled: true,
                        fillColor: _kInputBg,
                        contentPadding: EdgeInsets.all(12),
                        border: OutlineInputBorder(
                          borderSide: BorderSide.none,
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _card(
                  children: [
                    _sectionTitle('工作状态'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final s in WorkStatus.values)
                          _option(
                            label: s.label,
                            selected: _work == s,
                            onTap: () => setState(
                                () => _work = _work == s ? null : s),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _sectionTitle('婚姻状况'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final s in MaritalStatus.values)
                          _option(
                            label: s.label,
                            selected: _marital == s,
                            onTap: () => setState(
                                () => _marital = _marital == s ? null : s),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  /// 白底圆角卡片（与全站卡片同一形态）
  Widget _card({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: _kTitleColor,
      ),
    );
  }

  /// 省市区选择入口（点击弹出三级联动滚轮）
  Widget _regionRow() {
    final r = _region;
    return GestureDetector(
      onTap: _pickRegion,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: _kInputBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                r == null ? '请选择省 / 市 / 区' : r.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  color: r == null ? _kHintColor : _kTitleColor,
                ),
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 20, color: Color(0xFFC0C4CC)),
          ],
        ),
      ),
    );
  }

  /// 可选标签（再点一次取消选择）
  Widget _option({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF1EA) : _kInputBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? _kBrandOrange : _kBorder,
            width: selected ? 1.2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? _kBrandOrange : _kLabelColor,
          ),
        ),
      ),
    );
  }
}
