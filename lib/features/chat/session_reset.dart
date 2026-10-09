/// 退出登录 / 切换账号时的**数据隔离重置**（修复 P0-1、P0-2）
///
/// 背景：`ChatSessionService`、`ChatService`、`AgentService` 都是 `main.dart`
/// 里注册一次的**进程级单例**。退出登录只清 `SharedPreferences` 里的登录态，
/// 这些单例的内存字段（会话列表、租户 ID、身份上下文）会原样留存，于是：
/// - 下一个账号（本机无历史会话）直接读到上一个账号的会话与消息正文（P0-1）
/// - 下一个账号未实名时，联网搜索沉淀会写进上一个账号的租户目录（P0-2）
///
/// 本文件是**唯一**的清理入口：将来新增"按账号隔离的进程级服务"时，
/// 只需在这里补一行，避免各处退出流程各写一套、漏掉某个服务。
library;

import '../../contracts/agent_service.dart';
import '../../contracts/chat_service.dart';
import '../../contracts/chat_session_service.dart';
import '../../core/di/service_locator.dart';

/// 重置全部按账号隔离的进程级服务状态。
///
/// 任何一步失败都不会抛出，也不会中断退出登录流程——
/// 清理失败最多是多留一点内存态，不能让用户退不出去。
void resetUserSessionState() {
  _safely(() {
    sl.get<ChatSessionService>().reset();
  });
  _safely(() {
    sl.get<ChatService>()
      ..setPersonContext(null)
      ..setTenantId(null);
  });
  _safely(() {
    sl.get<AgentService>()
      ..setPersonContext(null)
      ..setTenantId(null);
  });
}

void _safely(void Function() action) {
  try {
    action();
  } catch (_) {
    // DI 容器未注册（如纯单元测试环境）时忽略：
    // 清理是"尽力而为"，绝不能因此阻塞退出登录
  }
}
