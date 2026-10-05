/// 主框架模块 · 登录后的五栏导航壳
///
/// 底部五个 Tab：懂你 / 数据 / 博客 / 发现 / 我的。
/// 对话页不再占用 Tab，改为独立页面（从首页"对话"卡片进入）。
library;

import 'package:flutter/material.dart';

import '../../contracts/agent_service.dart';
import '../../contracts/chat_service.dart';
import '../chat/business_agent_page.dart';
import '../chat/chat_page.dart';
import '../discover/discover_tab.dart';
import '../personal/personal_auth_service.dart';
import '../tabs/blog_tab.dart';
import '../tabs/database_tab.dart';
import '../tabs/insight_tab.dart';
import '../tabs/profile_tab.dart';

/// 登录后的主框架
class ShellPage extends StatefulWidget {
  final ChatService? chatService;
  final AgentService? agentService;

  const ShellPage({super.key, this.chatService, this.agentService});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  /// Tab 索引：0 懂你（首页）、1 数据、2 博客、3 发现、4 我的
  int _index = 0;
  final GlobalKey<DatabaseTabState> _databaseTabKey =
      GlobalKey<DatabaseTabState>();

  /// 当前个人租户ID（个人版以手机号作为数据隔离租户ID，注册即有、永不变）
  String _currentTenantId = '';

  @override
  void initState() {
    super.initState();
    _loadTenant();
  }

  /// 加载当前登录个人的租户ID（手机号）
  Future<void> _loadTenant() async {
    try {
      final auth = await PersonalAuthService.getAuth();
      if (auth != null && mounted) {
        setState(() => _currentTenantId = auth.phone);
      }
    } catch (_) {
      // 加载失败不影响主框架使用
    }
  }

  static const _titles = ['懂你', '数据', '博客', '发现', '我的'];

  /// 打开对话页（不带指令）
  void openChat() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatPage(
          chatService: widget.chatService!,
          agentService: widget.agentService,
        ),
      ),
    );
  }

  /// 打开任务智能体详情页（上下文按当前个人租户加载）
  void openAgent(String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BusinessAgentPage(
          title: title,
          tenantId: _currentTenantId,
          chatService: widget.chatService!,
          agentService: widget.agentService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      InsightTab(onOpenChat: openChat, onOpenAgent: openAgent),
      DatabaseTab(key: _databaseTabKey),
      const BlogTab(),
      DiscoverTab(chatService: widget.chatService, agentService: widget.agentService),
      const ProfileTab(),
    ];

    return Scaffold(
      // 懂你(0)、数据(1) 用外层统一标题栏；博客(2)/发现(3)/我的(4) 各自管理顶栏
      appBar: (_index == 0 || _index == 1)
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
        onDestinationSelected: (i) {
          setState(() => _index = i);
          // 切换到数据页时刷新记忆列表（让自动提炼的记忆立即可见）
          // 数据页是第2位（index 1）
          if (i == 1) {
            _databaseTabKey.currentState?.refresh();
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.lightbulb_outline),
            selectedIcon: Icon(Icons.lightbulb),
            label: '懂你',
          ),
          NavigationDestination(
            icon: Icon(Icons.dataset_outlined),
            selectedIcon: Icon(Icons.dataset),
            label: '数据',
          ),
          NavigationDestination(
            icon: Icon(Icons.article_outlined),
            selectedIcon: Icon(Icons.article),
            label: '博客',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: '发现',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
