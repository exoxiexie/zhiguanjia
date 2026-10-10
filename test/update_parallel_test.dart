/// v1.0.51 更新检查提速：**两源并行 + 单源 7 秒超时 + 主源优先**
///
/// 为什么不是"谁快用谁"：GitHub 只是读源回退、镜像可能滞后于 Gitee，
/// 若谁快用谁，可能读到旧版本号 → 误报「已是最新」。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:zhiguanjia/contracts/update_service.dart';
import 'package:zhiguanjia/features/update/update_service_impl.dart';

const String _gitee = 'https://gitee.com/api/v5/repos/laoxie2076/zhiguanjia/contents';
const String _github = 'https://raw.githubusercontent.com/exoxiexie/zhiguanjia/main';

typedef _Script = Future<ResponseBody> Function(RequestOptions options);

/// 按 URL 关键字匹配脚本的适配器（Dio 只有工厂构造，无法继承 → 注入适配器）
class _Adapter implements HttpClientAdapter {
  _Adapter(this.script);

  final Map<String, _Script> script;
  int calls = 0;
  final List<String> urls = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    calls++;
    urls.add(options.uri.toString());
    for (final MapEntry<String, _Script> e in script.entries) {
      if (options.uri.toString().contains(e.key)) return e.value(options);
    }
    return Future<ResponseBody>.error(
        DioException(requestOptions: options, message: 'no script'));
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _body(String text) => ResponseBody.fromString(text, 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    });

/// Gitee API 格式：content 为 base64 编码的 JSON
_Script _giteeOk(String version, int code, {int delayMs = 0}) => (RequestOptions o) async {
      if (delayMs > 0) await Future<void>.delayed(Duration(milliseconds: delayMs));
      final inner = jsonEncode(<String, dynamic>{
        'versionName': version, 'versionCode': code,
        'url': 'https://gitee.com/x/$version.apk', 'changelog': 'g',
      });
      return _body(jsonEncode(<String, dynamic>{'content': base64Encode(utf8.encode(inner))}));
    };

/// GitHub raw 格式：纯文本 JSON
_Script _rawOk(String version, int code, {int delayMs = 0}) => (RequestOptions o) async {
      if (delayMs > 0) await Future<void>.delayed(Duration(milliseconds: delayMs));
      return _body(jsonEncode(<String, dynamic>{
        'versionName': version, 'versionCode': code,
        'url': 'https://gitee.com/x/$version.apk', 'changelog': 'r',
      }));
    };

_Script _fail() => (RequestOptions o) =>
    Future<ResponseBody>.error(DioException(requestOptions: o, message: 'boom'));

/// 永不返回（模拟链路卡死）
_Script _hang() => (RequestOptions o) => Completer<ResponseBody>().future;

