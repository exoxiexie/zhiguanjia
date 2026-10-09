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
///
/// [replace] 为 true 时先**收掉当前提示**再显示 —— 用于"正在处理…"→结果 的替换。
/// 否则 Flutter 会把新提示**排队**，结果要等前一条 4 秒结束才出现。
void showAppSnackBar(BuildContext context, String message,
    {bool replace = false}) {
  final messenger = ScaffoldMessenger.of(context);
  if (replace) messenger.removeCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message, textAlign: TextAlign.center),
    ),
  );
}
