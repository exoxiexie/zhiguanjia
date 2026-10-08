/// Agent Harness 实现 · 基于 DeepSeek function calling 的轻量循环调度器
///
/// 核心循环（tool-call loop）：
///   模型调用(带 tools，**真流式**) → 有 tool_calls? → 执行工具 → 结果回填 → 回到模型调用
///   无 tool_calls → 本轮正文即最终回复（已在流式中逐步上屏）
/// 终止条件：maxSteps / timeout / 模型明确结束。
///
/// **每一轮都是真流式**（v1.0.33 核心修复）：
/// 请求带 `stream: true`，正文片段到达即通过 `onDelta` 上屏，用户立刻看到字在冒；
/// 工具调用的分片（index / id / name / arguments）在同一条流里同步累积，
/// 流结束后若有 tool_calls 才进入工具循环。
///
/// 此前是「非流式请求 + 拿到整段后按 3 字符回放」的**假流式**：
/// 用户必须等整段回答生成完才看到第一个字，主观上明显比官方 App 慢。
/// 注意这与「走不走 Agent、要不要组装上下文」无关 —— 上下文组装（_buildMessages）、
/// 工具循环、搜索沉淀全部保留，改动仅在于模型请求的调用姿势。
///
/// 目录隔离：本模块只属于 agent 域，不依赖其他业务模块。
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../contracts/agent_service.dart';
import '../../contracts/api_config.dart';
import '../../contracts/chat_service.dart';
import '../storage/search_data_store.dart';

class HttpAgentService implements AgentService {
  /// 搜索用模型
  static const String _searchModel = 'deepseek-flash';

  final Dio _dio;

  /// 个人职业身份上下文（实名认证后注入每次 Agent 任务）
  String? _personContext;

  /// 当前租户ID（个人手机号），用于搜索数据自动沉淀
  String? _tenantId;

  /// 最近一次搜索的结果（用于自动沉淀时记录信源）
  List<SearchSource>? _lastSearchSources;

  @override
  void setPersonContext(String? contextText) {
    _personContext = contextText;
  }

  @override
  void setTenantId(String? tenantId) {
    _tenantId = tenantId;
  }

