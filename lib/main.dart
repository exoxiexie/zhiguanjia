/// 职管家 · App 入口
///
/// 职责：组装主题、路由与顶层依赖（铁律：入口只做组装，不写业务逻辑）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'contracts/agent_service.dart';
import 'contracts/chat_service.dart';
import 'contracts/chat_session_service.dart';
import 'core/di/service_locator.dart';
import 'features/agent/agent_service_impl.dart';
import 'features/api/api_client.dart';
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
      // ── 中文本地化（v1.0.35）────────────────────────────────────────
      // 不接本地化时，MaterialApp 会回落到内置的英文 [DefaultMaterialLocalizations]，
      // 于是长按文本弹的系统菜单显示 Copy / Paste / Select all（英文），
      // 系统日期选择器等自带组件同样变英文。
      // 这里显式声明中文 + Material/Widgets/Cupertino 三套代理，
      // 一次性把「复制 / 剪切 / 粘贴 / 全选」及所有组件内置文案统一成中文。
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
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
    if (auth == null) return false;
    // 已登录：后台尽力续期服务端令牌（30 天滑动窗口）。
    // 不 await、失败也不影响本地登录态——保证断网时仍可正常进入 App。
    unawaited(ApiClient.ensureFreshSession());
    return true;
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
