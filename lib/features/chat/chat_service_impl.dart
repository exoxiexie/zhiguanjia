/// 对话模块 · DeepSeek 实现（App 直连 DeepSeek 公网 API）
///
/// 【开发版】API Key 直接内置在 App 中，方便任何网络环境下使用；
/// 正式生产版会重构为服务端代理，届时仅需替换本实现，UI 与契约不变。
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../contracts/api_config.dart';
import '../../contracts/chat_service.dart';
import '../storage/search_data_store.dart';

/// 直接调用 DeepSeek 公网 API 的对话服务实现。
///
/// 请求链路：App → 服务端代理（阿里云函数计算）→ DeepSeek，
/// 真实 API Key 仅存于服务端环境变量，App 端只持代理令牌。
class HttpChatService implements ChatService {
  /// 搜索用模型
  static const String _searchModel = 'deepseek-flash';

  /// 网页抓取请求头（模拟移动端浏览器，降低被站点拒绝概率）
  static const String _fetchUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

  /// 网页正文截断上限（字符数，控制注入 token 量）
  static const int _maxFetchChars = 6000;

  final Dio _dio;

  /// 个人职业身份上下文（实名认证后注入每次对话）
  String? _personContext;

  /// 当前租户ID（个人手机号），用于搜索数据自动沉淀
  String? _tenantId;

  @override
  void setPersonContext(String? contextText) {
    _personContext = contextText;
  }

  @override
  void setTenantId(String? tenantId) {
    _tenantId = tenantId;
  }

