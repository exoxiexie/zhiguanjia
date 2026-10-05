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

void main() {
  // 注册全局服务（UI 层只依赖契约，通过 sl 获取实例）
  sl.register<ChatService>(HttpChatService());
  sl.register<AgentService>(HttpAgentService());
  sl.register<ChatSessionService>(ChatSessionServiceImpl());
  runApp(const ZhiguanjiaApp());
}

/// 应用根
class ZhiguanjiaApp extends StatelessWidget {
  const ZhiguanjiaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '职管家',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5B7FD4)),
        useMaterial3: true,
      ),
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