HttpUpdateService _service(_Adapter adapter,
    {List<String>? urls,
    Duration perSource = const Duration(milliseconds: 400),
    Duration total = const Duration(milliseconds: 1500)}) {
  final Dio dio = Dio();
  dio.httpClientAdapter = adapter;
  return HttpUpdateService(
    baseUrls: urls ?? const <String>[_gitee, _github],
    dio: dio,
    perSourceTimeout: perSource,
    totalTimeout: total,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 本机 = 1.0.50 / code 51
    PackageInfo.setMockInitialValues(
      appName: '职管家', packageName: 'com.zhiguanjia.zhiguanjia',
      version: '1.0.50', buildNumber: '51', buildSignature: '',
    );
  });

  test('主源成功 → 采用主源（即使回退源更快、版本更旧）', () async {
    final _Adapter adapter = _Adapter(<String, _Script>{
      'gitee.com': _giteeOk('1.0.51', 52, delayMs: 250), // 主源慢
      'raw.githubusercontent': _rawOk('1.0.49', 50),     // 回退源立刻返回旧版本
    });
    final CheckResult r = await _service(adapter).checkForUpdate();
    expect(r.hasUpdate, isTrue);
    expect(r.latest!.versionCode, 52);
    expect(r.latest!.version, '1.0.51');
  });

  test('两源并发发起（不是依次等待）', () async {
    final _Adapter adapter = _Adapter(<String, _Script>{
      'gitee.com': _giteeOk('1.0.51', 52, delayMs: 200),
      'raw.githubusercontent': _rawOk('1.0.51', 52),
    });
    final Stopwatch sw = Stopwatch()..start();
    await _service(adapter).checkForUpdate();
    sw.stop();
    expect(adapter.calls, 2);
    // 并发时总耗时≈较慢的那个（200ms），而非两者相加
    expect(sw.elapsedMilliseconds, lessThan(1200));
  });

  test('主源失败 → 立即采用已在飞行中的回退源', () async {
    final _Adapter adapter = _Adapter(<String, _Script>{
      'gitee.com': _fail(),
      'raw.githubusercontent': _rawOk('1.0.51', 52, delayMs: 30),
    });
    final Stopwatch sw = Stopwatch()..start();
    final CheckResult r = await _service(adapter).checkForUpdate();
    sw.stop();
    expect(r.hasUpdate, isTrue);
    expect(r.latest!.versionCode, 52);
    expect(sw.elapsedMilliseconds, lessThan(1500));
  });

  test('两源都失败 → 快速返回失败（不再拖到 30 秒）', () async {
    final _Adapter adapter =
        _Adapter(<String, _Script>{'gitee.com': _fail(), 'raw.githubusercontent': _fail()});
    final Stopwatch sw = Stopwatch()..start();
    final CheckResult r = await _service(adapter).checkForUpdate();
    sw.stop();
    expect(r.hasUpdate, isFalse);
    expect(r.message, contains('检查更新失败'));
    expect(sw.elapsedMilliseconds, lessThan(2000));
  });

  test('主源卡死 → 单源超时后仍失败（两轮重试后放弃，不做无休止等待）', () async {
    final _Adapter adapter = _Adapter(<String, _Script>{
      'gitee.com': _hang(),
      'raw.githubusercontent': _fail(),
    });
    final Stopwatch sw = Stopwatch()..start();
    final CheckResult r = await _service(adapter).checkForUpdate();
    sw.stop();
    expect(r.hasUpdate, isFalse);
    // 两轮 × 400ms 单源超时 ≈ 800ms；远小于旧版顺序等待的秒级
    expect(sw.elapsedMilliseconds, greaterThan(700));
    expect(sw.elapsedMilliseconds, lessThan(1500));
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('第 1 轮失败 → 第 2 轮重试成功（慢网络握手未热也能救回来）', () async {
    int attempt = 0;
    final _Adapter adapter = _Adapter(<String, _Script>{
      'gitee.com': (RequestOptions o) async {
        attempt++;
        if (attempt == 1) {
          return Future<ResponseBody>.error(
              DioException(requestOptions: o, message: 'first round failed'));
        }
        return _body(jsonEncode(<String, dynamic>{
          'versionName': '1.0.52', 'versionCode': 53,
          'url': 'https://gitee.com/x/1.0.52.apk', 'changelog': 'retry ok',
        }));
      },
      'raw.githubusercontent': _fail(),
    });
    final CheckResult r = await _service(adapter).checkForUpdate();
    expect(r.hasUpdate, isTrue);
    expect(r.latest!.versionCode, 53);
    expect(attempt, greaterThanOrEqualTo(2)); // 确实重试了
  });

  test('主源卡死 + 回退源可用 → 仍在 7 秒档内拿到结果', () async {
    final _Adapter adapter = _Adapter(<String, _Script>{
      'gitee.com': _hang(),
      'raw.githubusercontent': _rawOk('1.0.51', 52, delayMs: 30),
    });
    final Stopwatch sw = Stopwatch()..start();
    final CheckResult r = await _service(adapter).checkForUpdate();
    sw.stop();
    expect(r.hasUpdate, isTrue);
    expect(sw.elapsedMilliseconds, lessThan(10000));
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('默认超时值按历史证据设定（15 秒 / 30 秒）—— 防再次被调小', () {
    // 智懂你 v1.2.69（提交 2c21bd1a，2026-10-02）曾把 15 秒延长到 30 秒，
    // 原因写明「缓解 Gitee 网络波动导致的检查更新失败」→ 15 秒是被实测判定偏紧的下限。
    // 本实现并行竞速，超时值不影响正常速度，因此没有理由调小。
    expect(HttpUpdateService.defaultPerSourceTimeout, const Duration(seconds: 15));
    expect(HttpUpdateService.defaultTotalTimeout, const Duration(seconds: 30));
  });

  test('未配置更新源 → 明确报失败（不静默当作已是最新）', () async {
    final CheckResult r =
        await _service(_Adapter(<String, _Script>{})).checkForUpdate();
    expect(r.hasUpdate, isFalse);
    expect(r.message, contains('检查更新失败'));
  });
}
