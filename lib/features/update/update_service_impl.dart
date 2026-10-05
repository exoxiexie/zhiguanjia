/// 基于 HTTP 的更新服务实现
///
/// 支持多个更新源：按顺序从 [baseUrls] 读取 version.json，
/// 第一个成功的源生效（Gitee 优先，GitHub 回退），
/// 再用 version.json 里的 url 字段下载新版 APK。
/// 目录隔离：本模块只属于 update 域，不依赖其他业务模块。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../contracts/update_service.dart';

class HttpUpdateService implements UpdateService {
  /// 更新源列表（按优先级排序，依序尝试）
  final List<String> baseUrls;
  final Dio _dio;

  HttpUpdateService({required this.baseUrls, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 30),
              // 伪装成浏览器请求，绕过 Gitee WAF 对非浏览器 UA 的限速
              headers: const {
                'User-Agent':
                    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                'Accept': 'application/json, text/plain, */*',
                'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
                'Cache-Control': 'no-cache',
              },
            ));

  /// 依序尝试每个更新源读取 version.json，第一个成功即返回
  /// 总超时保护：30 秒内必须返回，避免一直转圈
  Future<Map<String, dynamic>> _fetchVersionInfo() async {
    return _fetchVersionInfoWithSources().timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw Exception('检查更新超时（30秒）'),
    );
  }

  Future<Map<String, dynamic>> _fetchVersionInfoWithSources() async {
    Object? lastError;
    // 时间戳绕过 CDN 缓存
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    for (final baseUrl in baseUrls) {
      try {
        // Gitee API 用 ref=master 参数，其他源用时间戳绕过缓存
        final url = baseUrl.contains('gitee.com/api')
            ? '$baseUrl/version.json?ref=master'
            : '$baseUrl/version.json?t=$timestamp';
        final resp = await _dio.get(url);
        final raw = resp.data;
        // 兼容两种返回格式：
        // 1. Gitee API：返回 Map，content 字段是 base64 编码的 JSON
        // 2. GitHub raw：返回纯文本 JSON 字符串
        if (raw is Map && raw['content'] != null) {
          // Gitee API 格式：解码 base64
          final decoded = utf8.decode(base64Decode(raw['content'].toString()));
          return jsonDecode(decoded) as Map<String, dynamic>;
        }
        if (raw is String) {
          return jsonDecode(raw) as Map<String, dynamic>;
        }
        return (raw as Map).cast<String, dynamic>();
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('所有更新源均不可用：$lastError');
  }

  @override
  Future<CheckResult> checkForUpdate() async {
    try {
      final data = await _fetchVersionInfo();
      final latestCode = int.tryParse('${data['versionCode'] ?? ''}') ?? 0;
      // 兼容两种字段名：Gitee 用 versionName，GitHub 用 version
      final latestVersion =
          (data['versionName'] ?? data['version'])?.toString() ?? '';

      final pkg = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(pkg.buildNumber) ?? 0;

      final hasUpdate = latestCode > currentCode;
      return CheckResult(
        hasUpdate: hasUpdate,
        latest: hasUpdate
            ? UpdateInfo(
                version: latestVersion,
                versionCode: latestCode,
                url: data['url']?.toString() ?? '',
                // 兼容两种字段名：Gitee 用 changelog，GitHub 用 note
                note: (data['changelog'] ?? data['note'])?.toString() ?? '',
              )
            : null,
        message: hasUpdate ? null : '已是最新版本（v${pkg.version}）',
      );
    } catch (e) {
      return CheckResult(hasUpdate: false, message: '检查更新失败：$e');
    }
  }

  @override
  Future<String> download(String url,
      {void Function(double)? onProgress}) async {
    final dir = await getApplicationDocumentsDirectory();
    final savePath = '${dir.path}/zhiguanjia_update.apk';

    await _dio.download(
      url,
      savePath,
      onReceiveProgress: (received, total) {
        if (onProgress == null) return;
        if (total > 0) {
          // 已知总大小，传 0.0 ~ 1.0 的进度
          onProgress(received / total);
        } else {
          // 未知总大小（chunked 传输），传已下载字节数（负数标识）
          onProgress(-received.toDouble());
        }
      },
    );
    return savePath;
  }
}
