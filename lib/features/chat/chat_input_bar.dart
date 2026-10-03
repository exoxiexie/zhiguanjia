/// 公共对话输入栏 · 对话页与业务智能体详情页共用
///
/// 样式与对话页输入栏完全一致：
/// - 顶部工具行：模型选择 + 连接电脑 + 技能选择
/// - 输入框（2~5行自适应）+ 附件按钮 + 发送按钮
library;

import 'package:flutter/material.dart';

import '../../contracts/chat_service.dart';

/// 对话输入栏
class ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;

  /// 待发送附件（由外部构造好传入，null 则不显示）
  final Widget? pendingAttachment;

  final ChatModel selectedModel;
  final ValueChanged<ChatModel>? onModelChanged;
  final VoidCallback? onAddAttachment;
  final VoidCallback? onSend;
  final VoidCallback? onConnectComputer;
  final VoidCallback? onSkillSelect;

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
    this.onConnectComputer,
    this.onSkillSelect,
    this.showTopBar = true,
    this.hintText = '输入你的问题…',
  });

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
            if (pendingAttachment != null) pendingAttachment!,
            if (showTopBar) ...[
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
                          value: selectedModel,
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
                          onChanged: isLoading
                              ? null
                              : (m) {
                                  if (m != null) onModelChanged?.call(m);
                                },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildFeatureButton(
                      icon: Icons.computer,
                      label: '连接电脑',
                      onTap: onConnectComputer,
                    ),
                    const SizedBox(width: 8),
                    _buildFeatureButton(
                      icon: Icons.extension,
                      label: '技能选择',
                      onTap: onSkillSelect,
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
                    controller: controller,
                    minLines: 2,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend?.call(),
                    style: const TextStyle(fontSize: 15),
                    decoration: InputDecoration(
                      hintText: hintText,
                      hintStyle: const TextStyle(color: Color(0x661A1B1C)),
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: isLoading ? null : onAddAttachment,
                        icon: const Icon(
                          Icons.add_circle_outline,
                          size: 24,
                          color: Color(0x991A1B1C),
                        ),
                        tooltip: '添加附件',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 32, minHeight: 32),
                      ),
                      const Spacer(),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder: (context, value, _) {
                          final canSend = !isLoading &&
                              value.text.trim().isNotEmpty;
                          return IconButton.filled(
                            onPressed: canSend ? onSend : null,
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
