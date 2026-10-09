/// 懂你 · 对话首页测试（v1.0.28 首页改造）
///
/// 改造后「懂你」Tab 自身即对话首页（Agent 模式），不再是从卡片进入的二级页：
/// 1. 左上角**没有返回箭头**（已是顶层页面）；
/// 2. 顶栏标题为「职管家」，左侧双横杠菜单、右侧「新建对话」；
///    输入栏上方为「快捷指令 / 提炼记忆」两个按钮；
/// 3. 主体是同一条对话链（消息区 + 输入栏）；
/// 4. 首页不再出现已下线的「洞察」与「专业智能体」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhiguanjia/contracts/chat_service.dart';
import 'package:zhiguanjia/features/chat/message_action_bar.dart';
import 'package:zhiguanjia/features/chat/preset_commands_page.dart';
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

  /// 给首个会话塞入若干消息（供分叉用例构造历史）
  void seed(List<ChatMessage> messages) {
    _conversations.first.messages.addAll(messages);
  }

  @override
  Future<void> init() async {}

  @override
  void reset() {
    _conversations
      ..clear()
      ..add(Conversation(id: 'default', title: '新对话'));
    _index = 0;
  }

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
  Future<String> forkConversation(int uptoIndex) async {
    final src = _conversations[_index];
    final end = (uptoIndex + 1).clamp(0, src.messages.length);
    final copied = <ChatMessage>[
      for (var i = 0; i < end; i++)
        ChatMessage(
          role: src.messages[i].role,
          content: src.messages[i].content,
        ),
    ];
    final id = 'fork${_conversations.length + 1}';
    _conversations.insert(
      0,
      Conversation(id: id, title: '${src.title}（分叉）', messages: copied),
    );
    _index = 0;
    return id;
  }

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

    testWidgets('顶栏保留「新建对话」（提炼记忆已下移到输入栏）', (tester) async {
      await _pumpHome(tester);

      expect(find.byTooltip('新建对话'), findsOneWidget);
      expect(find.byTooltip('提炼为记忆'), findsNothing, reason: '顶栏魔法星星已移入输入栏');
    });

    testWidgets('输入栏上方是「快捷指令」与「提炼记忆」两个按钮', (tester) async {
      await _pumpHome(tester);

      expect(find.text('快捷指令'), findsOneWidget);
      expect(find.text('提炼记忆'), findsOneWidget);
      expect(find.text('连接电脑'), findsNothing, reason: '旧按钮已替换');
      expect(find.text('技能选择'), findsNothing, reason: '旧按钮已替换');
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

  group('对话分叉', () {
    testWidgets('AI 回复气泡带「分叉」按钮，用户气泡不带', (tester) async {
      final svc = _FakeSessionService()
        ..seed(const [
          ChatMessage(role: 'user', content: '帮我改简历'),
          ChatMessage(role: 'assistant', content: '好的，请把简历发我'),
        ]);
      sl.reset();
      sl.register<ChatSessionService>(svc);

      await _pumpHome(tester);

      // 只有 AI 回复挂「分叉」（用户消息与流式中气泡都不挂）
      expect(find.text('分叉'), findsOneWidget);
    });

    testWidgets('点「分叉」新建会话并复制分叉点（含）之前的全部消息，原对话不变',
        (tester) async {
      final svc = _FakeSessionService()
        ..seed(const [
          ChatMessage(role: 'user', content: '帮我改简历'),
          ChatMessage(role: 'assistant', content: '好的，请把简历发我'),
        ]);
      sl.reset();
      sl.register<ChatSessionService>(svc);

      await _pumpHome(tester);
      await tester.tap(find.text('分叉'));
      await tester.pumpAndSettle();

      expect(svc.conversations.length, 2, reason: '分叉应新增一个会话');
      expect(svc.currentIndex, 0, reason: '分叉后应切到新会话');
      expect(svc.currentConversation.title, '新对话（分叉）');
      expect(svc.currentMessages.length, 2,
          reason: '新会话应复制分叉点（含）之前的全部消息');
      expect(svc.conversations[1].messages.length, 2, reason: '原会话保持不变');
    });
  });

  group('气泡操作条：分叉与提炼', () {
    testWidgets('AI 回复挂「分叉 + 提炼」，用户气泡都不挂', (tester) async {
      final svc = _FakeSessionService()
        ..seed(const <ChatMessage>[
          ChatMessage(role: 'user', content: '帮我改简历'),
          ChatMessage(role: 'assistant', content: '好的，请把简历发我'),
        ]);
      sl.reset();
      sl.register<ChatSessionService>(svc);

      await _pumpHome(tester);

      expect(find.text('分叉'), findsOneWidget);
      expect(find.text('提炼'), findsOneWidget, reason: '提炼排在分叉之后');
      // 两个按钮同属 AI 气泡操作条
      expect(find.byType(MessageActionBar), findsOneWidget);
    });

    testWidgets('点「提炼」当前为占位提示（功能下个版本接入）', (tester) async {
      final svc = _FakeSessionService()
        ..seed(const <ChatMessage>[
          ChatMessage(role: 'user', content: '帮我改简历'),
          ChatMessage(role: 'assistant', content: '好的，请把简历发我'),
        ]);
      sl.reset();
      sl.register<ChatSessionService>(svc);

      await _pumpHome(tester);
      await tester.tap(find.text('提炼'));
      await tester.pump();

      expect(find.text('「提炼」即将上线，敬请期待'), findsOneWidget);
    });
  });

  group('输入栏胶囊按钮', () {
    testWidgets('点「快捷指令」打开预设指令列表', (tester) async {
      await _pumpHome(tester);

      await tester.tap(find.text('快捷指令'));
      await tester.pumpAndSettle();

      expect(find.byType(PresetCommandsPage), findsOneWidget);
    });

    testWidgets('两个按钮为胶囊底（圆角 16 + 浅底），不再是"图标+文字"', (tester) async {
      await _pumpHome(tester);

      for (final label in <String>['快捷指令', '提炼记忆']) {
        final pill = find.ancestor(
          of: find.text(label),
          matching: find.byType(Container),
        );
        expect(pill, findsWidgets, reason: label + ' 应在胶囊容器内');
        final box = tester.widget<Container>(pill.first);
        final deco = box.decoration as BoxDecoration;
        expect(deco.color, const Color(0x0F000000), reason: label + ' 胶囊底色');
        expect((deco.borderRadius as BorderRadius).topLeft.x, 16,
            reason: label + ' 胶囊圆角');
      }
    });
  });

  group('回到底部箭头', () {
    testWidgets('滑离底部时浮出箭头，点击后回到底部并隐藏', (tester) async {
      final svc = _FakeSessionService()
        ..seed(List<ChatMessage>.generate(
          30,
          (i) => ChatMessage(
            role: i.isEven ? 'user' : 'assistant',
            content: '第 $i 条较长内容，用于把列表撑到可滚动高度，确保能滑离底部。',
          ),
        ));
      sl.reset();
      sl.register<ChatSessionService>(svc);

      await _pumpHome(tester);

      double arrowOpacity() {
        final f = find.ancestor(
          of: find.byIcon(Icons.keyboard_arrow_down_rounded),
          matching: find.byType(AnimatedOpacity),
        );
        return tester.widget<AnimatedOpacity>(f.first).opacity;
      }

      expect(arrowOpacity(), 0, reason: '初始在底部：箭头隐藏');

      // 直接驱动滚动（气泡里的 SelectableText 会吞掉拖拽手势，
      // 用控制器位移同样会触发滚动监听，验证的是同一套显隐逻辑）
      final controller =
          tester.widget<ListView>(find.byType(ListView)).controller!;
      expect(controller.position.maxScrollExtent, greaterThan(0),
          reason: '用例前提：列表可滚动');
      controller.jumpTo(controller.position.maxScrollExtent - 400);
      await tester.pumpAndSettle();
      expect(arrowOpacity(), 1, reason: '滑离底部后箭头出现');

      // 点箭头 → 回到底部
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await tester.pumpAndSettle();
      expect(arrowOpacity(), 0, reason: '回到最底部后箭头自动隐藏');
    });
  });
}
