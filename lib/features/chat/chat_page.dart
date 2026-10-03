/// 对话页 · 独立页面（从首页"对话"卡片进入）
///
/// 左上角：返回箭头 + 双横杠菜单图标（向右偏移，与箭头保持合适间距）
/// 右上角：提炼为记忆 + 新建对话
/// 左侧抽屉：历史会话列表
/// 主体：HomeTab（对话内容 + 输入栏）
library;

import 'package:flutter/material.dart';

import '../../contracts/agent_service.dart';
import '../../contracts/chat_service.dart';
import '../tabs/home_tab.dart';

/// 对话页
class ChatPage extends StatefulWidget {
  final ChatService chatService;
  final AgentService? agentService;

  /// 进入页面后自动填入的指令（快捷指令跳转用）
  final String? initialCommand;

  const ChatPage({
    super.key,
    required this.chatService,
    this.agentService,
    this.initialCommand,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<HomeTabState> _homeTabKey = GlobalKey<HomeTabState>();

  @override
  void initState() {
    super.initState();
    // 等对话页构建完成后，填入初始指令（如果有）
    if (widget.initialCommand != null && widget.initialCommand!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _homeTabKey.currentState?.setInputText(widget.initialCommand!);
      });
    }
  }

  /// 双杠菜单图标（上面长、下面短，经典 AI 产品风格）
  Widget _buildMenuIcon() {
    return Center(
      child: InkWell(
        onTap: () => _scaffoldKey.currentState?.openDrawer(),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                  width: 22,
                  height: 2.5,
                  decoration: BoxDecoration(
                    color: const Color(0xCC1A1B1C),
                    borderRadius: BorderRadius.circular(1.25),
                  )),
              const SizedBox(height: 6),
              Container(
                  width: 14,
                  height: 2.5,
                  decoration: BoxDecoration(
                    color: const Color(0xCC1A1B1C),
                    borderRadius: BorderRadius.circular(1.25),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  /// 左侧抽屉（历史会话列表）
  Widget _buildDrawer() {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.8,
      child: StatefulBuilder(
        builder: (ctx, setDrawerState) {
          final conversations = _homeTabKey.currentState?.conversations ?? [];
          final currentIndex = _homeTabKey.currentState?.currentIndex ?? 0;

          return Column(
            children: [
              // 顶部：新建对话按钮
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _homeTabKey.currentState?.newConversation();
                        setDrawerState(() {}); // 刷新抽屉列表
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('新建对话'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5B7FD4),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              // 历史对话列表（真实数据）
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: conversations.length,
                  itemBuilder: (ctx, i) {
                    final conv = conversations[i];
                    final active = i == currentIndex;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        active ? Icons.chat_bubble : Icons.chat_bubble_outline,
                        size: 18,
                        color: active
                            ? const Color(0xFF5B7FD4)
                            : const Color(0x661A1B1C),
                      ),
                      title: Text(
                        conv.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              active ? FontWeight.w600 : FontWeight.w400,
                          color: active
                              ? const Color(0xFF5B7FD4)
                              : const Color(0xFF1A1B1C),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${conv.messages.length} 条消息',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF9CA3AF)),
                      ),
                      selected: active,
                      onTap: () {
                        _homeTabKey.currentState?.switchConversation(i);
                        setDrawerState(() {});
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('对话'),
        centerTitle: true,
        elevation: 0,
        automaticallyImplyLeading: false,
        // leading 区域较宽（返回箭头+双横杠），必须显式设置宽度，否则被裁剪导致点击错位
        leadingWidth: 122,
        // 左上角：返回箭头 + 双横杠菜单（向右偏移，与箭头保持合适间距）
        leading: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 返回箭头
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: '返回',
              ),
              const SizedBox(width: 6),
              // 双横杠菜单图标
              _buildMenuIcon(),
            ],
          ),
        ),
        // 右上角：提炼为记忆 + 新建对话
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome, size: 22),
            onPressed: () => _homeTabKey.currentState?.extractToMemory(),
            tooltip: '提炼为记忆',
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.edit, size: 22),
            onPressed: () => _homeTabKey.currentState?.newConversation(),
            tooltip: '新建对话',
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: _buildDrawer(),
      body: HomeTab(
        key: _homeTabKey,
        chatService: widget.chatService,
        agentService: widget.agentService,
      ),
    );
  }
}