  HttpAgentService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 120),
            ));

  // ────────────────────────────────────────────────────────────
  //  Agent 主循环
  // ────────────────────────────────────────────────────────────

  @override
  Future<AgentResult> run({
    required List<ChatMessage> history,
    List<ToolDefinition> tools = const [],
    String model = 'deepseek-flash',
    int maxSteps = 8,
    Duration timeout = const Duration(seconds: 90),
    AgentStreamCallback? onDelta,
    AgentToolStartCallback? onToolStart,
    AgentToolEndCallback? onToolEnd,
  }) async {
    // 把 ChatMessage 列表转成 OpenAI 格式 messages（含附件处理）
    final messages = await _buildMessages(history);
    final stepLogs = <AgentStepLog>[];
    var totalToolCalls = 0;
    var reply = '';
    var finished = false;
    final overall = Stopwatch()..start();

    // ── 搜索状态记录（用于自动沉淀）──
    var usedSearch = false;
    var searchQuery = '';
    final searchSources = <SearchSource>[];
    final fetchedUrls = <String>[];

    for (var step = 1; step <= maxSteps; step++) {
      if (overall.elapsed > timeout) break;
      final stepTimer = Stopwatch()..start();

      // 判断是否为最后一步：无工具可用或已达步数上限时，
      // 不再带工具、直接产出最终回复（避免陷入无尽工具循环）
      final isFinalStep = (step == maxSteps) || tools.isEmpty;

      // ── 每一轮都是「真流式」调用 ──
      // 正文片段到达即上屏（用户立刻看到字往外冒）；工具调用分片同步累积。
      final round = await _streamModelRound(
        messages: messages,
        model: model,
        tools: isFinalStep ? const <ToolDefinition>[] : tools,
        onDelta: onDelta,
      );

      // ── 本轮没有工具调用 → 这就是最终回复（正文已在流式中显示完毕）──
      if (round.toolCalls.isEmpty) {
        final text =
            round.content.isNotEmpty ? round.content : round.reasoning;
        reply = mdToCnText(text);
        finished = true;
        stepLogs.add(AgentStepLog(
          step: step,
          toolCalls: const [],
          finished: true,
          elapsed: stepTimer.elapsed,
          promptTokens: round.promptTokens,
          completionTokens: round.completionTokens,
        ));
        break;
      }

      // ── 有工具调用：assistant 消息入历史，逐个执行工具并回填 ──
      messages.add({
        'role': 'assistant',
        'content': round.content,
        'tool_calls': round.toolCalls,
      });

      final records = <ToolCallRecord>[];
      for (final tc in round.toolCalls) {
        final fn = (tc['function'] as Map?) ?? const {};
        final name = fn['name']?.toString() ?? '';
        final arguments = fn['arguments']?.toString() ?? '{}';
        Map<String, dynamic> args;
        try {
          args = (jsonDecode(arguments) as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
        } catch (_) {
          args = <String, dynamic>{};
        }

        onToolStart?.call(name);
        final result = await _executeTool(tools, name, args);
        onToolEnd?.call(name, result);
        totalToolCalls++;

        // ── 记录搜索状态（用于自动沉淀）──
        if (name == 'web_search') {
          usedSearch = true;
          searchQuery = args['query']?.toString() ?? '';
          if (_lastSearchSources != null) {
            searchSources.addAll(_lastSearchSources!);
          }
        } else if (name == 'web_fetch') {
          final url = args['url']?.toString() ?? '';
          if (url.isNotEmpty && !fetchedUrls.contains(url)) {
            fetchedUrls.add(url);
          }
        }

        messages.add({
          'role': 'tool',
          'tool_call_id': tc['id']?.toString() ?? '',
          'content': result,
        });
        records.add(ToolCallRecord(
          id: tc['id']?.toString() ?? '',
          name: name,
          args: args,
          result: result,
        ));
      }

      stepLogs.add(AgentStepLog(
        step: step,
        toolCalls: records,
        finished: false,
        elapsed: stepTimer.elapsed,
        promptTokens: round.promptTokens,
        completionTokens: round.completionTokens,
      ));
    }

    // ── 联网搜索自动沉淀：本次调用了搜索工具且有租户ID时，异步沉淀模型回复 ──
    if (usedSearch &&
        _tenantId != null &&
        _tenantId!.isNotEmpty &&
        reply.isNotEmpty) {
      print(
          '[搜索沉淀] 触发沉淀: usedSearch=$usedSearch, tenantId=$_tenantId, reply长度=${reply.length}, 搜索结果=${searchSources.length}, 读取网页=${fetchedUrls.length}');
      final title = searchQuery.length > 30
          ? '${searchQuery.substring(0, 30)}...'
          : (searchQuery.isEmpty ? '联网搜索' : searchQuery);

      // 合并信源列表：搜索结果 + 实际读取的网页URL（去重）
      final allSources = <SearchSource>[...searchSources];
      final seenUrls = searchSources.map((s) => s.url).toSet();
      for (final url in fetchedUrls) {
        if (!seenUrls.contains(url)) {
          allSources.add(SearchSource(title: url, url: url));
          seenUrls.add(url);
        }
      }

      // 异步执行，不 await，不阻塞返回
      () async {
        try {
          final created = await SearchDataStore.create(
            tenantId: _tenantId!,
            title: title,
            searchQuery: searchQuery,
            content: reply,
            sources: allSources,
          );
          print(
              '[搜索沉淀] 沉淀成功: id=${created.id}, title=${created.title}, 信源数=${created.sources.length}');
        } catch (e, stackTrace) {
          print('[搜索沉淀] 沉淀失败: $e');
          print('[搜索沉淀] 堆栈: $stackTrace');
        }
      }();
    } else {
      print(
          '[搜索沉淀] 未触发沉淀: usedSearch=$usedSearch, tenantId=${_tenantId ?? "null"}, reply长度=${reply.length}');
    }

    return AgentResult(
      reply: reply,
      steps: stepLogs.length,
      toolCalls: totalToolCalls,
      stepLogs: stepLogs,
      finished: finished,
    );
  }

  // ────────────────────────────────────────────────────────────
  //  一轮真流式模型调用（正文边到边回调，工具调用分片同步累积）
  // ────────────────────────────────────────────────────────────

  /// 发起一轮带 `stream: true` 的模型调用。
  ///
  /// - 正文（`content`）与思考（`reasoning_content`）片段**到达即**通过
  ///   [onDelta] 回调给 UI —— 这是「首字立刻可见」的关键；
  /// - 同时按 `index` 累积 `tool_calls` 分片：`id` 只在首片出现，
  ///   `function.name` 通常首片给全，`function.arguments` 为逐片增量，需拼接。
  ///
  /// 返回本轮完整结果，由调用方判断「继续工具循环」还是「这就是最终回复」。
  Future<_StreamRound> _streamModelRound({
    required List<Map<String, dynamic>> messages,
    required String model,
    required List<ToolDefinition> tools,
    AgentStreamCallback? onDelta,
  }) async {
    final resp = await _dio.post<ResponseBody>(
      ApiConfig.chatCompletionsUrl,
      data: {
        'model': model,
        'messages': messages,
        if (tools.isNotEmpty) 'tools': tools.map(_toToolSchema).toList(),
        if (tools.isNotEmpty) 'tool_choice': 'auto',
        'max_tokens': 24576,
        'stream': true,
        // 让流式响应末包带上 usage，保留 token 统计（实测代理支持）
        'stream_options': const {'include_usage': true},
      },
      options: Options(
        responseType: ResponseType.stream,
        headers: {
          'X-Proxy-Token': ApiConfig.proxyToken,
          'Content-Type': 'application/json',
        },
      ),
    );
    final body = resp.data;
    if (body == null) throw Exception('模型未返回内容');

    final reasoningBuf = StringBuffer();
    final contentBuf = StringBuffer();
    // 工具调用分片累积：index -> {id, type, function:{name, arguments}}
    final toolAcc = <int, Map<String, dynamic>>{};
    var promptTokens = 0;
    var completionTokens = 0;

    await for (final raw
        in utf8.decoder.bind(body.stream).transform(const LineSplitter())) {
      final line = raw.trim();
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data == '[DONE]') break;
      Map<String, dynamic> json;
      try {
        json = jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      // usage 常在最后一个 chunk 单独下发
      final usage = json['usage'] as Map?;
      if (usage != null) {
        promptTokens = (usage['prompt_tokens'] as num?)?.toInt() ?? promptTokens;
        completionTokens =
            (usage['completion_tokens'] as num?)?.toInt() ?? completionTokens;
      }

      final choices = json['choices'] as List?;
      if (choices == null || choices.isEmpty) continue;
      final delta = (choices[0] as Map)['delta'] as Map?;
      if (delta == null) continue;

      final reasoning = delta['reasoning_content']?.toString() ?? '';
      final content = delta['content']?.toString() ?? '';
      if (reasoning.isNotEmpty) {
        reasoningBuf.write(reasoning);
        onDelta?.call(reasoning, reasoning: true);
      }
      if (content.isNotEmpty) {
        contentBuf.write(content);
        // ★ 真流式：正文片段一到就上屏，不再等整段生成完
        onDelta?.call(content, reasoning: false);
      }

      // ── 工具调用分片累积（流式下 tool_calls 是逐步下发的）──
      final tcList = delta['tool_calls'] as List?;
      if (tcList != null) {
        for (final rawTc in tcList) {
          if (rawTc is! Map) continue;
          final idx = (rawTc['index'] as num?)?.toInt() ?? 0;
          final acc = toolAcc.putIfAbsent(
            idx,
            () => <String, dynamic>{
              'id': '',
              'type': 'function',
              'function': <String, dynamic>{'name': '', 'arguments': ''},
            },
          );
          if (rawTc['id'] != null) acc['id'] = rawTc['id'].toString();
          if (rawTc['type'] != null) acc['type'] = rawTc['type'].toString();
          final fn = rawTc['function'] as Map?;
          if (fn != null) {
            final accFn = acc['function'] as Map<String, dynamic>;
            if (fn['name'] != null) accFn['name'] = fn['name'].toString();
            if (fn['arguments'] != null) {
              // arguments 是增量片段，必须拼接
              accFn['arguments'] = '${accFn['arguments']}${fn['arguments']}';
            }
          }
        }
      }
    }

    final indices = toolAcc.keys.toList()..sort();
    return _StreamRound(
      content: contentBuf.toString(),
      reasoning: reasoningBuf.toString(),
      toolCalls: <Map<String, dynamic>>[
        for (final i in indices) toolAcc[i]!,
      ],
      promptTokens: promptTokens,
      completionTokens: completionTokens,
    );
  }

  // ────────────────────────────────────────────────────────────
  //  ChatMessage → OpenAI 格式 messages（含附件处理）
  // ────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _buildMessages(
      List<ChatMessage> history) async {
    final messages = <Map<String, dynamic>>[];
    // ── 个人职业身份上下文：实名认证后注入 ──
    if (_personContext != null && _personContext!.isNotEmpty) {
      messages.add({
        'role': 'system',
        'content': '【当前服务个人职业身份档案】\n'
            '$_personContext\n\n'
            '请在完成任务时，结合以上个人职业身份画像给出针对性的职业建议和分析。'
            '如果任务与其职业发展相关，请优先结合以上画像处理。',
      });
    }
    for (var i = 0; i < history.length; i++) {
      final m = history[i];
      final att = m.attachment;

      if (m.role == 'user' && att != null) {
        // 文档附件：文本注入 system 上下文
        if (att.type == ChatAttachmentType.document &&
            att.text != null &&
            att.text!.isNotEmpty) {
          messages.add({
            'role': 'system',
            'content': '用户上传了文档「${att.name}」，请基于文档内容回答用户问题，'
                '不要编造文档之外的事实。回答请使用中文。\n\n【文档内容】\n${att.text}',
          });
          messages.add({'role': 'user', 'content': m.content});
          continue;
        }
        // 图片附件：转 data URL 多模态
        if (att.type == ChatAttachmentType.image && att.filePath != null) {
          final bytes = await File(att.filePath!).readAsBytes();
          final b64 = base64Encode(bytes);
          messages.add({
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': m.content.isEmpty ? '请帮我分析这张图片。' : m.content,
              },
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:${_mimeFor(att.filePath!)};base64,$b64',
                },
              },
            ],
          });
          continue;
        }
      }

      messages.add({'role': m.role, 'content': m.content});
    }
    return messages;
  }

  String _mimeFor(String filePath) {
    final ext = filePath.toLowerCase().split('.').last;
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  // ────────────────────────────────────────────────────────────
  //  工具执行
  // ────────────────────────────────────────────────────────────

  Future<String> _executeTool(
    List<ToolDefinition> tools,
    String name,
    Map<String, dynamic> args,
  ) async {
    for (final t in tools) {
      if (t.name == name) {
        try {
          return await t.execute(args);
        } catch (e) {
          return '工具执行失败：$e';
        }
      }
    }
    return '错误：未找到工具 "$name"';
  }

  Map<String, dynamic> _toToolSchema(ToolDefinition t) => {
        'type': 'function',
        'function': {
          'name': t.name,
          'description': t.description,
          'parameters': t.parameters,
        },
      };

  // ────────────────────────────────────────────────────────────
  //  联网搜索（DeepSeek Anthropic 兼容端点 + web_search 服务器工具）
  // ────────────────────────────────────────────────────────────

  /// 执行一次联网搜索，返回去重后的来源列表。
  Future<List<SearchSource>> searchWeb(String query) async {
    final resp = await _dio.post(
      ApiConfig.anthropicMessagesUrl,
      data: {
        'model': _searchModel,
        'max_tokens': 24576,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': 'Perform a web search for the query: $query'
              },
            ],
          },
        ],
        'tools': [
          {'type': 'web_search_20250305', 'name': 'web_search', 'max_uses': 5},
        ],
      },
      options: Options(headers: {
        'X-Proxy-Token': ApiConfig.proxyToken,
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      }),
    );
    final blocks = resp.data?['content'] as List? ?? [];
    final sources = <SearchSource>[];
    final seen = <String>{};
    for (final b in blocks) {
      if (b is Map && b['type'] == 'web_search_tool_result') {
        final items = b['content'] as List? ?? [];
        for (final it in items) {
          if (it is Map) {
            final url = it['url']?.toString() ?? '';
            if (url.isEmpty || seen.contains(url)) continue;
            seen.add(url);
            final title = it['title']?.toString() ?? url;
            sources.add(SearchSource(title: title, url: url));
          }
        }
      }
    }

    // 保存最近一次搜索结果，供 Agent 循环结束后自动沉淀使用
    _lastSearchSources = sources;

    return sources;
  }

  // ────────────────────────────────────────────────────────────
  //  网页正文读取（web_fetch）
  // ────────────────────────────────────────────────────────────

  /// 读取指定 URL 的网页正文，清洗 HTML 后返回纯文本。
  ///
  /// - 去除 <script>、<style>、<nav>、<footer>、<header> 等无关标签
  /// - 去除所有 HTML 标签，保留纯文本
  /// - 压缩多余空白
  /// - 截断到 maxLength 字符（默认 4000）
  Future<String> fetchWebPage(String url, {int maxLength = 4000}) async {
    try {
      final resp = await _dio.get<String>(
        url,
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Accept': 'text/html,application/xhtml+xml',
            'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
          },
          responseType: ResponseType.plain,
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      var html = resp.data ?? '';
      if (html.isEmpty) return '网页内容为空。';

      // 1. 去除 script、style、nav、footer、header、aside 等无关标签及内容
      html = html.replaceAll(
          RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '');
      html = html.replaceAll(
          RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '');
      html = html.replaceAll(
          RegExp(r'<nav[\s\S]*?</nav>', caseSensitive: false), '');
      html = html.replaceAll(
          RegExp(r'<footer[\s\S]*?</footer>', caseSensitive: false), '');
      html = html.replaceAll(
          RegExp(r'<header[\s\S]*?</header>', caseSensitive: false), '');
      html = html.replaceAll(
          RegExp(r'<aside[\s\S]*?</aside>', caseSensitive: false), '');
      html = html.replaceAll(
          RegExp(r'<noscript[\s\S]*?</noscript>', caseSensitive: false), '');

      // 2. 将块级标签替换为换行
      html = html.replaceAll(
          RegExp(r'</(p|div|br|li|h1|h2|h3|h4|h5|h6|tr)>',
              caseSensitive: false),
          '\n');

      // 3. 去除所有剩余 HTML 标签
      html = html.replaceAll(RegExp(r'<[^>]+>'), '');

      // 4. HTML 实体解码
      html = html
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll('&#39;', "'")
          .replaceAll(RegExp(r'&#\d+;'), '');

      // 5. 压缩多余空白行和空格
      final lines =
          html.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
      var text = lines.join('\n');
      text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
      text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');

      // 6. 截断
      if (text.length > maxLength) {
        text = '${text.substring(0, maxLength)}\n\n（内容过长，已截断）';
      }

      return text.isEmpty ? '未能提取到网页正文内容。' : text;
    } catch (e) {
      return '网页读取失败：$e';
    }
  }
}

