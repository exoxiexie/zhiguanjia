/// 契约层：对话服务接口。
///
/// 【铁律1 前端驱动后端】UI 层只依赖本接口编程，不接触任何网络实现。
/// 当前 MVP 由 HttpChatService（App 直连 DeepSeek）满足该接口，
/// 后续替换为真实后端 API 时，UI 无需任何改动。
library;

/// 一条聊天消息
class ChatMessage {
  /// 角色：'user'（用户）或 'assistant'（AI）
  final String role;

  /// 消息正文
  final String content;

  /// 可选附件（图片或文档），仅用户消息可携带
  final ChatAttachment? attachment;

  const ChatMessage({
    required this.role,
    required this.content,
    this.attachment,
  });
}

/// 附件类型
enum ChatAttachmentType {
  /// 图片（走多模态模型直接识别）
  image,

  /// 文档（PDF / Word / 文本，App 端提取文本后注入上下文）
  document,
}

/// 聊天附件（图片或文档）
class ChatAttachment {
  /// 附件类型
  final ChatAttachmentType type;

  /// 文件名 / 显示名
  final String name;

  /// 本地文件路径（图片必填，发送时读取并编码）
  final String? filePath;

  /// 文档已提取的文本内容（文档解析后填充）
  final String? text;

  const ChatAttachment({
    required this.type,
    required this.name,
    this.filePath,
    this.text,
  });

  /// 是否已解析出可用内容（图片始终可发送；文档需有 text）
  bool get isReady =>
      type == ChatAttachmentType.image || (text != null && text!.isNotEmpty);

  ChatAttachment copyWith({String? text}) => ChatAttachment(
        type: type,
        name: name,
        filePath: filePath,
        text: text ?? this.text,
      );
}

/// 可选对话模型
class ChatModel {
  /// DeepSeek API 模型 id
  final String id;

  /// 界面展示名称
  final String label;

  const ChatModel({required this.id, required this.label});
}

/// 当前支持的模型列表
const List<ChatModel> kChatModels = [
  ChatModel(id: 'deepseek-flash', label: 'DeepSeek V4.1 Flash'),
];

/// 一条联网搜索来源
class SearchSource {
  /// 来源标题
  final String title;

  /// 来源网址
  final String url;

  const SearchSource({required this.title, required this.url});
}

/// 中文序号（一到三十），用于把有序列表 "1. " 转成 "一、 "
const List<String> _cnNums = [
  '一',
  '二',
  '三',
  '四',
  '五',
  '六',
  '七',
  '八',
  '九',
  '十',
  '十一',
  '十二',
  '十三',
  '十四',
  '十五',
  '十六',
  '十七',
  '十八',
  '十九',
  '二十',
  '二十一',
  '二十二',
  '二十三',
  '二十四',
  '二十五',
  '二十六',
  '二十七',
  '二十八',
  '二十九',
  '三十',
];

/// 把模型输出的 Markdown 转成符合中文阅读习惯的纯文本：
/// - 去掉 # / * / ` / > 等 Markdown 标记
/// - 有序列表 "1. 2." → "一、 二、"
/// - 无序列表 "- *" → "·"
/// - 链接 [文字](url) → 文字
/// 供 UI 流式展示与实现层共用。
String mdToCnText(String text) {
  final lines = text.split('\n');
  final out = <String>[];
  for (final raw in lines) {
    var line = raw;
    // 跳过代码块围栏 ``` / ~~~
    if (RegExp(r'^\s*(```+|~~~+)').hasMatch(line)) continue;
    // 去掉引用标记 "> "
    line = line.replaceFirst(RegExp(r'^\s*>\s?'), '');
    // 去掉标题标记 "#### " / "### " / ...
    line = line.replaceFirst(RegExp(r'^\s*#{1,6}\s*'), '');
    // 有序列表 "1. " / "1、 " / "1) " → "一、 "
    final m = RegExp(r'^\s*(\d{1,2})[.、)）]\s*').firstMatch(line);
    if (m != null) {
      final num = int.parse(m.group(1)!);
      final rest = line.substring(m.end);
      line = (num >= 1 && num <= _cnNums.length)
          ? '${_cnNums[num - 1]}、${rest.isEmpty ? ' ' : rest}'
          : rest;
    } else {
      // 无序列表 "- " / "* " / "• " → "· "
      final m2 = RegExp(r'^\s*[-*•]\s+').firstMatch(line);
      if (m2 != null) {
        line = '· ${line.substring(m2.end)}';
      }
    }
    // 去掉加粗 / 斜体 / 删除线
    line = line.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (x) => x.group(1)!);
    line = line.replaceAllMapped(RegExp(r'__([^_\n]+?)__'), (x) => x.group(1)!);
    line = line.replaceAllMapped(RegExp(r'\*([^*\n]+)\*'), (x) => x.group(1)!);
    line = line.replaceAllMapped(RegExp(r'~~([^~\n]+?)~~'), (x) => x.group(1)!);
    // 去掉行内代码 `code`
    line = line.replaceAllMapped(RegExp(r'`([^`\n]+?)`'), (x) => x.group(1)!);
    // 图片 / 链接 → 保留文字
    line = line.replaceAllMapped(
        RegExp(r'!\[([^\]]*)\]\([^)]*\)'), (x) => x.group(1) ?? '');
    line = line.replaceAllMapped(
        RegExp(r'\[([^\]]+)\]\([^)]*\)'), (x) => x.group(1)!);
    out.add(line);
  }
  final result = out.join('\n');
  return result.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

/// 流式增量回调：每次调用携带一段新增文本。
/// [delta] 本次新增片段；[reasoning] 为 true 表示思考过程片段
/// （不建议展示正文），false 表示最终正文片段（应逐字展示）。
typedef ChatStreamCallback = void Function(
  String delta, {
  required bool reasoning,
});

/// 对话服务接口
abstract class ChatService {
  /// 设置个人职业身份上下文，作为每次对话的系统提示词注入。
  ///
  /// 传入 null 表示清除个人上下文。上下文文本由调用方构造，
  /// 实现层不耦合具体的个人数据模型。
  void setPersonContext(String? contextText);

  /// 设置当前租户ID（个人手机号），用于搜索数据自动沉淀等租户隔离操作。
  ///
  /// 传入 null 表示清除租户ID。
  void setTenantId(String? tenantId);

  /// 发送消息并返回 AI 回复。
  ///
  /// [history] 为完整对话历史（含最新一条用户消息），
  /// 由实现方决定如何携带上下文（当前 MVP 全量透传）。
  /// [model] 指定使用的模型 id，见 [kChatModels]。
  /// [search] 为 true 时，对最新一条用户消息执行联网搜索，
  /// 并把搜索来源注入上下文、在回复末尾附上参考资料。
  /// [systemExtra] 额外的系统提示词（如业务智能体的业务域上下文），
  /// 拼接到个人上下文之后一并注入；传入 null 表示不追加。
  /// [onDelta] 提供后按流式逐段回调增量文本（思考段/正文段分开）；
  /// 返回值始终为最终完整正文（兼容非流式调用方）。
  Future<String> sendMessage(
    List<ChatMessage> history, {
    String model = 'deepseek-flash',
    bool search = false,
    String? systemExtra,
    ChatStreamCallback? onDelta,
  });
}
