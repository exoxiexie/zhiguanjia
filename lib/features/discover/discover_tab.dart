/// 发现 Tab（职管家 · 个人职业版）
///
/// 职业机会发现：职位推荐流（职位卡片列表）。
/// 当前版本：职位卡片按设计稿静态展示（mock 数据，可点 × 本地移除）；
/// 顶部搜索 / 新增 / 城市 / 筛选 / 推荐流切换等仅为占位 UI，交互与数据后续开发。
library;

import 'package:flutter/material.dart';

import '../../contracts/agent_service.dart';
import '../../contracts/chat_service.dart';

/// 品牌活力橙
const Color _kBrandOrange = Color(0xFFFD5C13);

/// 薪资青绿（招聘场景惯例色，按设计稿）
const Color _kSalaryGreen = Color(0xFF16B89C);

/// 发现页（职业机会发现）
class DiscoverTab extends StatefulWidget {
  final ChatService? chatService;
  final AgentService? agentService;

  const DiscoverTab({super.key, this.chatService, this.agentService});

  @override
  State<DiscoverTab> createState() => _DiscoverTabState();
}

/// 职位数据模型（当前为本地 mock，后续替换为接口数据）
class _Job {
  final String title; // 职位名
  final String salary; // 薪资
  final String company; // 公司
  final String finance; // 融资阶段
  final String scale; // 公司规模
  final List<String> tags; // 经验/学历/福利等标签
  final String hrName; // HR 称呼
  final String hrRole; // HR 职位
  final String? active; // 活跃度（如「今日活跃」，null 不显示）
  final String district; // 区
  final String area; // 商圈
  final bool dimmed; // 是否灰显（已读/不匹配）
  final Color avatarColor; // 头像底色

  const _Job({
    required this.title,
    required this.salary,
    required this.company,
    required this.finance,
    required this.scale,
    required this.tags,
    required this.hrName,
    required this.hrRole,
    required this.district,
    required this.area,
    required this.avatarColor,
    this.active,
    this.dimmed = false,
  });
}

class _DiscoverTabState extends State<DiscoverTab> {
  static const List<String> _feedTabs = ['推荐', '附近', '最新'];
  int _feedIndex = 0;

  final List<_Job> _jobs = [
    const _Job(
      title: 'AI产品经理',
      salary: '20-25K·14薪',
      company: '四川安正集团',
      finance: '不需要融资',
      scale: '100-499人',
      tags: ['3-5年', '本科', 'B端产品'],
      hrName: '余女士',
      hrRole: 'HR',
      district: '武侯区',
      area: '桂溪',
      avatarColor: Color(0xFFFF7A3D),
    ),
    const _Job(
      title: 'FDE前线部署工程师/15K-30k',
      salary: '15-30K',
      company: '四川弦序人工智能科技',
      finance: '天使轮',
      scale: '20-99人',
      tags: ['3-5年', '本科', '双休'],
      hrName: '金晶',
      hrRole: '人事经理',
      active: '今日活跃',
      district: '武侯区',
      area: '银泰城',
      avatarColor: Color(0xFF5B7FD4),
    ),
    const _Job(
      title: 'ai产品经理',
      salary: '15-30K',
      company: '青霆科技',
      finance: 'A轮',
      scale: '20-99人',
      tags: ['3-5年', '本科'],
      hrName: '李女士',
      hrRole: '人事',
      district: '锦江区',
      area: '东光',
      dimmed: true,
      avatarColor: Color(0xFF16B89C),
    ),
    const _Job(
      title: '策略产品 薪资：12K-20K（根据能力面议）',
      salary: '12-20K',
      company: '粗门',
      finance: 'A轮',
      scale: '20-99人',
      tags: ['3-5年', '大专', '用户/功能产品', '用增产品'],
      hrName: '王女士',
      hrRole: '招聘顾问',
      district: '高新区',
      area: '天府三街',
      avatarColor: Color(0xFF7C3AED),
    ),
  ];

  void _todo() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('该功能开发中')),
    );
  }

  void _removeJob(int index) {
    setState(() => _jobs.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  /// 顶部：标题 + 新增/搜索（占位）；推荐流 Tab + 城市/筛选（占位）
  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                '职位推荐',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1B1C),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _todo,
                child: const Icon(Icons.add, size: 28, color: Color(0xFF1A1B1C)),
              ),
              const SizedBox(width: 20),
              GestureDetector(
                onTap: _todo,
                child: const Icon(Icons.search,
                    size: 27, color: Color(0xFF1A1B1C)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < _feedTabs.length; i++) ...[
                GestureDetector(
                  onTap: () => setState(() => _feedIndex = i),
                  child: Text(
                    _feedTabs[i],
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight:
                          i == _feedIndex ? FontWeight.w700 : FontWeight.w400,
                      color: i == _feedIndex
                          ? _kBrandOrange
                          : const Color(0xFF9CA3AF),
                    ),
                  ),
                ),
                const SizedBox(width: 24),
              ],
              const Spacer(),
              _buildPillButton('成都'),
              const SizedBox(width: 10),
              _buildPillButton('筛选'),
            ],
          ),
        ],
      ),
    );
  }

  /// 城市 / 筛选 浅灰胶囊按钮（占位）
  Widget _buildPillButton(String text) {
    return GestureDetector(
      onTap: _todo,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: const TextStyle(fontSize: 14, color: Color(0xFF374151)),
            ),
            const Icon(Icons.arrow_drop_down,
                size: 18, color: Color(0xFF6B7280)),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_jobs.isEmpty) {
      return const Center(
        child: Text('暂无更多职位',
            style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 12, bottom: 16),
      itemCount: _jobs.length,
      itemBuilder: (context, index) => _buildJobCard(_jobs[index], index),
    );
  }

  Widget _buildJobCard(_Job job, int index) {
    final titleColor =
        job.dimmed ? const Color(0xFF9CA3AF) : const Color(0xFF1A1B1C);
    final subColor =
        job.dimmed ? const Color(0xFFB5B9C0) : const Color(0xFF6B7280);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _todo,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 职位名 + 薪资
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        job.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: titleColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      job.salary,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _kSalaryGreen,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // 公司 + 融资 + 规模
                Text(
                  '${job.company}  ${job.finance}  ${job.scale}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: subColor),
                ),
                const SizedBox(height: 12),
                // 标签
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in job.tags)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          t,
                          style: TextStyle(fontSize: 13, color: subColor),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                // HR + 地点 + 关闭
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: job.avatarColor,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        job.hrName.substring(0, 1),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${job.hrName} · ${job.hrRole}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: titleColor,
                            ),
                          ),
                          if (job.active != null) ...[
                            const SizedBox(height: 2),
                            const Text(
                              '今日活跃',
                              style: TextStyle(
                                  fontSize: 12, color: _kSalaryGreen),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Text(
                      '${job.district} ${job.area}',
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF9CA3AF)),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => _removeJob(index),
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close,
                            size: 18, color: Color(0xFFC4C8CE)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
