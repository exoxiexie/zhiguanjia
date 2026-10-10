/// 基于 HTTP 的更新服务实现
///
/// 更新源**并行读取**：主源（Gitee）成功即采用，其余源仅作回退。
/// 注意 GitHub 只是**读源回退**（镜像可能滞后于 Gitee），**不是下载备份** ——
/// 下载地址始终取自 version.json 的 url 字段（指向 Gitee Release）。
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

  /// 单源读取超时。并行竞速下每个源只给这么久（原为逐源尝试、总超时 30 秒）
  static const Duration _kPerSourceTimeout = Duration(seconds: 7);

  /// 兜底总超时。并行后正常路径约 1 秒、失败路径约 7 秒，远快于此
  static const Duration _kTotalTimeout = Duration(seconds: 15);

  Future<Map<String, dynamic>> _fetchVersionInfo() {
    return _fetchVersionInfoWithSources().timeout(
      _kTotalTimeout,
      onTimeout: () => throw Exception('检查更新超时'),
    );
  }

  /// 并行读取更新源：**主源成功就用主源**，其余源只作回退
  ///
  /// 为什么并行：原来逐源尝试，Gitee 一挂用户要等满 30 秒才看到失败；
  /// 并行后回退源已经在飞行中，主源失败可立即采用 → 最坏从 30 秒降到约 7 秒。
  ///
  /// 为什么"主源优先"而不是"谁快用谁"：GitHub 镜像可能滞后于 Gitee，
  /// 若谁快用谁，可能读到旧版本号 → 误报「已是最新」。
  Future<Map<String, dynamic>> _fetchVersionInfoWithSources() async {
    if (baseUrls.isEmpty) {
      throw Exception('未配置更新源');
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // 全部并发发起；非主源先挂错误处理，避免主源成功后被判为「未处理异常」
    final primary = _fetchOne(baseUrls.first, timestamp);
    final fallbacks = <Future<Map<String, dynamic>?>>[
      for (final baseUrl in baseUrls.skip(1))
        _fetchOne(baseUrl, timestamp)
            .then<Map<String, dynamic>?>((v) => v, onError: (_) => null),
    ];

    Object? lastError;
    try {
      return await primary;
    } catch (e) {
      lastError = e;
    }
    for (final fallback in fallbacks) {
      final data = await fallback; // 已在飞行中，通常立刻拿到
      if (data != null) return data;
    }
    throw Exception('所有更新源均不可用：$lastError');
  }

  /// 读取单个更新源（带单源超时）
  Future<Map<String, dynamic>> _fetchOne(String baseUrl, int timestamp) async {
    // Gitee API 用 ref=master，其他源用时间戳绕过 CDN 缓存
    final url = baseUrl.contains('gitee.com/api')
        ? '$baseUrl/version.json?ref=master'
        : '$baseUrl/version.json?t=$timestamp';
    final resp = await _dio.get(url).timeout(_kPerSourceTimeout);
    final raw = resp.data;
    // 兼容两种返回格式：
    // 1. Gitee API：返回 Map，content 字段是 base64 编码的 JSON
    // 2. GitHub raw：返回纯文本 JSON 字符串
    if (raw is Map && raw['content'] != null) {
      final decoded = utf8.decode(base64Decode(raw['content'].toString()));
      return jsonDecode(decoded) as Map<String, dynamic>;
    }
    if (raw is String) {
      return jsonDecode(raw) as Map<String, dynamic>;
    }
    return (raw as Map).cast<String, dynamic>();
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
