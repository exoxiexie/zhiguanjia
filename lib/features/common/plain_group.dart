/// 通栏卡片（全站统一，职管家）
///
/// 微信式「发现页」形态：白底圆角卡片，每行 = 图标 + 名称 + （可选）右侧说明 + 右箭头，
/// 点整行进入对应页面。同一张卡内多行之间用细分割线分隔；**一张卡只放一组同类入口**。
///
/// **唯一事实来源**：发现页与数据页都用本组件渲染通栏入口，
/// 不允许任何页面再自写一套 —— 否则改一次样式要改多处，早晚长得不一样。
library;

import 'package:flutter/material.dart';

/// 全站卡片的左右外边距 —— **唯一事实来源**。
///
/// 约定：页面滚动容器**不自带左右内边距**，所有卡片一律带这个外边距。
/// 这样发现页 / 数据页 / 首页的卡片左右宽度天然一致，
/// 不会出现「页面加了 12、卡片又加 12，结果卡片比同页其它卡片窄一圈」。
const double kCardSideMargin = 12;

/// 卡片统一外边距（左右各 [kCardSideMargin]，上下由页面自行控制）
const EdgeInsets kCardMargin =
    EdgeInsets.symmetric(horizontal: kCardSideMargin);

/// 行间分割线
const Color kPlainGroupDivider = Color(0xFFEDEEF0);

/// 右箭头颜色
const Color kPlainGroupChevron = Color(0xFFC4C8CE);

/// 一条通栏入口的配置
class PlainGroupEntry {
  /// 左侧图标
  final IconData icon;

  /// 图标颜色（建议用各模块的语义色）
  final Color color;

  /// 主标题
  final String label;

  /// 右侧补充说明（如「3 条」），为空则不显示
  final String trailingText;

  /// 点击整行的动作
  final VoidCallback onTap;

  const PlainGroupEntry({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.trailingText = '',
  });
}

/// 一张通栏卡片（一组入口）
class PlainGroup extends StatelessWidget {
  final List<PlainGroupEntry> entries;

  /// 卡片外边距（默认取全站统一的 [kCardMargin]）
  final EdgeInsetsGeometry margin;

  const PlainGroup({
    super.key,
    required this.entries,
    this.margin = kCardMargin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 56,
                color: kPlainGroupDivider,
              ),
            _PlainGroupRow(entry: entries[i]),
          ],
        ],
      ),
    );
  }
}

/// 单行：图标 + 名称 + （可选）右侧说明 + 右箭头
class _PlainGroupRow extends StatelessWidget {
  final PlainGroupEntry entry;

  const _PlainGroupRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: entry.onTap,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(entry.icon, size: 24, color: entry.color),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    entry.label,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF1A1B1C),
                    ),
                  ),
                ),
                if (entry.trailingText.isNotEmpty) ...[
                  Text(
                    entry.trailingText,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                const Icon(Icons.chevron_right,
                    size: 22, color: kPlainGroupChevron),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
