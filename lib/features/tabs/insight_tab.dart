/// 懂你 Tab · 对话入口 + 功能栏目列表（职管家 · 个人职业版）
///
/// 顶部：对话入口卡片（点击进入对话页）+ 洞察
/// 下方：任务智能体栏目（右上角齿轮可管理卡片开关）
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/business_domain.dart';

class InsightTab extends StatefulWidget {
  /// 打开对话页回调（点击顶部"对话"板块时触发）
  final VoidCallback? onOpenChat;

  /// 打开任务智能体详情页回调（点击下方任务智能体时触发，传入智能体名称）
  final void Function(String title)? onOpenAgent;

  const InsightTab({super.key, this.onOpenChat, this.onOpenAgent});

  @override
  State<InsightTab> createState() => _InsightTabState();
}

class _InsightTabState extends State<InsightTab> {
  /// 智能体显示开关（title -> 是否显示），默认全部开启
  final Map<String, bool> _enabled = {};

  @override
  void initState() {
    super.initState();
    _loadEnabled();
  }

  Future<void> _loadEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, bool>{};
    for (final d in kBusinessDomains) {
      map[d.tag] = prefs.getBool('agent_enabled_${d.tag}') ?? true;
    }
    if (mounted) {
      setState(() {
        _enabled..clear()..addAll(map);
      });
    }
  }

  bool _isEnabled(String title) => _enabled[title] ?? true;

  /// 按偏好过滤后的可见智能体
  List<_AgentDef> get _visibleAgents => [
        for (final d in kBusinessDomains)
          if (_isEnabled(d.tag))
            _AgentDef(d.icon, d.color, d.tag, d.subtitle),
      ];

  /// 全部智能体（管理面板用）
  List<_AgentDef> get _allAgents => [
        for (final d in kBusinessDomains)
          _AgentDef(d.icon, d.color, d.tag, d.subtitle),
      ];

  Future<void> _setEnabled(String title, bool value) async {
    setState(() => _enabled[title] = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('agent_enabled_$title', value);
  }

  /// 打开任务智能体管理面板（齿轮）
  void _showManageSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.66,
        child: StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 18, 16, 4),
                    child: Text(
                      '管理任务智能体',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1B1C),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      '关闭后该智能体卡片将不在首页显示',
                      style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                    ),
                  ),
                  Flexible(
                    child: _allAgents.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                '暂无任务智能体，后续版本开放',
                                style: TextStyle(
                                    fontSize: 13, color: Color(0xFF9CA3AF)),
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            itemCount: _allAgents.length,
                            itemBuilder: (context, i) {
                              final a = _allAgents[i];
                              final enabled = _enabled[a.title] ?? true;
                              return ListTile(
                                leading: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: a.iconBg,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(a.icon,
                                      size: 18, color: Colors.white),
                                ),
                                title: Text(
                                  a.title,
                                  style: const TextStyle(
                                      fontSize: 15, color: Color(0xFF1A1B1C)),
                                ),
                                subtitle: Text(
                                  a.subtitle,
                                  style: const TextStyle(
                                      fontSize: 12, color: Color(0xFF9CA3AF)),
                                ),
                                trailing: Switch(
                                  value: enabled,
                                  activeColor: const Color(0xFF5B7FD4),
                                  onChanged: (v) {
                                    setSheetState(
                                        () => _enabled[a.title] = v);
                                    _setEnabled(a.title, v);
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 按偏好过滤需要显示的任务智能体
    final visibleAgents = _visibleAgents;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F3EE),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 16),
              // 顶部大卡片：对话 | 洞察 上下两个板块（整体浅蓝渐变）
              _buildTopCard(context),
              const SizedBox(height: 16),
              // 任务智能体栏目标题行（右侧齿轮管理开关）
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Text(
                      '任务智能体',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                    const Spacer(),
                    // 细齿轮：管理任务智能体卡片开关
                    InkWell(
                      onTap: _showManageSheet,
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.settings_outlined,
                          size: 18,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (visibleAgents.isEmpty)
                _buildEmptyHint()
              else
                _buildSection([
                  for (final a in visibleAgents)
                    _InsightItem(
                      icon: a.icon,
                      iconBg: a.iconBg,
                      title: a.title,
                      subtitle: a.subtitle,
                      onTap: () => widget.onOpenAgent?.call(a.title),
                    ),
                ]),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  /// 任务智能体为空时的占位提示
  Widget _buildEmptyHint() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Text(
          '职业任务智能体即将上线，敬请期待',
          style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
        ),
      ),
    );
  }

  /// 顶部大卡片：对话 | 洞察 上下两个板块（整体浅蓝渐变撑满，无白边）
  Widget _buildTopCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFFFF7A3D), Color(0xFFFD5C13)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // 上：对话板块（InkWell 整块区域可点，含空白处）
          InkWell(
            onTap: widget.onOpenChat,
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Row(
                  children: [
                    // 图标
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.chat_bubble_outline,
                          size: 22, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    // 标题和小字
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '对话',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '与职管家 AI 职业管家对话',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 右侧箭头
                    const Icon(Icons.arrow_forward_ios,
                        size: 16, color: Colors.white70),
                  ],
                ),
              ),
            ),
          ),
          // 分隔线（白色半透明）
          const Padding(
            padding: EdgeInsets.only(left: 56),
            child: Divider(height: 1, color: Color(0x59FFFFFF)),
          ),
          // 下：洞察板块
          InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const _PlaceholderPage(title: '洞察')),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  // 图标
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.auto_awesome,
                        size: 20, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  // 标题和副标题
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '洞察',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '基于职业数据生成分析报告',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 右侧箭头
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: Colors.white70,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(List<Widget> items) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            items[i],
            if (i < items.length - 1)
              const Padding(
                padding: EdgeInsets.only(left: 56),
                child: Divider(height: 1, color: Color(0xFFE4E3DD)),
              ),
          ],
        ],
      ),
    );
  }
}

/// 洞察栏目项
class _InsightItem extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _InsightItem({
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // 左侧图标
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 12),
            // 中间标题和副标题
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1A1B1C),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            // 右侧箭头
            const Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: Color(0xFFC4C4C4),
            ),
          ],
        ),
      ),
    );
  }
}

/// 占位页（功能开发中）
class _PlaceholderPage extends StatelessWidget {
  final String title;

  const _PlaceholderPage({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.white,
        automaticallyImplyLeading: false,
        // 左上角：向左尖括号返回（与首页顶部卡片箭头同款样式）
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 16,
            color: Color(0xFF1B3A5C),
          ),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: '返回',
        ),
      ),
      body: const Center(
        child: Text(
          '功能开发中',
          style: TextStyle(fontSize: 18, color: Color(0xFF6B7280)),
        ),
      ),
    );
  }
}

/// 任务智能体定义（图标、配色、名称、副标题）
class _AgentDef {
  final IconData icon;
  final Color iconBg;
  final String title;
  final String subtitle;

  const _AgentDef(this.icon, this.iconBg, this.title, this.subtitle);
}
