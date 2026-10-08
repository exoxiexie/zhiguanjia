/// 懂你 · 对话首页测试（v1.0.28 首页改造）
///
/// 改造后「懂你」Tab 自身即对话首页（Agent 模式），不再是从卡片进入的二级页：
/// 1. 左上角**没有返回箭头**（已是顶层页面）；
/// 2. 顶栏标题为「职管家」，左侧双横杠菜单、右侧「提炼为记忆 / 新建对话」齐备；
/// 3. 主体是同一条对话链（消息区 + 输入栏）；
/// 4. 首页不再出现已下线的「洞察」与「专业智能体」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhiguanjia/contracts/chat_service.dart';
import 'package:zhiguanjia/contracts/chat_session_service.dart';
import 'package:zhiguanjia/core/di/service_locator.dart';
import 'package:zhiguanjia/features/chat/chat_input_bar.dart';
import 'package:zhiguanjia/features/chat/chat_page.dart';
import 'package:zhiguanjia/features/tabs/home_tab.dart';

/// 最小可用的对话服务假实现（首页不发起请求，仅占位）
class _FakeChatService implements ChatService {
  @override
  void setPersonContext(String? contextText) {}

  @override
  void setTenantId(String? tenantId) {}

  @override
  Future<String> sendMessage(
    List<ChatMessage> history, {
    String model = 'deepseek-flash',
    bool search = false,
    String? systemExtra,
    ChatStreamCallback? onDelta,
  }) async =>
      '（测试环境）';
}

/// 最小可用的会话服务假实现（内存态，不落盘）
class _FakeSessionService implements ChatSessionService {
  final List<Conversation> _conversations = [
    Conversation(id: 'c1', title: '新对话'),
  ];
  int _index = 0;

  @override
  Future<void> init() async {}

  @override
  bool get isReady => true;

  @override
  List<Conversation> get conversations => _conversations;

  @override
  int get currentIndex => _index;

  @override
  Conversation get currentConversation => _conversations[_index];

  @override
  List<ChatMessage> get currentMessages => _conversations[_index].messages;

  @override
  Future<String> newConversation() async {
    _conversations.insert(0, Conversation(id: 'c${_conversations.length + 1}', title: '新对话'));
    _index = 0;
    return _conversations.first.id;
  }

  @override
  void switchConversation(int index) => _index = index;

  @override
  Future<void> persistMessage(ChatMessage msg) async {}

  @override
  Future<void> updateSessionTitle(String title) async {}

  @override
  Future<void> syncArchive() async {}

  @override
  Future<String?> getLastExtractedMessageId() async => null;

  @override
  Future<void> updateLastExtractedMessageId(String messageId) async {}

  @override
  Future<bool> extractToMemory({bool incremental = true}) async => true;
}

Future<void> _pumpHome(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(home: ChatPage(chatService: _FakeChatService())),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sl.reset();
    sl.register<ChatSessionService>(_FakeSessionService());
  });

  tearDown(() => sl.reset());

  group('懂你 = 对话首页', () {
    testWidgets('顶栏标题为「职管家」，且没有返回箭头', (tester) async {
      await _pumpHome(tester);

      expect(find.text('职管家'), findsOneWidget);
      expect(find.byTooltip('返回'), findsNothing);
    });

    testWidgets('顶栏保留菜单与「提炼为记忆 / 新建对话」', (tester) async {
      await _pumpHome(tester);

      expect(find.byTooltip('提炼为记忆'), findsOneWidget);
      expect(find.byTooltip('新建对话'), findsOneWidget);
    });

    testWidgets('主体是对话区：消息区 + 输入栏', (tester) async {
      await _pumpHome(tester);

      expect(find.byType(HomeTab), findsOneWidget);
      expect(find.byType(ChatInputBar), findsOneWidget);
    });

    testWidgets('左侧菜单可划出历史会话抽屉', (tester) async {
      await _pumpHome(tester);

      tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await tester.pumpAndSettle();

      expect(find.text('新建对话'), findsOneWidget);
      expect(find.text('新对话'), findsOneWidget);
    });

    testWidgets('首页不再出现「洞察」与「专业智能体」', (tester) async {
      await _pumpHome(tester);

      expect(find.text('洞察'), findsNothing);
      expect(find.text('专业智能体'), findsNothing);
      expect(find.text('学习'), findsNothing);
      expect(find.text('招聘'), findsNothing);
    });
  });
}
