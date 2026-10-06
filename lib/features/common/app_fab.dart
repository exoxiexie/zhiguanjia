/// 全站「新增」浮动按钮（右下角 ＋）
///
/// **为什么单独抽**：本 App 启用了 Material 3（`main.dart` 的 `useMaterial3: true`），
/// M3 的 `FloatingActionButton` 默认是**16dp 圆角方形**；本 App 统一用**正圆**。
/// 把 shape 收敛到这一处，否则每个页面各写一遍 `CircleBorder()`，
/// 早晚漏掉一处，又变成两种形状（本项目「避免第二套实现」的既有约定）。
///
/// 用法：`floatingActionButton: AppFab(tooltip: '添加学历教育', onPressed: ...)`
library;

import 'package:flutter/material.dart';

/// 品牌活力橙（与 App 图标主色一致）
const Color kBrandOrange = Color(0xFFFD5C13);

class AppFab extends StatelessWidget {
  final VoidCallback onPressed;

  /// 无障碍 / 长按提示文案（如「添加学历教育」）
  final String tooltip;

  const AppFab({
    super.key,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: onPressed,
      backgroundColor: kBrandOrange,
      foregroundColor: Colors.white,
      elevation: 4,
      tooltip: tooltip,
      // 关键：M3 默认圆角方形，这里统一改成正圆
      shape: const CircleBorder(),
      child: const Icon(Icons.add, size: 30),
    );
  }
}