/// 一轮流式模型调用的完整结果（v1.0.33）
///
/// [content] / [reasoning] 为本轮累积到的正文与思考文本；
/// [toolCalls] 为按 `index` 拼装好的完整工具调用（OpenAI 格式，可直接回填进 messages），
/// 为空表示本轮即最终回复。
class _StreamRound {
  final String content;
  final String reasoning;
  final List<Map<String, dynamic>> toolCalls;
  final int promptTokens;
  final int completionTokens;

  const _StreamRound({
    required this.content,
    required this.reasoning,
    required this.toolCalls,
    required this.promptTokens,
    required this.completionTokens,
  });
}

/// 内置联网搜索工具定义（供 AgentService.run 注册使用）
ToolDefinition buildWebSearchTool(HttpAgentService service) => ToolDefinition(
      name: 'web_search',
      description: '当用户问题需要实时、最新的信息时使用，例如新闻、天气、股价、'
          '最新事件、近期动态等。返回搜索结果的标题和链接，供模型基于搜索结果回答。',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': '搜索关键词，应简洁准确，例如"2026年AI最新新闻"',
          },
        },
        'required': ['query'],
      },
      execute: (args) async {
        final query = args['query']?.toString() ?? '';
        if (query.isEmpty) return '搜索关键词为空。';
        final sources = await service.searchWeb(query);
        if (sources.isEmpty) return '未找到相关搜索结果。';
        final buf = StringBuffer('搜索结果（共${sources.length}条）：\n');
        for (var i = 0; i < sources.length; i++) {
          buf.writeln('${i + 1}. ${sources[i].title}');
          buf.writeln('   ${sources[i].url}');
        }
        buf.writeln('\n请基于以上搜索结果回答用户问题，在回复末尾以"参考资料："列出主要来源。');
        return buf.toString();
      },
    );

/// 内置网页正文读取工具定义（供 AgentService.run 注册使用）
ToolDefinition buildWebFetchTool(HttpAgentService service) => ToolDefinition(
      name: 'web_fetch',
      description: '当需要读取某个具体网页的详细内容时使用。搜索得到链接后，'
          '可以调用本工具读取网页正文，获取更详细的信息来回答用户问题。'
          '每次只读取一个网页，建议选择最相关的3-5个网页读取。',
      parameters: {
        'type': 'object',
        'properties': {
          'url': {
            'type': 'string',
            'description': '要读取的网页URL，必须是完整的http/https链接',
          },
        },
        'required': ['url'],
      },
      execute: (args) async {
        final url = args['url']?.toString() ?? '';
        if (url.isEmpty) return 'URL为空。';
        if (!url.startsWith('http://') && !url.startsWith('https://')) {
          return 'URL格式不正确，必须以http://或https://开头。';
        }
        final content = await service.fetchWebPage(url);
        return '网页正文内容：\n$content';
      },
    );
