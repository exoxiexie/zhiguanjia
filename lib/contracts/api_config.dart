/// API 网关配置 · 服务端代理
///
/// 所有 DeepSeek 调用统一走代理服务（阿里云函数计算），
/// 真实 API Key 仅存于服务端环境变量，不进 App、不进仓库。
/// App 端只持有代理地址与调用令牌——令牌泄露后可轮换，损失可控。
library;

/// 服务端代理统一配置。
class ApiConfig {
  /// 服务端代理地址（阿里云函数计算 FC，新加坡区域）
  static const String proxyBaseUrl =
      'https://zhidongek-proxy-ocspgrobnt.ap-southeast-1.fcapp.run';

  /// 代理调用令牌（App 端内置，服务端校验；泄露可在服务端轮换）
  static const String proxyToken =
      'deff5427b5b3f9013961836bade0f56a07e54900a08297bd';

  /// 对话补全接口（OpenAI 兼容格式）
  static const String chatCompletionsUrl = '$proxyBaseUrl/chat/completions';

  /// 联网搜索接口（Anthropic 兼容格式，web_search 服务器工具）
  static const String anthropicMessagesUrl =
      '$proxyBaseUrl/anthropic/v1/messages';
}
