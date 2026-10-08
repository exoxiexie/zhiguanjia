/// 底栏项 · 自绘（职管家 · 个人职业版）
///
/// **为什么不用官方 `NavigationDestination`**（v1.0.32）：
/// 官方把三件事写死在私有代码里，无法从外部调整 ——
/// 1. 选中态那个「药丸」底：尺寸 `64×32` 是源码常量，主题改不了；
/// 2. 图标与文字之间的 8dp 间隙：由「图标盒内空隙 4 + 文字写死的上边距 4」拼成；
/// 3. 图标与文字的相对位置由私有 `MultiChildLayoutDelegate` 计算，插不进手。
///
/// 因此这里改为**自绘格子内容**：仍由官方 [NavigationBar] 提供外壳
/// （高度、背景、底部安全区、横向均分），只是每格换成下面的 [AppNavDestination]，
/// 从而做到：**无药丸**、**图标与文字间距可控**、**选中态图标用实心深色**。
library;

import 'package:flutter/material.dart';

/// 图标与文字之间的间距（v1.0.32：由官方的 8dp 收到 4dp）
///
/// 官方 8dp = 图标盒内下方空隙 4 + 文字上边距 4；自绘后由本常量直接控制。
const double kNavIconLabelGap = 4;

/// 底栏图标尺寸（与官方 M3 默认一致）
const double kNavIconSize = 24;

/// 选中态图标颜色：项目统一的近黑
const Color kNavSelectedIconColor = Color(0xFF1A1B1C);

/// 一个底栏项的静态定义（图标 / 选中图标 / 文字）
class AppNavItem {
  /// 未选中图标（通常为线性 outline 版本）
  final IconData icon;

  /// 选中图标（实心版本，与 [icon] 同族）
  final IconData selectedIcon;

  /// 文字
  final String label;

  const AppNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// 底栏单项：图标 + 文字，**不画药丸**，选中靠图标变实心深色 + 文字变色体现。
///
/// 用法：作为 `NavigationBar.destinations` 的元素传入即可
/// （已实测官方只断言 `destinations.length >= 2`，不限制元素类型）。
class AppNavDestination extends StatelessWidget {
  /// 该项定义
  final AppNavItem item;

  /// 是否选中
  final bool selected;

  /// 点击回调
  final VoidCallback onTap;

  const AppNavDestination({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    // 未选中色与官方 M3 默认一致（onSurfaceVariant），保证不改变既有观感；
    // 选中时图标用近黑实心，文字用 onSurface（同官方）。
    final Color unselectedColor = cs.onSurfaceVariant;
    final Color iconColor =
        selected ? kNavSelectedIconColor : unselectedColor;
    final Color labelColor = selected ? cs.onSurface : unselectedColor;

    final TextStyle labelStyle =
        (Theme.of(context).textTheme.labelMedium ?? const TextStyle()).copyWith(
      color: labelColor,
    );

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        // 撑满整格高度，保证点击热区覆盖整条格子
        height: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              selected ? item.selectedIcon : item.icon,
              size: kNavIconSize,
              color: iconColor,
            ),
            const SizedBox(height: kNavIconLabelGap),
            MediaQuery.withClampedTextScaling(
              // 与官方一致：底栏文字不跟随系统字号放大，避免撑破底栏
              maxScaleFactor: 1.0,
              child: Text(item.label, style: labelStyle),
            ),
          ],
        ),
      ),
    );
  }
}

/// 由 [AppNavItem] 列表构造一整排底栏项（配合 `NavigationBar.destinations` 使用）
List<Widget> buildAppNavDestinations({
  required List<AppNavItem> items,
  required int selectedIndex,
  required ValueChanged<int> onSelected,
}) {
  return <Widget>[
    for (int i = 0; i < items.length; i++)
      AppNavDestination(
        item: items[i],
        selected: i == selectedIndex,
        onTap: () => onSelected(i),
      ),
  ];
}
