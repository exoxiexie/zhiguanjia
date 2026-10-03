/// 快捷指令列表页 · 对话页顶部"试试像这样给我下指令"卡片点击后进入
///
/// 分类展示预设指令，点击后通过 [onSelect] 回调填入输入框。
library;

import 'package:flutter/material.dart';

/// 快捷指令列表页
class PresetCommandsPage extends StatelessWidget {
  final void Function(String command)? onSelect;

  const PresetCommandsPage({super.key, this.onSelect});

  /// 预设指令分类和内容（职管家 · 个人职业场景）
  List<PresetCommandCategory> get _categories => [
        PresetCommandCategory(
          name: '热门指令',
          icon: Icons.local_fire_department_outlined,
          color: const Color(0xFFF97316),
          commands: [
            '结合我的职业背景和技能，帮我做一次全面的职业现状诊断，给出可执行的发展建议',
            '根据我的工作经历，帮我梳理当前的核心竞争力和需要补齐的短板',
            '帮我检查一下我的职业规划有没有明显的风险或误区，包括行业趋势和岗位选择',
          ],
        ),
        PresetCommandCategory(
          name: '职业规划',
          icon: Icons.analytics_outlined,
          color: const Color(0xFF2563EB),
          commands: [
            '结合我的岗位、技能和所在行业，分析我未来3年的职业发展路径',
            '根据我的背景，帮我制定一份未来一年的职业成长计划，按季度列出目标和行动项',
            '帮我分析当前岗位的晋升空间，以及是否需要考虑转岗或转行',
          ],
        ),
        PresetCommandCategory(
          name: '简历求职',
          icon: Icons.description_outlined,
          color: const Color(0xFFDC2626),
          commands: [
            '帮我优化简历，针对目标岗位突出匹配的经历、项目和技能',
            '我马上要参加一场面试，帮我准备这个岗位常见的面试问题和回答思路',
            '帮我写一段有说服力的自我介绍，适用于求职面试开场',
          ],
        ),
        PresetCommandCategory(
          name: '技能成长',
          icon: Icons.trending_up_outlined,
          color: const Color(0xFF7C3AED),
          commands: [
            '根据我的目标岗位，帮我规划需要学习的技能栈和学习顺序',
            '帮我制定一份为期3个月的学习计划，安排每周的学习重点和练习任务',
            '推荐适合我当前水平的证书或课程，并说明它们对求职的实际帮助',
          ],
        ),
        PresetCommandCategory(
          name: '职场日常',
          icon: Icons.work_outline,
          color: const Color(0xFF059669),
          commands: [
            '帮我准备一次和领导的加薪沟通，列出谈判要点和话术',
            '帮我写一封得体的工作邮件，用于和同事或客户沟通项目进展',
            '我遇到了职场上的困惑或劳动权益问题，帮我分析情况并给出应对建议',
          ],
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('快捷指令'),
        backgroundColor: Colors.white,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          return _buildCategoryCard(context, category);
        },
      ),
    );
  }

  Widget _buildCategoryCard(
      BuildContext context, PresetCommandCategory category) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 分类标题
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: category.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(category.icon, size: 16, color: category.color),
                ),
                const SizedBox(width: 8),
                Text(
                  category.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1B1C),
                  ),
                ),
              ],
            ),
          ),
          // 指令列表
          for (int i = 0; i < category.commands.length; i++) ...[
            InkWell(
              onTap: () {
                onSelect?.call(category.commands[i]);
                Navigator.of(context).pop();
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        category.commands[i],
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF4B5563),
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward,
                        size: 14, color: Color(0xFFC4C4C4)),
                  ],
                ),
              ),
            ),
            if (i < category.commands.length - 1)
              const Padding(
                padding: EdgeInsets.only(left: 16),
                child: Divider(height: 1, color: Color(0xFFF0F0F0)),
              ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// 预设指令分类模型
class PresetCommandCategory {
  final String name;
  final IconData icon;
  final Color color;
  final List<String> commands;

  const PresetCommandCategory({
    required this.name,
    required this.icon,
    required this.color,
    required this.commands,
  });
}
