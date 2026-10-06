/// 年月选择器（底部弹层，全站统一）
///
/// **为什么不用 `showDatePicker`**：
/// 1. 本项目未接入 `flutter_localizations`，系统日期选择器会显示**英文**；
/// 2. 职业经历只需要精确到「年月」，「日」是多余的输入负担。
///
/// 因此这里用两个滚轮（年 / 月）+ 取消 / 确定，中文、精确到年月、无额外依赖。
/// 返回 `yyyy-MM`；用户取消返回 null。
library;

import 'package:flutter/material.dart';

/// 品牌活力橙
const Color _kBrandOrange = Color(0xFFFD5C13);

/// 可选最早年份
const int _kMinYear = 1950;

/// 未来可选的年数（如「毕业时间」可能晚于今年）
const int _kFutureYears = 10;

/// 弹出年月选择器；[initial] 为 `yyyy-MM`，为空则定位到当前年月
Future<String?> showMonthPicker(
  BuildContext context, {
  String initial = '',
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _MonthPickerSheet(initial: initial),
  );
}

class _MonthPickerSheet extends StatefulWidget {
  final String initial;

  const _MonthPickerSheet({required this.initial});

  @override
  State<_MonthPickerSheet> createState() => _MonthPickerSheetState();
}

class _MonthPickerSheetState extends State<_MonthPickerSheet> {
  /// 年份倒序（今年 + 未来 10 年 → 1950），用户先滚到近期更省力
  late final List<int> _years = [
    for (var y = DateTime.now().year + _kFutureYears; y >= _kMinYear; y--) y,
  ];

  late final FixedExtentScrollController _yearCtrl;
  late final FixedExtentScrollController _monthCtrl;

  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(widget.initial.trim());
    var y = m == null ? now.year : (int.tryParse(m.group(1)!) ?? now.year);
    var mo = m == null ? now.month : (int.tryParse(m.group(2)!) ?? now.month);
    if (y < _kMinYear) y = _kMinYear;
    if (y > _years.first) y = _years.first;
    if (mo < 1 || mo > 12) mo = 1;
    _year = y;
    _month = mo;
    _yearCtrl = FixedExtentScrollController(initialItem: _years.indexOf(y));
    _monthCtrl = FixedExtentScrollController(initialItem: mo - 1);
  }

  @override
  void dispose() {
    _yearCtrl.dispose();
    _monthCtrl.dispose();
    super.dispose();
  }

  String get _result => '$_year-${_month.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
      child: Column(
        children: [
          SizedBox(
            height: 52,
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消',
                      style: TextStyle(color: Color(0xFF9CA3AF))),
                ),
                const Expanded(
                  child: Center(
                    child: Text(
                      '选择年月',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1B1C),
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, _result),
                  child: const Text(
                    '确定',
                    style: TextStyle(
                      color: _kBrandOrange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: ListWheelScrollView.useDelegate(
                    controller: _yearCtrl,
                    itemExtent: 44,
                    physics: const FixedExtentScrollPhysics(),
                    onSelectedItemChanged: (i) => _year = _years[i],
                    childDelegate: ListWheelChildBuilderDelegate(
                      childCount: _years.length,
                      builder: (_, i) => Center(
                        child: Text(
                          '${_years[i]}年',
                          style: const TextStyle(
                              fontSize: 16, color: Color(0xFF1A1B1C)),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListWheelScrollView.useDelegate(
                    controller: _monthCtrl,
                    itemExtent: 44,
                    physics: const FixedExtentScrollPhysics(),
                    onSelectedItemChanged: (i) => _month = i + 1,
                    childDelegate: ListWheelChildBuilderDelegate(
                      childCount: 12,
                      builder: (_, i) => Center(
                        child: Text(
                          '${i + 1}月',
                          style: const TextStyle(
                              fontSize: 16, color: Color(0xFF1A1B1C)),
                        ),
                      ),
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
