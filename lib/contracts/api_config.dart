/// API 网关配置 · 服务端代理
///
/// 所有 DeepSeek 调用统一走代理服务（阿里云函数计算），
/// 真实 API Key 仅存于服务端环境变量，不进 App、不进仓库。
/// App 端只持有代理地址与调用令牌——令牌泄露后可轮换，损失可控。
library;

/// 服务端代理统一配置。
class ApiConfig {
  /// 服务端代理地址（阿里云函数计算 FC，成都区域）
  ///
  /// v1.0.34 起由新加坡（`ap-southeast-1`）迁至成都（`cn-chengdu`）：
  /// 实测握手环节 TLS 0.736s → 0.040s，建立连接明显更快。
  static const String proxyBaseUrl =
      'https://zhidongk-api-cd-nknkhdghnt.cn-chengdu.fcapp.run';

  /// 代理调用令牌（App 端内置，服务端校验；泄露可在服务端轮换）
  static const String proxyToken =
      'deff5427b5b3f9013961836bade0f56a07e54900a08297bd';

  /// 对话补全接口（OpenAI 兼容格式）
  static const String chatCompletionsUrl = '$proxyBaseUrl/chat/completions';

  /// 联网搜索接口（Anthropic 兼容格式，web_search 服务器工具）
  static const String anthropicMessagesUrl =
      '$proxyBaseUrl/anthropic/v1/messages';

  // ── 商业版业务 API（P1 起）─────────────────────────────────────────
  //
  // 自建于阿里云 ECS（与官网同机），经 Nginx 反代 `/api/` → 本机 8000。
  //
  // TODO(备案): 域名 zhidongni.com.cn 备案通过后，把这里改成
  // `https://zhidongni.com.cn/api` 并启用 HTTPS——**App 侧只改这一处**。
  // 开发期用 HTTP：Android 已允许明文（AndroidManifest 中
  // usesCleartextTraffic="true"），且当前仅自用，无第三方风险。
  static const String apiBaseUrl = 'http://8.137.71.241/api';
}
