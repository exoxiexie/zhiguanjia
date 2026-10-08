/// Agent · 真流式输出测试（v1.0.33）
///
/// **背景**：懂你页的对话走 Agent 分支。改造前 Agent 的模型请求是**非流式**
/// （不带 `stream: true`），必须等整段回答生成完才返回，再按 3 字符「回放」给界面
/// —— 用户等待期间一个字都看不到，主观上比官方 App 慢很多。
///
/// 改造后每一轮都带 `stream: true`：正文片段到达即通过 onDelta 上屏，
/// 工具调用则在同一流里以分片（index / id / name / arguments）下发，需要拼装。
///
/// 这里用「脚本化的 HTTP 适配器」喂内存 SSE 流来锁住三件事：
/// 1. 正文是**逐片**回调，不是攒完一次性给；
/// 2. 把字节流**故意打碎**（每 7 字节一片）仍能正确解析 —— 不被分片边界影响；
/// 3. 工具循环完好：工具调用分片能拼回完整参数、工具被执行、随后第二轮出正文。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhiguanjia/contracts/agent_service.dart';
import 'package:zhiguanjia/contracts/chat_service.dart';
import 'package:zhiguanjia/features/agent/agent_service_impl.dart';

/// 把一串 SSE 片段编码成字节流，并**故意打碎**成小片，模拟真实网络分包
Stream<Uint8List> _fragmented(List<String> ssePieces, {int chunkSize = 7}) async* {
  final bytes = utf8.encode(ssePieces.join());
  for (var i = 0; i < bytes.length; i += chunkSize) {
    final end = (i + chunkSize > bytes.length) ? bytes.length : i + chunkSize;
    yield Uint8List.fromList(bytes.sublist(i, end));
  }
}

/// 构造一个 SSE 数据行（OpenAI 流式格式）
String _sse(Map<String, dynamic> delta, {Map<String, dynamic>? usage}) =>
    'data: ${jsonEncode({
          'choices': [
            {'index': 0, 'delta': delta, 'finish_reason': null}
          ],
          if (usage != null) 'usage': usage,
        })}\n\n';

/// 正文分片
String _contentSse(String text) => _sse({'content': text});

/// 工具调用分片（index / id / name / arguments 可分别给，模拟真实增量）
String _toolSse({
  required int index,
  String? id,
  String? name,
  String? argsFragment,
}) =>
    _sse({
      'tool_calls': [
        {
          'index': index,
          if (id != null) 'id': id,
          if (id != null) 'type': 'function',
          'function': {
            if (name != null) 'name': name,
            if (argsFragment != null) 'arguments': argsFragment,
          },
        }
      ],
    });