  HttpChatService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 120),
            ));

  @override
  Future<String> sendMessage(
    List<ChatMessage> history, {
    String model = 'deepseek-flash',
    bool search = false,
    String? systemExtra,
    ChatStreamCallback? onDelta,
  }) async {
    try {
      // ── 身份问题后台拦截：检测到用户问身份时，直接返回标准答案，不走模型 ──
      // 这样可以100%确保身份回答的准确性和一致性，不受模型幻觉影响
      // 【例外】业务智能体场景（带 systemExtra 角色提示词）不拦截：
      // 该场景下"你是谁"应由模型基于智能体角色提示词回答（如"我是你的税务智能体…"）
      if (history.isNotEmpty &&
          history.last.role == 'user' &&
          (systemExtra == null || systemExtra.isEmpty)) {
        final userMsg = history.last.content.toLowerCase();
        if (_isIdentityQuestion(userMsg)) {
          const answer = '我是职管家 AI 职业管家，致力于为你提供职业规划、求职发展、技能成长等全职业生涯的智能服务。';
          // 模拟流式输出，逐字推送，保持与模型回答一致的体验
          for (var i = 0; i < answer.length; i++) {
            onDelta?.call(answer[i], reasoning: false);
            await Future.delayed(const Duration(milliseconds: 20));
          }
          return answer;
        }
      }

      // ── 网页深读：用户消息含 URL 时自动抓取正文（优先级最高）──
      String? fetchedUrl;
      String? fetchedText;
      if (history.isNotEmpty && history.last.role == 'user') {
        final url = _firstUrlIn(history.last.content);
        if (url != null) {
          try {
            fetchedText = await _fetchWebContent(url);
            fetchedUrl = url;
          } catch (_) {
            // 网页抓取失败不阻塞对话，回退普通回答
            fetchedUrl = null;
            fetchedText = null;
          }
        }
      }

      // ── 联网搜索：无网页深读且开启搜索时执行 web_search ──
      List<SearchSource> sources = const [];
      if (fetchedText == null &&
          search &&
          history.isNotEmpty &&
          history.last.role == 'user') {
        try {
          sources = await _searchWeb(history.last.content);
        } catch (_) {
          // 搜索失败不阻塞对话，回退为普通回答
          sources = const [];
        }
      }

      // ── 组装主对话消息 ──
      final messages = <Map<String, dynamic>>[];
      // 全局 system prompt：明确模型身份，减少身份幻觉
      // 模型无关设计：不硬编码具体厂商，未来可接入任意模型
      // 【最高优先级指令】身份设定必须严格遵守，模型不得自行编造身份
      messages.add({
        'role': 'system',
        'content': '【最高优先级·身份设定·必须严格遵守】\n'
            '你是「职管家」AI 职业管家，一款面向个人用户、陪伴全职业生涯的人工智能管家，'
            '提供职业规划、简历优化、求职面试、技能成长、薪酬谈判、职场法律、职业健康等服务。\n'
            '你的身份就是「职管家 AI 职业管家」，除此之外没有其他身份。\n\n'
            '【严格禁止】\n'
            '1. 绝对不要声称自己是 DeepSeek、深度求索、Claude、Anthropic、GPT、OpenAI、Gemini、Google 等任何其他公司或模型的产品\n'
            '2. 绝对不要提到任何具体的模型厂商、模型名称、版本号或公司名称\n'
            '3. 绝对不要说"我是一款大语言模型"、"我是由XX公司开发的"这类暴露底层模型身份的话\n\n'
            '【当用户询问你的身份时，必须且只能这样回答】\n'
            '"我是职管家 AI 职业管家，致力于为你提供职业规划、求职发展、技能成长等全职业生涯的智能服务。"\n\n'
            '其他要求：请始终用中文回答，保持专业、准确、诚实。具体使用的底层模型由系统后台配置和管理，你不需要关心也不需要透露。',
      });
      // ── 个人职业身份上下文：实名认证后注入，让 AI 知道当前服务的个人主体 ──
      if (_personContext != null && _personContext!.isNotEmpty) {
        messages.add({
          'role': 'system',
          'content': '【当前服务个人职业身份档案】\n'
              '$_personContext\n\n'
              '请在回答用户问题时，结合以上个人职业身份画像给出针对性的职业建议和分析。'
              '如果用户的问题与其职业发展相关，请优先结合以上画像回答。',
        });
      }
      // ── 任务智能体追加上下文（任务域沉淀数据） ──
      if (systemExtra != null && systemExtra.isNotEmpty) {
        messages.add({
          'role': 'system',
          'content': systemExtra,
        });
      }
      if (fetchedText != null && fetchedUrl != null) {
        // 网页正文作为 system 上下文注入，保留完整对话历史
        messages.add({
          'role': 'system',
          'content': '以下是用户提供的网页正文，请优先基于正文回答用户问题，'
              '不要编造正文之外的事实。回答请使用中文，并在末尾以“来源：”注明该网页链接。\n\n'
              '【网页链接】$fetchedUrl\n\n【网页正文】\n$fetchedText',
        });
      } else if (sources.isNotEmpty) {
        // 搜索结果作为 system 上下文注入，保留完整对话历史
        final searchContext = StringBuffer('以下是针对用户问题的联网搜索结果，请优先基于这些信息回答：\n');
        for (var i = 0; i < sources.length; i++) {
          searchContext.writeln('${i + 1}. ${sources[i].title}');
          searchContext.writeln('   ${sources[i].url}');
        }
        searchContext.writeln('回答请使用中文，并在末尾以“参考资料：”列出主要来源。');
        messages.add({'role': 'system', 'content': searchContext.toString()});
      }
      messages.addAll(
          history.map((m) => {'role': m.role, 'content': m.content}).toList());
      // ── 附件处理 ──
      if (history.isNotEmpty) {
        final last = history.last;
        final att = last.attachment;
        // 文档附件：把解析出的文本注入 system 上下文（模型基于文档内容回答）
        if (last.role == 'user' &&
            att != null &&
            att.type == ChatAttachmentType.document &&
            att.text != null &&
            att.text!.isNotEmpty) {
          messages.add({
            'role': 'system',
            'content': '用户上传了文档「${att.name}」，请基于文档内容回答用户问题，'
                '不要编造文档之外的事实。回答请使用中文。\n\n【文档内容】\n${att.text}',
          });
        }
        // 图片附件：最后一条用户消息转为多模态 content 数组
        if (last.role == 'user' &&
            att != null &&
            att.type == ChatAttachmentType.image &&
            att.filePath != null) {
          final bytes = await File(att.filePath!).readAsBytes();
          final b64 = base64Encode(bytes);
          messages.removeLast();
          messages.add({
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': last.content.isEmpty ? '请帮我分析这张图片。' : last.content,
              },
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:${_mimeFor(att.filePath!)};base64,$b64',
                },
              },
            ],
          });
        }
      }

      final resp = await _dio.post<ResponseBody>(
        ApiConfig.chatCompletionsUrl,
        data: {
          'model': model,
          'messages': messages,
          'max_tokens': 1024,
          'stream': true,
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
      if (body == null) {
        throw Exception('模型未返回内容');
      }
      // 逐段解析 SSE 流：思考段(reasoning_content)与正文段(content)分开回调
      final reasoningBuf = StringBuffer();
      final contentBuf = StringBuffer();
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
          onDelta?.call(content, reasoning: false);
        }
      }
      final reply = contentBuf.isNotEmpty
          ? contentBuf.toString()
          : reasoningBuf.toString();
      if (reply.trim().isEmpty) {
        throw Exception('模型未返回内容');
      }

      var result = mdToCnText(reply);
      // ── 网页深读：末尾附来源（兜底，模型可能未列出）──
      if (fetchedText != null &&
          fetchedUrl != null &&
          !result.contains('来源') &&
          !result.contains('参考资料')) {
        result = '$result\n\n—— 参考网页 ——\n$fetchedUrl';
      }
      // ── 联网搜索：在回复末尾附上参考资料（兜底，模型可能未列出）──
      if (sources.isNotEmpty && !result.contains('参考资料')) {
        final buf = StringBuffer(result);
        buf.write('\n\n—— 参考资料 ——\n');
        for (var i = 0; i < sources.length; i++) {
          buf.writeln('${i + 1}. ${sources[i].title}（${sources[i].url}）');
        }
        result = buf.toString().trim();
      }

      // ── 联网搜索自动沉淀：搜索成功且有租户ID时，异步沉淀搜索数据，不阻塞回复 ──
      if (sources.isNotEmpty && _tenantId != null && _tenantId!.isNotEmpty) {
        final query = history.isNotEmpty ? history.last.content : '';
        final title =
            query.length > 30 ? '${query.substring(0, 30)}...' : query;
        // 沉淀内容 = 输入模型的搜索提炼上下文（格式化的搜索结果）
        final contentBuf = StringBuffer('# 搜索提炼内容\n\n');
        contentBuf.writeln('本次搜索共找到 ${sources.length} 条相关信息，整理如下：\n');
        for (var i = 0; i < sources.length; i++) {
          contentBuf.writeln('## ${i + 1}. ${sources[i].title}');
          contentBuf.writeln('- 链接：${sources[i].url}');
          contentBuf.writeln('');
        }
        // 异步执行，不 await，不阻塞对话回复
        () async {
          try {
            await SearchDataStore.create(
              tenantId: _tenantId!,
              title: title.isEmpty ? '联网搜索' : title,
              searchQuery: query,
              content: contentBuf.toString(),
              sources: sources,
            );
          } catch (e) {
            debugPrint('搜索数据自动沉淀失败: $e');
          }
        }();
      }

      return result;
    } on DioException catch (e) {
      throw Exception('网络错误：${e.message}');
    }
  }

  /// 根据图片文件扩展名推断 MIME 类型（用于 data URL）
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

  /// 提取文本中第一个 http(s) 链接；无则返回 null。
  String? _firstUrlIn(String text) {
    final m = RegExp(r'https?://[^\s\u4e00-\u9fff，。；！？、\u0022\u0027()\[\]{}]+')
        .firstMatch(text);
    return m?.group(0);
  }

  /// 抓取网页正文（模拟浏览器请求 → 提取纯文本 → 截断）。
  /// 抓取失败或无内容时抛异常，由调用方降级。
  Future<String> _fetchWebContent(String url) async {
    final resp = await _dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'User-Agent': _fetchUserAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        },
        validateStatus: (code) => code != null && code < 400,
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    final text = _htmlToText(resp.data ?? '');
    if (text.isEmpty) {
      throw Exception('网页内容为空');
    }
    return text.length <= _maxFetchChars
        ? text
        : text.substring(0, _maxFetchChars);
  }

  /// 把 HTML 转成适合喂给模型的纯文本
  /// （去 script/style 等整块内容、去标签、实体解码、压缩空白）。
  String _htmlToText(String html) {
    var s = html;
    // 去掉 script/style/noscript/svg/iframe/template 整块内容
    s = s.replaceAll(
        RegExp(r'<(script|style|noscript|svg|iframe|template)[^>]*>.*?</\1>',
            caseSensitive: false, dotAll: true),
        ' ');
    // 去掉注释
    s = s.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ');
    // 去掉所有标签
    s = s.replaceAll(RegExp(r'<[^>]+>', dotAll: true), ' ');
    // 常见实体解码
    s = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    // 数字实体解码
    s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      return (code != null && code > 0) ? String.fromCharCode(code) : '';
    });
    // 压缩空白与空行
    s = s.replaceAll(RegExp(r'[ \t\r\f\v]+'), ' ');
    s = s.replaceAll(RegExp(r'\n\s*\n+'), '\n');
    return s.trim();
  }

  /// 执行一次联网搜索（DeepSeek Anthropic 兼容端点 + web_search 服务器工具）。
  /// 返回去重后的来源列表；模型判断无需搜索时返回空列表。
  Future<List<SearchSource>> _searchWeb(String query) async {
    final resp = await _dio.post(
      ApiConfig.anthropicMessagesUrl,
      data: {
        'model': _searchModel,
        'max_tokens': 2048,
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
    return sources;
  }

  /// 检测用户消息是否为身份类问题（你是谁、介绍自己、什么模型等）
  ///
  /// 命中时由后台直接返回标准答案，不走模型，确保身份回答100%准确一致。
  bool _isIdentityQuestion(String msg) {
    // 去除空白和标点，简化匹配
    final cleaned = msg.replaceAll(RegExp(r'[\s，。？！、,.!?\n]'), '');
    const keywords = [
      '你是谁',
      '你叫什么',
      '你叫啥',
      '你是什么',
      '介绍一下你自己',
      '介绍你自己',
      '自我介绍',
      '说说你自己',
      '你的身份',
      '你是哪个',
      '你是啥',
      '你是什么模型',
      '你用的什么模型',
      '你基于什么模型',
      '什么大模型',
      '你是哪个公司的',
      '你是哪家公司',
      '哪个公司开发',
      '谁开发的你',
      '你的版本',
      '版本号',
      '你是ai吗',
      '你是人工智能吗',
      '你是助手吗',
      '你是管家吗',
      '职管家',
    ];
    return keywords.any((k) => cleaned.contains(k));
  }
}
