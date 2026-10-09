/// 底栏导航测试（v1.0.29 底栏 4 → 5 格）
///
/// 底栏顺序固定为：对话 / 数据 / 懂你 / 发现 / 我的。
/// 其中「懂你」为独立占位 Tab（与负责交互的「对话」职责分开），
/// 默认仍落在第 1 格「对话」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhiguanjia/contracts/chat_service.dart';
import 'package:zhiguanjia/contracts/chat_session_service.dart';
import 'package:zhiguanjia/core/di/service_locator.dart';
import 'package:zhiguanjia/features/common/app_nav_bar.dart';
import 'package:zhiguanjia/features/shell/shell_page.dart';
import 'package:zhiguanjia/features/tabs/insight_tab.dart';

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
    _conversations.insert(
        0, Conversation(id: 'c${_conversations.length + 1}', title: '新对话'));
    _index = 0;
    return _conversations.first.id;
  }

  @override
  void switchConversation(int index) => _index = index;

  @override
  Future<String> forkConversation(int uptoIndex) async => 'c1';

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

Future<void> _pumpShell(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(home: ShellPage(chatService: _FakeChatService())),
  );
  await tester.pumpAndSettle();
}

/// 取底栏各格的文字标签（自 NavigationBar 的 destinations 直接读取，精确不歧义）
///
/// v1.0.32 起 destinations 为自绘的 [AppNavDestination]（不再是官方
/// `NavigationDestination`，因为要摘掉选中"药丸"并收紧图标-文字间距）。
List<String> _labels(WidgetTester tester) {
  final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
  return nav.destinations
      .cast<AppNavDestination>()
      .map((d) => d.item.label)
      .toList();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sl.reset();
    sl.register<ChatSessionService>(_FakeSessionService());
  });

  tearDown(() => sl.reset());

  group('底栏五格导航', () {
    testWidgets('底栏为 5 格，顺序为 对话 / 数据 / 懂你 / 发现 / 我的', (tester) async {
      await _pumpShell(tester);

      expect(_labels(tester), ['对话', '数据', '懂你', '发现', '我的']);
    });

    testWidgets('默认落在第 1 格「对话」', (tester) async {
      await _pumpShell(tester);

      final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(nav.selectedIndex, 0);
    });

    testWidgets('点「懂你」切到第 3 格，且该页自带「懂你」标题', (tester) async {
      await _pumpShell(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('懂你'),
        ),
      );
      await tester.pumpAndSettle();

      final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(nav.selectedIndex, 2);

      // 占位页自身提供顶栏标题（Content 先留白）
      expect(
        find.descendant(of: find.byType(InsightTab), matching: find.text('懂你')),
        findsOneWidget,
      );
    });
  });
}
