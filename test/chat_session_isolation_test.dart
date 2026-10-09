/// 会话服务「换账号数据隔离」回归测试（缺陷 P0-1）
///
/// 背景：`ChatSessionServiceImpl` 是 `main.dart` 注册的**进程级单例**，
/// 退出登录不会重建实例。修复前 `init()` 只在"新账号有历史会话"时才清空
/// 内存列表，导致本机无历史会话的新账号直接读到上一账号的会话与消息正文。
///
/// 本测试不依赖数据库（数据库层按手机号分目录，本身是隔离的），
/// 专门验证**内存态**这一层的清理——泄漏正是发生在这一层。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhiguanjia/contracts/chat_service.dart';
import 'package:zhiguanjia/features/chat/chat_session_service_impl.dart';

void main() {
  late ChatSessionServiceImpl service;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    service = ChatSessionServiceImpl();
  });

  test('初始状态：恰好一个占位会话，索引 0，消息为空（界面读取不越界）', () {
    expect(service.conversations.length, 1);
    expect(service.currentIndex, 0);
    expect(service.currentConversation.title, '新对话');
    expect(service.currentMessages, isEmpty);
  });

  test('reset() 回到「刚安装、未登录」状态：清空会话内容并保留一个空占位', () {
    // 造出"上一个账号"的内存内容
    service.currentMessages
        .add(ChatMessage(role: 'user', content: '账号A的隐私提问'));
    expect(service.currentMessages, isNotEmpty);

    service.reset();

    expect(service.conversations.length, 1, reason: '不得残留上一账号的会话');
    expect(service.conversations.first.id, 'default');
    expect(service.conversations.first.messages, isEmpty,
        reason: '上一账号的消息内容必须清空');
    expect(service.currentIndex, 0);
    expect(service.isReady, isFalse, reason: 'reset 后需重新 init');
  });

  test('核心场景：换账号 init() 后，上一账号的会话与消息全部消失', () async {
    // ── 账号 A：一个带消息的会话 + 另一个新会话 ──
    service.currentMessages
        .add(ChatMessage(role: 'user', content: '账号A的隐私提问'));
    final aSecondId = await service.newConversation();
    final aIds = service.conversations.map((c) => c.id).toList();

    expect(service.conversations.length, 2, reason: 'A 应有两个会话');
    expect(service.conversations.any((c) => c.messages.isNotEmpty), isTrue,
        reason: 'A 确实有对话内容');

    // ── 账号 B 登录：init() 必须把 A 的内存态整体清空 ──
    await service.init();

    expect(
      service.conversations.any((c) => c.messages.isNotEmpty),
      isFalse,
      reason: '账号 B 不得看到账号 A 的任何消息内容',
    );
    expect(
      service.conversations.map((c) => c.id).toList(),
      isNot(contains(aSecondId)),
      reason: '账号 B 不得看到账号 A 的会话（id=$aSecondId）',
    );
    expect(aIds, isNotEmpty); // 仅用于说明 A 侧确实产生过会话
  });

  test('init() 无论成功失败都保证列表非空（避免界面越界崩溃）', () async {
    await service.init();
    expect(service.conversations, isNotEmpty);
    expect(() => service.currentMessages, returnsNormally);
    expect(() => service.currentConversation, returnsNormally);
  });
}
