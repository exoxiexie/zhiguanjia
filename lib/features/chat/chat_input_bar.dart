/// 公共对话输入栏 · 对话首页（懂你）使用
///
/// 样式：
/// - 顶部工具行：模型选择 + 连接电脑 + 技能选择（可用 [showTopBar] 关闭）
/// - 输入框（1~5 行自适应）+ 附件按钮 + 发送按钮
///
/// **输入框高度规则（v1.0.30 起）**：
/// 未聚焦时只占 **1 行**（平时不占地方、输入栏整体更矮）；
/// 一旦聚焦就撑到 **2 行**（给正在输入的内容留出余地）；
/// 继续写则逐行长高，**最多 5 行**，再多就在框内滚动。
/// 发送后失焦 → 自动收回 1 行。
///
/// **发送即收键盘**：点发送按钮或按键盘「发送」键，统一走内部 [_handleSend] ——
/// 先收起键盘（输入栏落回屏幕底部），再回调 [onSend] 交给宿主发送。
/// 以前不收键盘，键盘 + 输入栏会长占约 2/3 屏，用户得手动收键盘才能看到回复。
library;

import 'package:flutter/material.dart';

import '../../contracts/chat_service.dart';

/// 输入框行数边界（未聚焦 / 聚焦 / 最大）
const int _kMinLinesIdle = 1;
const int _kMinLinesFocused = 2;
const int _kMaxLines = 5;

/// 对话输入栏
class ChatInputBar extends StatefulWidget {
  final TextEditingController controller;
  final bool isLoading;

  /// 待发送附件（由外部构造好传入，null 则不显示）
  final Widget? pendingAttachment;

  final ChatModel selectedModel;
  final ValueChanged<ChatModel>? onModelChanged;
  final VoidCallback? onAddAttachment;
  final VoidCallback? onSend;
  /// 「快捷指令」：打开预设指令列表，选中后填入输入框
  final VoidCallback? onQuickCommand;

  /// 「提炼记忆」：把当前对话提炼为记忆（原顶栏魔法星星的能力）
  final VoidCallback? onExtractMemory;

  /// 是否显示顶部工具行（模型选择+连接电脑+技能选择），默认 true
  final bool showTopBar;

  /// 输入框提示文字，默认"输入你的问题…"
  final String hintText;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.isLoading,
    required this.selectedModel,
    this.pendingAttachment,
    this.onModelChanged,
    this.onAddAttachment,
    this.onSend,
    this.onQuickCommand,
    this.onExtractMemory,
    this.showTopBar = true,
    this.hintText = '输入你的问题…',
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  /// 输入框焦点（决定最小行数：未聚焦 1 行 / 聚焦 2 行）
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  /// 焦点变化即重绘，让输入框在 1 行 / 2 行之间切换
  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  /// 统一的发送入口：先收起键盘（输入栏落回底部），再交给宿主发送。
  ///
  /// 键盘收起放在这里而不是各宿主页，是为了让调用方行为天然一致，
  /// 且今后新增对话页无需再各自实现一遍。
  void _handleSend() {
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onSend?.call();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.pendingAttachment != null) widget.pendingAttachment!,
            if (widget.showTopBar) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0x0F000000),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 2),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<ChatModel>(
                          value: widget.selectedModel,
                          isDense: true,
                          padding: EdgeInsets.zero,
                          dropdownColor: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          icon: const Icon(Icons.arrow_drop_down,
                              size: 18, color: Color(0x881A1B1C)),
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xCC1A1B1C)),
                          items: kChatModels.map((m) {
                            return DropdownMenuItem<ChatModel>(
                              value: m,
                              child: Text(m.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12)),
                            );
                          }).toList(),
                          onChanged: widget.isLoading
                              ? null
                              : (m) {
                                  if (m != null) widget.onModelChanged?.call(m);
                                },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildFeatureButton(
                      icon: Icons.tips_and_updates_outlined,
                      label: '快捷指令',
                      onTap: widget.onQuickCommand,
                    ),
                    const SizedBox(width: 8),
                    _buildFeatureButton(
                      icon: Icons.auto_awesome,
                      label: '提炼记忆',
                      onTap: widget.onExtractMemory,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],
            Container(
              decoration: BoxDecoration(
                color: const Color(0x0F000000),
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.fromLTRB(9, 8, 8, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    minLines:
                        _focusNode.hasFocus ? _kMinLinesFocused : _kMinLinesIdle,
                    maxLines: _kMaxLines,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _handleSend(),
                    style: const TextStyle(fontSize: 15),
                    decoration: InputDecoration(
                      hintText: widget.hintText,
                      hintStyle: const TextStyle(color: Color(0x661A1B1C)),
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed:
                            widget.isLoading ? null : widget.onAddAttachment,
                        icon: const Icon(
                          Icons.add_circle_outline,
                          size: 24,
                          color: Color(0x991A1B1C),
                        ),
                        tooltip: '添加附件',
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                      const Spacer(),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: widget.controller,
                        builder: (context, value, _) {
                          final canSend = !widget.isLoading &&
                              value.text.trim().isNotEmpty;
                          return IconButton.filled(
                            onPressed: canSend ? _handleSend : null,
                            icon: const Icon(Icons.arrow_upward, size: 22),
                            style: IconButton.styleFrom(
                              backgroundColor: canSend
                                  ? const Color(0xFF5B7FD4)
                                  : const Color(0x331A1B1C),
                              foregroundColor: Colors.white,
                              shape: const CircleBorder(),
                            ),
                            tooltip: '发送',
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 16, color: const Color(0x991A1B1C)),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xCC1A1B1C)),
            ),
          ],
        ),
      ),
    );
  }
}
