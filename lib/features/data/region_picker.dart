/// 省 / 市 / 区三级联动选择器（底部弹层，全站统一）
///
/// **为什么自己写**：本项目未接入 `flutter_localizations`，也没引第三方城市选择器；
/// 这里用三列滚轮 + 取消 / 确定，中文、离线、零新增依赖，
/// 交互与 [showMonthPicker] 完全同一套。
///
/// **数据**：[kChinaRegions]（省级 → 地级 → 区县，34 / 352 / 3026 项），整份编进包内。
/// 选省后市级自动回到第一项、区级跟随刷新，三级始终联动。
library;

import 'package:flutter/material.dart';

import 'region_data.dart';

/// 品牌活力橙
const Color _kBrandOrange = Color(0xFFFD5C13);

const Color _kTitleColor = Color(0xFF1A1B1C);

/// 一次住址选择的结果（省 / 市 / 区全称，如「广东省 深圳市 南山区」）
class RegionSelection {
  final String province;
  final String city;
  final String district;

  const RegionSelection({
    required this.province,
    required this.city,
    required this.district,
  });

  /// 一行展示（`广东省 深圳市 南山区`）
  String get text =>
      [province, city, district].where((e) => e.isNotEmpty).join(' ');

  /// 从存储字符串还原；层级不足返回 null
  static RegionSelection? parse(String raw) {
    final parts =
        raw.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.length < 3) return null;
    return RegionSelection(
      province: parts[0],
      city: parts[1],
      district: parts[2],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RegionSelection &&
      other.province == province &&
      other.city == city &&
      other.district == district;

  @override
  int get hashCode => Object.hash(province, city, district);

  @override
  String toString() => text;
}

/// 弹出省市区选择器；[initial] 用于回显定位，用户取消返回 null
Future<RegionSelection?> showRegionPicker(
  BuildContext context, {
  RegionSelection? initial,
}) {
  return showModalBottomSheet<RegionSelection>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _RegionPickerSheet(initial: initial),
  );
}

class _RegionPickerSheet extends StatefulWidget {
  final RegionSelection? initial;

  const _RegionPickerSheet({required this.initial});

  @override
  State<_RegionPickerSheet> createState() => _RegionPickerSheetState();
}

class _RegionPickerSheetState extends State<_RegionPickerSheet> {
  late final List<String> _provinces = kChinaRegions.keys.toList();

  late int _provIndex;
  late int _cityIndex;
  late int _distIndex;

  late final FixedExtentScrollController _provCtrl;
  late final FixedExtentScrollController _cityCtrl;
  late final FixedExtentScrollController _distCtrl;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;

    var pi = init == null ? 0 : _provinces.indexOf(init.province);
    if (pi < 0) pi = 0;

    final cities = _citiesOf(pi);
    var ci = init == null ? 0 : cities.indexOf(init.city);
    if (ci < 0) ci = 0;

    final districts = _districtsOf(pi, ci);
    var di = init == null ? 0 : districts.indexOf(init.district);
    if (di < 0) di = 0;

    _provIndex = pi;
    _cityIndex = ci;
    _distIndex = di;

    _provCtrl = FixedExtentScrollController(initialItem: pi);
    _cityCtrl = FixedExtentScrollController(initialItem: ci);
    _distCtrl = FixedExtentScrollController(initialItem: di);
  }

  @override
  void dispose() {
    _provCtrl.dispose();
    _cityCtrl.dispose();
    _distCtrl.dispose();
    super.dispose();
  }

  List<String> _citiesOf(int provIndex) =>
      kChinaRegions[_provinces[provIndex]]?.keys.toList() ?? const [];

  List<String> _districtsOf(int provIndex, int cityIndex) {
    final cities = kChinaRegions[_provinces[provIndex]];
    if (cities == null) return const [];
    final names = cities.keys.toList();
    if (cityIndex < 0 || cityIndex >= names.length) return const [];
    return cities[names[cityIndex]] ?? const [];
  }

  /// 当前滚轮位置对应的结果；市为空（数据异常）返回 null
  RegionSelection? get _result {
    final cities = _citiesOf(_provIndex);
    if (cities.isEmpty) return null;
    final districts = _districtsOf(_provIndex, _cityIndex);
    return RegionSelection(
      province: _provinces[_provIndex],
      city: cities[_cityIndex],
      district: districts.isEmpty ? '' : districts[_distIndex],
    );
  }

  /// 换省：市 / 区都回到第一项
  void _onProvinceChanged(int i) {
    setState(() {
      _provIndex = i;
      _cityIndex = 0;
      _distIndex = 0;
    });
    _resetWheel(_cityCtrl);
    _resetWheel(_distCtrl);
  }

  /// 换市：区回到第一项
  void _onCityChanged(int i) {
    setState(() {
      _cityIndex = i;
      _distIndex = 0;
    });
    _resetWheel(_distCtrl);
  }

  /// 列表内容变了，把滚轮拨回第一项。
  /// 必须等本帧渲染完（此时新列表已挂上）再动，否则会越界。
  void _resetWheel(FixedExtentScrollController c) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (c.hasClients) c.jumpToItem(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cities = _citiesOf(_provIndex);
    final districts = _districtsOf(_provIndex, _cityIndex);

    return SizedBox(
      height: 320,
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
                      '选择所在地区',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _kTitleColor,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final r = _result;
                    if (r != null) Navigator.pop(context, r);
                  },
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
            child: Stack(
              children: [
                Row(
                  children: [
                    _wheel(_provinces, _provCtrl, _onProvinceChanged),
                    _wheel(cities, _cityCtrl, _onCityChanged),
                    _wheel(districts, _distCtrl,
                        (i) => setState(() => _distIndex = i)),
                  ],
                ),
                // 中间「选中行」高亮带（IgnorePointer 保证不挡滚轮手势）
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        height: 44,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0x0A000000),
                          borderRadius: BorderRadius.circular(8),
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

  Widget _wheel(
    List<String> items,
    FixedExtentScrollController controller,
    ValueChanged<int> onChanged,
  ) {
    return Expanded(
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: 44,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: onChanged,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: items.length,
          builder: (_, i) => Center(
            child: Text(
              items[i],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, color: _kTitleColor),
            ),
          ),
        ),
      ),
    );
  }
}