/// 脚本化 HTTP 适配器：按调用次序返回不同的 SSE 脚本，并记录每次请求体。
///
/// 采用注入 `HttpClientAdapter` 的方式（`Dio` 本身只有工厂构造，无法继承）。
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._scripts);

  final List<List<String>> _scripts;
  int callCount = 0;
  final List<Map<String, dynamic>> requestBodies = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (requestStream != null) {
      final bytes = <int>[];
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map) {
        requestBodies.add(Map<String, dynamic>.from(decoded));
      }
    }
    final idx = callCount < _scripts.length ? callCount : _scripts.length - 1;
    callCount++;
    return ResponseBody(
      _fragmented(_scripts[idx]),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 造一个「先要求调 web_search」的 SSE 脚本（参数被切成 4 片下发）
List<String> _toolCallScript() => [
      _toolSse(index: 0, id: 'call_1', name: 'web_search', argsFragment: '{"'),
      _toolSse(index: 0, argsFragment: 'query'),
      _toolSse(index: 0, argsFragment: '":"今天'),
      _toolSse(index: 0, argsFragment: '天气"}'),
      'data: [DONE]\n\n',
    ];

/// 建一个装了脚本适配器的 Dio，返回 (dio, adapter)
(Dio, _ScriptedAdapter) _scriptedDio(List<List<String>> scripts) {
  final dio = Dio();
  final adapter = _ScriptedAdapter(scripts);
  dio.httpClientAdapter = adapter;
  return (dio, adapter);
}

void main() {
  final history = <ChatMessage>[
    const ChatMessage(role: 'user', content: '你好'),
  ];

  group('Agent 真流式：正文逐片上屏', () {
    test('正文片段到达即回调，不攒完再给', () async {
      final (dio, _) = _scriptedDio([
        [
          _contentSse('你'),
          _contentSse('好'),
          _contentSse('，世界'),
          'data: [DONE]\n\n',
        ],
      ]);
      final service = HttpAgentService(dio: dio);
      final deltas = <String>[];

      final result = await service.run(
        history: history,
        tools: const [],
        onDelta: (d, {required bool reasoning}) {
          if (!reasoning) deltas.add(d);
        },
      );

      // 关键：收到 3 次回调（逐片），而不是 1 次性拿到 "你好，世界"
      expect(deltas, ['你', '好', '，世界']);
      expect(result.reply, '你好，世界');
    });

    test('打碎字节流（每 7 字节）不影响解析', () async {
      final (dio, _) = _scriptedDio([
        [
          _contentSse('第一段'),
          _contentSse('第二段'),
          'data: [DONE]\n\n',
        ],
      ]);
      final service = HttpAgentService(dio: dio);
      final deltas = <String>[];

      final result = await service.run(
        history: history,
        tools: const [],
        onDelta: (d, {required bool reasoning}) {
          if (!reasoning) deltas.add(d);
        },
      );

      expect(deltas.length, 2);
      expect(result.reply, '第一段第二段');
    });

    test('请求确实带了 stream: true 与 include_usage', () async {
      final (dio, adapter) = _scriptedDio([
        [_contentSse('好'), 'data: [DONE]\n\n'],
      ]);
      final service = HttpAgentService(dio: dio);

      await service.run(history: history, tools: const []);

      expect(adapter.requestBodies, hasLength(1));
      expect(adapter.requestBodies.first['stream'], isTrue);
      expect(adapter.requestBodies.first['stream_options'], isNotNull);
    });

    test('思考片段只走 reasoning 回调，不进正文', () async {
      final (dio, _) = _scriptedDio([
        [
          _sse({'reasoning_content': '让我想想'}),
          _contentSse('答案'),
          'data: [DONE]\n\n',
        ],
      ]);
      final service = HttpAgentService(dio: dio);
      final reasoningDeltas = <String>[];
      final contentDeltas = <String>[];

      final result = await service.run(
        history: history,
        tools: const [],
        onDelta: (d, {required bool reasoning}) {
          if (reasoning) {
            reasoningDeltas.add(d);
          } else {
            contentDeltas.add(d);
          }
        },
      );

      expect(reasoningDeltas, ['让我想想']);
      expect(contentDeltas, ['答案'], reason: '思考不应混进正文');
      expect(result.reply, '答案');
    });
  });

  group('Agent 真流式：工具循环仍然完好', () {
    test('工具调用分片能拼回完整参数，工具被执行，随后出正文', () async {
      final executed = <Map<String, dynamic>>[];
      final (dio, adapter) = _scriptedDio([
        _toolCallScript(), // 第 1 轮：要求调用 web_search
        [
          _contentSse('今天晴，'),
          _contentSse('20 度。'),
          'data: [DONE]\n\n',
        ], // 第 2 轮：给出最终正文
      ]);
      final service = HttpAgentService(dio: dio);
      final deltas = <String>[];
      final toolStarts = <String>[];

      final tool = ToolDefinition(
        name: 'web_search',
        description: '联网搜索',
        parameters: {
          'type': 'object',
          'properties': {
            'query': {'type': 'string'}
          },
          'required': ['query'],
        },
        execute: (args) async {
          executed.add(args);
          return '搜索结果：今天晴';
        },
      );

      final result = await service.run(
        history: history,
        tools: [tool],
        maxSteps: 5,
        onDelta: (d, {required bool reasoning}) {
          if (!reasoning) deltas.add(d);
        },
        onToolStart: toolStarts.add,
      );

      // 工具被调用一次，且参数由 4 个分片正确拼装
      expect(executed, hasLength(1));
      expect(executed.first['query'], '今天天气');

      // 工具名上报给 UI（用于显示"正在联网搜索…"）
      expect(toolStarts, ['web_search']);

      // 第二轮正文是真流式逐片到达
      expect(deltas, ['今天晴，', '20 度。']);
      expect(result.reply, '今天晴，20 度。');

      // 循环统计：2 轮、1 次工具调用、正常结束
      expect(result.steps, 2);
      expect(result.toolCalls, 1);
      expect(result.finished, isTrue);

      // 第 1 轮带 tools，第 2 轮（未到上限）也带 tools
      expect(adapter.requestBodies[0].containsKey('tools'), isTrue);
      // 工具结果确实回填进了第 2 轮请求
      final secondMessages =
          (adapter.requestBodies[1]['messages'] as List).cast<Map>();
      expect(
        secondMessages.any((m) => m['role'] == 'tool'),
        isTrue,
        reason: '工具执行结果应作为 tool 消息回填给模型',
      );
    });

    test('最后一步不带 tools（强制收口）', () async {
      final (dio, adapter) = _scriptedDio([
        [
          _contentSse('收口答案'),
          'data: [DONE]\n\n',
        ],
      ]);
      final service = HttpAgentService(dio: dio);

      final tool = ToolDefinition(
        name: 'web_search',
        description: '联网搜索',
        parameters: {'type': 'object', 'properties': const {}},
        execute: (args) async => 'ok',
      );

      // maxSteps: 1 → 第一步即最后一步，应不带 tools
      await service.run(
        history: history,
        tools: [tool],
        maxSteps: 1,
      );

      expect(adapter.requestBodies.first.containsKey('tools'), isFalse);
      expect(adapter.requestBodies.first.containsKey('tool_choice'), isFalse);
    });
  });

  group('Agent 真流式：token 统计保留', () {
    test('流式末包带 usage 时能读到用量', () async {
      final (dio, _) = _scriptedDio([
        [
          _contentSse('好'),
          _sse(const {}, usage: {
            'prompt_tokens': 11,
            'completion_tokens': 22,
          }),
          'data: [DONE]\n\n',
        ],
      ]);
      final service = HttpAgentService(dio: dio);

      final result = await service.run(history: history, tools: const []);

      expect(result.stepLogs.first.promptTokens, 11);
      expect(result.stepLogs.first.completionTokens, 22);
    });
  });
}
