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

HttpUpdateService _service(_Adapter adapter, {List<String>? urls}) {
  final Dio dio = Dio();
  dio.httpClientAdapter = adapter;
  return HttpUpdateService(
      baseUrls: urls ?? const <String>[_gitee, _github], dio: dio);
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

  test('主源卡死 → 单源 7 秒超时后回退（原为 30 秒）', () async {
    final _Adapter adapter = _Adapter(<String, _Script>{
      'gitee.com': _hang(),
      'raw.githubusercontent': _fail(),
    });
    final Stopwatch sw = Stopwatch()..start();
    final CheckResult r = await _service(adapter).checkForUpdate();
    sw.stop();
    expect(r.hasUpdate, isFalse);
    expect(sw.elapsedMilliseconds, greaterThan(6000)); // 等满了单源超时
    expect(sw.elapsedMilliseconds, lessThan(10000));   // 但远小于原来的 30 秒
  }, timeout: const Timeout(Duration(seconds: 40)));

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

  test('未配置更新源 → 明确报失败（不静默当作已是最新）', () async {
    final CheckResult r =
        await _service(_Adapter(<String, _Script>{})).checkForUpdate();
    expect(r.hasUpdate, isFalse);
    expect(r.message, contains('检查更新失败'));
  });
}
