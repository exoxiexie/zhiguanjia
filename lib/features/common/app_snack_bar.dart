/// 统一的底部提示（SnackBar）
///
/// **视觉约定：文案一律居中显示。**
/// 历史上提示是各处手写的，容易漏掉 `textAlign`（v1.0.45 的「检查更新」就是这样
/// 从居中退化成了左对齐），因此收敛到这个入口。
///
/// 新增提示请用 [showAppSnackBar]；散落的旧调用点可逐步迁移，不必一次性改完。
library;

import 'package:flutter/material.dart';

/// 显示一条居中的底部提示
void showAppSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, textAlign: TextAlign.center),
    ),
  );
}
