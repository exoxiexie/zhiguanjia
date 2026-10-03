/// 轻量依赖注入容器（Service Locator）
///
/// 职责：统一注册和获取全局服务实例，UI 层只依赖契约（接口），
/// 不直接 new 具体实现，实现模块间硬隔离。
///
/// 用法：
/// ```dart
/// // 注册（通常在 main.dart 启动时）
/// sl.register<ChatService>(HttpChatService());
///
/// // 获取（UI 层）
/// final chatService = sl.get<ChatService>();
/// ```
library;

/// 全局服务定位器，单例。
final ServiceLocator sl = ServiceLocator._();

class ServiceLocator {
  ServiceLocator._();

  final Map<Type, dynamic> _services = {};

  /// 注册一个服务实例（按类型 T 存储）。
  void register<T>(T service) {
    _services[T] = service;
  }

  /// 获取已注册的服务实例。
  ///
  /// 未注册时抛 StateError，便于开发期发现遗漏。
  T get<T>() {
    final service = _services[T];
    if (service == null) {
      throw StateError('ServiceLocator: 未注册类型 $T，请在启动时调用 sl.register<$T>()');
    }
    return service as T;
  }

  /// 检查某类型是否已注册。
  bool isRegistered<T>() => _services.containsKey(T);

  /// 清空所有注册（主要用于测试）。
  void reset() => _services.clear();
}
