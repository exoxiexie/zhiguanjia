/// 更新服务契约
///
/// UI 只依赖本接口做「检查更新 / 下载新版」，不接触网络与文件实现细节。
library;

/// 服务器返回的最新版本信息
class UpdateInfo {
  final String version; // 版本名，如 "1.0.1"
  final int versionCode; // 版本号，如 2（用于比较）
  final String url; // 新版 APK 下载地址
  final String note; // 更新说明

  const UpdateInfo({
    required this.version,
    required this.versionCode,
    required this.url,
    this.note = '',
  });
}

/// 检查更新的结果
class CheckResult {
  final bool hasUpdate; // 是否有新版本
  final UpdateInfo? latest; // 有更新时的最新版本信息
  final String? message; // 失败原因 / 附加说明

  const CheckResult({required this.hasUpdate, this.latest, this.message});
}

/// 更新服务抽象：检查版本 + 下载 APK
abstract class UpdateService {
  /// 检查是否有新版本（比较服务器版本号与当前安装版本号）
  Future<CheckResult> checkForUpdate();

  /// 下载新版 APK 到本地，返回本地文件路径
  /// [onProgress] 下载进度回调，取值 0.0 ~ 1.0
  Future<String> download(String url, {void Function(double)? onProgress});
}
