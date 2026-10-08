/// 职管家 · App 入口
///
/// 职责：组装主题、路由与顶层依赖（铁律：入口只做组装，不写业务逻辑）。
library;

import 'package:flutter/material.dart';

import 'contracts/agent_service.dart';
import 'contracts/chat_service.dart';
import 'contracts/chat_session_service.dart';
import 'core/di/service_locator.dart';
import 'features/agent/agent_service_impl.dart';
import 'features/chat/chat_service_impl.dart';
import 'features/chat/chat_session_service_impl.dart';
import 'features/personal/personal_auth_service.dart';
import 'features/personal/personal_login_page.dart';
import 'features/shell/shell_page.dart';

/// 底栏（NavigationBar）内容高度 —— 全站唯一事实来源（v1.0.31）。
///
/// 取值理由：Material 3 默认 80dp，明显高于业界主流（M2 = 56dp、
/// iOS UITabBar = 49pt、国内 App 普遍 49~56dp），观感偏"高"。
/// 压到 56dp 与主流对齐，同时仍高于 Material 规定的最小触摸高度 48dp。
/// **不含**底部系统安全区，真机总高 = 56 + 安全区。
const double kNavigationBarHeight = 56;

void main() {
  // 注册全局服务（UI 层只依赖契约，通过 sl 获取实例）
  sl.register<ChatService>(HttpChatService());
  sl.register<AgentService>(HttpAgentService());
  sl.register<ChatSessionService>(ChatSessionServiceImpl());
  runApp(const ZhiguanjiaApp());
}

/// 全站主题（唯一事实来源）。
///
/// 抽成函数而非内联，是为了让测试能拿到**同一份**配置做回归断言，
/// 避免"测试里另写一套主题、改坏了测不出来"。
ThemeData buildAppTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5B7FD4)),
      useMaterial3: true,
      // 底栏高度（v1.0.31）：M3 默认 80dp 高于业界主流，压到 [kNavigationBarHeight]。
      // 注意不含底部系统安全区，真机总高 = 该值 + 安全区（手势约 34 / 三键 48）。
      navigationBarTheme: const NavigationBarThemeData(
        height: kNavigationBarHeight,
      ),
    );

/// 应用根
class ZhiguanjiaApp extends StatelessWidget {
  const ZhiguanjiaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '职管家',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const AuthGate(),
    );
  }
}

/// 登录态闸门：已登录 → 主框架；未登录 → 个人登录页
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final ChatService _chatService;
  late final AgentService _agentService;
  late final Future<bool> _loggedInFuture;

  @override
  void initState() {
    super.initState();
    _chatService = sl.get<ChatService>();
    _agentService = sl.get<AgentService>();
    _loggedInFuture = _checkLogin();
  }

  Future<bool> _checkLogin() async {
    final auth = await PersonalAuthService.getAuth();
    return auth != null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _loggedInFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final loggedIn = snapshot.data ?? false;
        return loggedIn
            ? ShellPage(chatService: _chatService, agentService: _agentService)
            : PersonalLoginPage(
                chatService: _chatService, agentService: _agentService);
      },
    );
  }
}
