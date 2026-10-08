/// 主框架模块 · 登录后的五栏导航壳
///
/// 底部五个 Tab：对话 / 数据 / 懂你 / 发现 / 我的。
/// - 「对话」即对话首页（Agent 模式）：进入即对话，与 AI 对话完成各类任务，
///   顶栏与历史会话抽屉由对话页自身管理，因此本壳不再为其提供标题栏；
/// - 「懂你」为独立 Tab（当前占位），与「对话」职责分开：一个干活、一个懂你；
/// - 「数据」由本壳提供统一标题栏；「发现」「我的」各自管理顶栏。
/// 「说说」已折叠进「发现」页的通栏卡片，不再占用底栏。
library;

import 'package:flutter/material.dart';

import '../../contracts/agent_service.dart';
import '../../contracts/chat_service.dart';
import '../chat/chat_page.dart';
import '../common/app_nav_bar.dart';
import '../discover/discover_tab.dart';
import '../tabs/database_tab.dart';
import '../tabs/insight_tab.dart';
import '../tabs/profile_tab.dart';

/// 底栏五个 Tab 的定义（图标 / 选中图标 / 文字，v1.0.32 起自绘）
///
/// 顺序即展示顺序：对话 / 数据 / 懂你 / 发现 / 我的（index 0..4）。
const List<AppNavItem> kShellNavItems = [
  AppNavItem(
    icon: Icons.chat_bubble_outline,
    selectedIcon: Icons.chat_bubble,
    label: '对话',
  ),
  AppNavItem(
    icon: Icons.dataset_outlined,
    selectedIcon: Icons.dataset,
    label: '数据',
  ),
  AppNavItem(
    icon: Icons.lightbulb_outline,
    selectedIcon: Icons.lightbulb,
    label: '懂你',
  ),
  AppNavItem(
    icon: Icons.explore_outlined,
    selectedIcon: Icons.explore,
    label: '发现',
  ),
  AppNavItem(
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
    label: '我的',
  ),
];

/// 登录后的主框架
class ShellPage extends StatefulWidget {
  final ChatService? chatService;
  final AgentService? agentService;

  const ShellPage({super.key, this.chatService, this.agentService});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  /// Tab 索引：0 对话、1 数据、2 懂你、3 发现、4 我的
  int _index = 0;
  final GlobalKey<DatabaseTabState> _databaseTabKey =
      GlobalKey<DatabaseTabState>();
  final GlobalKey<ProfileTabState> _profileTabKey =
      GlobalKey<ProfileTabState>();

  /// 仅「数据」页使用（其余页各自管顶栏，见 build 注释）
  static const _titles = ['对话', '数据', '懂你', '发现', '我的'];

  @override
  Widget build(BuildContext context) {
    final pages = [
      // 对话 = 对话首页：自带顶栏（历史会话抽屉 + 提炼为记忆 / 新建对话）
      ChatPage(
        chatService: widget.chatService!,
        agentService: widget.agentService,
      ),
      DatabaseTab(key: _databaseTabKey),
      const InsightTab(),
      DiscoverTab(
          chatService: widget.chatService, agentService: widget.agentService),
      ProfileTab(key: _profileTabKey),
    ];

    return Scaffold(
      // 对话(0) 顶栏由对话页自身提供；懂你(2) / 发现(3) / 我的(4) 同理；
      // 仅数据(1) 用外层统一标题栏。
      appBar: _index == 1
          ? AppBar(
              title: Text(_titles[_index]),
              centerTitle: true,
              elevation: 0,
              automaticallyImplyLeading: false,
            )
          : null,
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        // 官方 NavigationBar 只当"外壳"用（高度 / 背景 / 底部安全区 / 横向均分），
        // 每格的内容换成自绘的 AppNavDestination —— 不再有选中"药丸"，
        // 图标与文字间距由 kNavIconLabelGap 控制（见 common/app_nav_bar.dart）。
        destinations: buildAppNavDestinations(
          items: kShellNavItems,
          selectedIndex: _index,
          onSelected: _onDestinationSelected,
        ),
      ),
    );
  }

  /// 切换 Tab；常驻页面按需刷新，避免显示上次的旧数据：
  /// 「数据」页是第 2 格（index 1）—— 切回时刷新记忆列表；
  /// 「我的」页是第 5 格（index 4）—— 在数据页完成实名认证后刷新认证状态。
  void _onDestinationSelected(int i) {
    setState(() => _index = i);
    if (i == 1) {
      _databaseTabKey.currentState?.refresh();
    } else if (i == 4) {
      _profileTabKey.currentState?.refresh();
    }
  }
}
