/// 对话 Tab · 与职管家 AI 的对话界面
///
/// 【架构】UI 层只依赖契约（ChatService / AgentService / ChatSessionService），
/// 所有数据库/存储/存档/提炼操作统一委托给 ChatSessionService，
/// 不直接 import 任何 DAO/Entity/存储层，实现模块硬隔离。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../contracts/agent_service.dart';
import '../../contracts/chat_service.dart';
import '../../contracts/chat_session_service.dart';
import '../../core/di/service_locator.dart';
import '../agent/agent_service_impl.dart';
import '../chat/attachment_parser.dart';
import '../chat/chat_input_bar.dart';
import '../chat/identity_question.dart';
import '../chat/message_action_bar.dart';
import '../chat/preset_commands_page.dart';
import '../memory/memory_distiller.dart';
import '../personal/personal_auth_service.dart';
import '../sync/sync_engine.dart';
import '../personal/personal_model.dart';

// 导出 Conversation 类型，保持 shell_page 等通过 import home_tab 间接访问的兼容性
export '../../contracts/chat_session_service.dart' show Conversation;

/// 对话页：消息列表 + 输入栏，通过 [AgentService] 契约与后端通信
class HomeTab extends StatefulWidget {
  final ChatService chatService;
  final AgentService? agentService;

  const HomeTab({super.key, required this.chatService, this.agentService});

  @override
  State<HomeTab> createState() => HomeTabState();
}

class HomeTabState extends State<HomeTab> {
  /// 会话服务（统一管理会话/消息/存档/提炼，从 DI 容器获取）
  final ChatSessionService _sessionService = sl.get<ChatSessionService>();

  @override
  void initState() {
    super.initState();
    _initSessionService();
  }

  /// 初始化会话服务（获取租户、打开数据库、加载历史会话）
  Future<void> _initSessionService() async {
    await _sessionService.init();
    // P4：先补发本地变更、拉取云端增量（需本地库已打开），再重新加载一次，
    // 这样换手机登录进来说话时，云端已有的会话会直接出现。
    // 失败静默：离线时照常用本地数据。
    await SyncEngine.sync();
    await _sessionService.init();
    // 设置个人职业身份上下文（实名认证后作为每次对话的系统提示词）
    await _setupPersonContext();
    if (mounted) setState(() {});
  }

  /// 获取当前登录个人的实名身份画像，构造上下文文本并设置到对话服务。
  ///
  /// 身份锚定：让职业管家知道服务的对象是谁。
  /// 隐私原则：只注入姓名/性别/年龄/籍贯等职业画像字段，
  /// 不注入完整身份证号（仅内部脱敏保存）。未实名认证则不注入。
  Future<void> _setupPersonContext() async {
    try {
      final PersonalAuth? auth = await PersonalAuthService.getAuth();
      if (auth == null || !auth.isVerified) {
        // 【P0-2】清身份上下文的同时必须清租户 ID：
        // 只清上下文会让"未实名的下一个账号"把联网搜索沉淀写进上一个账号目录
        widget.chatService.setPersonContext(null);
        widget.chatService.setTenantId(null);
        widget.agentService?.setPersonContext(null);
        widget.agentService?.setTenantId(null);
        return;
      }

      // 年龄（由实名认证解析出的出生日期计算）
      int? age;
      if (auth.birthday.isNotEmpty) {
        final birth = DateTime.tryParse(auth.birthday);
        if (birth != null) {
          final now = DateTime.now();
          age = now.year -
              birth.year -
              ((now.month < birth.month ||
                      (now.month == birth.month && now.day < birth.day))
                  ? 1
                  : 0);
        }
      }

      final buf = StringBuffer();
      buf.writeln('【个人职业身份档案】');
      buf.writeln('姓名：${auth.name}');
      buf.writeln('实名认证：已认证');
      if (auth.gender.isNotEmpty) buf.writeln('性别：${auth.gender}');
      if (age != null && age > 0 && age < 120) buf.writeln('年龄：$age岁');
      if (auth.province.isNotEmpty) buf.writeln('籍贯：${auth.province}');
      buf.write('说明：身份证号等敏感信息已脱敏处理，不在对话上下文中展示。');

      widget.chatService.setPersonContext(buf.toString());
      widget.chatService.setTenantId(auth.phone);
      widget.agentService?.setPersonContext(buf.toString());
      widget.agentService?.setTenantId(auth.phone);
    } catch (e) {
      debugPrint('设置个人身份上下文失败: $e');
      widget.chatService.setPersonContext(null);
      widget.chatService.setTenantId(null);
      widget.agentService?.setPersonContext(null);
      widget.agentService?.setTenantId(null);
    }
  }

  /// 当前对话的消息列表（便捷访问）
  List<ChatMessage> get _messages => _sessionService.currentMessages;

  /// 暴露给外部：所有历史会话
  List<Conversation> get conversations => _sessionService.conversations;

  /// 暴露给外部：当前对话索引
  int get currentIndex => _sessionService.currentIndex;

  /// 新建对话
  Future<void> newConversation() async {
    await _sessionService.newConversation();
    if (mounted) {
      setState(() {
        _pendingAttachment = null;
        _controller.clear();
        _streamBuffer.clear();
        _isLoading = false;
      });
    }
  }

  /// 切换到指定对话
  void switchConversation(int index) {
    _sessionService.switchConversation(index);
    if (mounted) {
      setState(() {
        _pendingAttachment = null;
        _streamBuffer.clear();
        _isLoading = false;
      });
    }
  }

  /// 从第 [index] 条消息处「分叉」出一条新对话
  ///
  /// 复制该条（含）之前的消息到新会话并切过去，原会话保持不变。
  /// 交给会话服务落库，UI 只负责重置本地流式状态。
  Future<void> forkConversation(int index) async {
    if (_isLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 正在回复中，请稍后再分叉')),
      );
      return;
    }
    await _sessionService.forkConversation(index);
    if (!mounted) return;
    setState(() {
      _pendingAttachment = null;
      _streamBuffer.clear();
      _isLoading = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已从该处分叉出新对话，原对话已保留'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// 供外部调用：提炼当前对话为记忆（手动触发）
  ///
  /// 弹出确认对话框，用户选择增量提炼或全部提炼后，
  /// 调用 AI 对对话内容进行提炼，保存到对话记忆数据中。
  Future<void> extractToMemory() async {
    if (_isLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 正在回复中，请稍后再提炼')),
      );
      return;
    }

    final messages = _sessionService.currentMessages;
    if (messages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前对话没有内容，无法提炼')),
      );
      return;
    }

    // 检查是否有过提炼记录
    final lastExtractedId = await _sessionService.getLastExtractedMessageId();
    final hasExtracted = lastExtractedId != null && lastExtractedId.isNotEmpty;

    if (!mounted) return;

    // 弹出确认对话框
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('提炼为记忆'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasExtracted
                  ? '将对上次提炼之后的新对话进行增量提炼，避免重复。'
                  : '将对当前全部对话内容进行提炼，生成一条结构化记忆。',
            ),
            const SizedBox(height: 12),
            Text(
              '当前对话共 ${messages.length} 条消息',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          if (hasExtracted)
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('增量提炼'),
            ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(hasExtracted ? '全部提炼' : '开始提炼'),
          ),
        ],
      ),
    );

    if (result != true || !mounted) return;

    // 显示 loading
    setState(() {
      _isLoading = true;
      _thinkingText = '正在提炼记忆…';
    });

    try {
      final success = await _sessionService.extractToMemory(
        incremental: hasExtracted,
      );

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('提炼成功！已保存到对话记忆数据'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        final errorMsg = MemoryDistiller.lastError ?? '未知错误';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('提炼失败：$errorMsg')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('提炼失败：$e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _thinkingText = '正在思考…';
        });
      }
    }
  }

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  /// 供外部调用：设置输入框内容（快捷指令跳转时使用）
  void setInputText(String text) {
    _controller.text = text;
  }

  /// 当前选中的对话模型（默认 DeepSeek V4.1 Flash，原生多模态）
  ChatModel _selectedModel = kChatModels[0];

  /// 发送中提示文案（普通思考 / 搜索中 / 读取网页）
  String _thinkingText = '正在思考…';

  /// 待发送附件（选择后、发送前暂存）
  ChatAttachment? _pendingAttachment;

  /// 文档附件解析中标记
  bool _parsingDoc = false;

  /// 是否正在输出正文（false=仍在思考/读取中，true=正文逐字流出）
  bool _streamingReasoning = true;

  /// 流式正文累积缓冲（onDelta 的正文片段逐段追加）
  final StringBuffer _streamBuffer = StringBuffer();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    final attachment = _pendingAttachment;
    if ((text.isEmpty && attachment == null) || _isLoading) return;

    _controller.clear();
    final userMsg = ChatMessage(
      role: 'user',
      content: text,
      attachment: attachment,
    );
    String? newTitle;
    setState(() {
      _messages.add(userMsg);
      // 如果是对话的第一条消息，用前15个字作为对话标题
      if (_sessionService.currentConversation.title == '新对话' &&
          text.isNotEmpty) {
        newTitle = text.length > 15 ? '${text.substring(0, 15)}…' : text;
        _sessionService.currentConversation.title = newTitle!;
      }
      _sessionService.currentConversation.updatedAt = DateTime.now();
      _pendingAttachment = null;
      _parsingDoc = false;
      _isLoading = true;
      _thinkingText = RegExp(r'https?://').hasMatch(text) ? '正在读取网页…' : '正在思考…';
      _streamingReasoning = true;
      _streamBuffer.clear();
    });
    _scrollToBottom();

    // 持久化用户消息和会话标题（委托给会话服务）
    _sessionService.persistMessage(userMsg);
    if (newTitle != null) _sessionService.updateSessionTitle(newTitle!);

    try {
      // ── 身份问题统一拦截：不管 Agent 还是普通对话，都直接返回标准答案 ──
      // 判定为整句白名单匹配（见 chat/identity_question.dart），不误伤业务提问
      if (isIdentityQuestion(text)) {
        const answer = '我是职管家 AI 职业管家，致力于为你提供职业规划、求职发展、技能成长等全职业生涯的智能服务。';
        for (var i = 0; i < answer.length; i++) {
          if (!mounted) return;
          setState(() {
            _thinkingText = '';
            _streamingReasoning = false;
            _streamBuffer.write(answer[i]);
          });
          _scrollToBottom();
          await Future.delayed(const Duration(milliseconds: 20));
        }
        if (!mounted) return;
        final assistantMsg = ChatMessage(role: 'assistant', content: answer);
        setState(() {
          _messages.add(assistantMsg);
          _isLoading = false;
          _streamingReasoning = true;
          _streamBuffer.clear();
        });
        _scrollToBottom();
        _sessionService.persistMessage(assistantMsg);
        return;
      }

      final agent = widget.agentService;
      if (agent != null) {
        // ── Agent 模式：自动判断是否需要搜索，工具循环 + 流式最终回复 ──
        final agentService = agent as HttpAgentService;
        final tools = [
          buildWebSearchTool(agentService),
          buildWebFetchTool(agentService)
        ];
        final result = await agent.run(
          history: List.of(_messages),
          tools: tools,
          model: _selectedModel.id,
          maxSteps: 5,
          onDelta: (delta, {required bool reasoning}) {
            if (!mounted) return;
            setState(() {
              if (!reasoning) {
                _streamingReasoning = false;
                _streamBuffer.write(delta);
              }
            });
            _scrollToBottom();
          },
          onToolStart: (toolName) {
            if (!mounted) return;
            setState(() {
              // 工具开始执行 → 回到「思考中」态：
              // 真流式下，模型可能在决定调工具前先吐过一小段过渡文字，
              // 这里把它清掉，避免工具执行期间还挂着半截话。
              _streamingReasoning = true;
              _streamBuffer.clear();
              if (toolName == 'web_search') {
                _thinkingText = '正在联网搜索…';
              } else if (toolName == 'web_fetch') {
                _thinkingText = '正在读取网页内容…';
              } else {
                _thinkingText = '正在调用工具…';
              }
            });
          },
          onToolEnd: (toolName, result) {
            if (!mounted) return;
            setState(() {
              _thinkingText = '正在思考…';
            });
          },
        );
        if (!mounted) return;
        final agentMsg = ChatMessage(role: 'assistant', content: result.reply);
        setState(() {
          _messages.add(agentMsg);
          _isLoading = false;
          _streamingReasoning = true;
          _streamBuffer.clear();
        });
        _sessionService.persistMessage(agentMsg);
      } else {
        // ── 回退模式：普通对话（无 Agent 能力）──
        final reply = await widget.chatService.sendMessage(
          List.of(_messages),
          model: _selectedModel.id,
          search: false,
          onDelta: (delta, {required bool reasoning}) {
            if (!mounted) return;
            setState(() {
              _thinkingText = '正在思考…';
              if (!reasoning) {
                _streamingReasoning = false;
                _streamBuffer.write(delta);
              }
            });
            _scrollToBottom();
          },
        );
        if (!mounted) return;
        final replyMsg = ChatMessage(role: 'assistant', content: reply);
        setState(() {
          _messages.add(replyMsg);
          _isLoading = false;
          _streamingReasoning = true;
          _streamBuffer.clear();
        });
        _sessionService.persistMessage(replyMsg);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _streamingReasoning = true;
        _streamBuffer.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败：$e')),
      );
    }
    _scrollToBottom();
  }

  /// 弹出附件选择面板（相册 / 拍照 / 文件）
  void _showAttachmentSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: Color(0xFF5B7FD4)),
              title: const Text('从相册选择图片'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: Color(0xFF5B7FD4)),
              title: const Text('拍照'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined,
                  color: Color(0xFF5B7FD4)),
              title: const Text('选择文件（可多选，PDF / Word / TXT）'),
              onTap: () {
                Navigator.pop(ctx);
                _pickFile();
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.folder_outlined, color: Color(0xFF5B7FD4)),
              title: const Text('选择文件夹（自动解析里面所有文档）'),
              onTap: () {
                Navigator.pop(ctx);
                _pickFolder();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 选择图片（相册 / 拍照），压缩后暂存为待发送附件
  Future<void> _pickImage(ImageSource source) async {
    try {
      final x = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1280,
        imageQuality: 70,
      );
      if (x == null || !mounted) return;
      setState(() {
        _pendingAttachment = ChatAttachment(
          type: ChatAttachmentType.image,
          name: x.name,
          filePath: x.path,
        );
        _parsingDoc = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择图片失败：$e')),
      );
    }
  }

  /// 选择本地文档并立即解析文本（支持多选，支持 U 盘/移动硬盘）
  Future<void> _pickFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'docx', 'txt', 'md'],
        withData: true,
        allowMultiple: true,
      );
      final files = res?.files;
      if (files == null || files.isEmpty || !mounted) return;

      setState(() {
        _pendingAttachment = ChatAttachment(
          type: ChatAttachmentType.document,
          name: files.length == 1 ? files.first.name : '${files.length} 个文件',
          filePath: files.length == 1 ? files.first.path : null,
        );
        _parsingDoc = true;
      });

      try {
        final buffer = StringBuffer();
        for (var i = 0; i < files.length; i++) {
          final file = files[i];
          final bytes = file.bytes;
          final path = file.path;
          final ext = file.extension?.toLowerCase() ??
              (file.name.contains('.')
                  ? file.name.toLowerCase().split('.').last
                  : (path != null && path.contains('.')
                      ? path.toLowerCase().split('.').last
                      : ''));

          final String text;
          if (bytes != null && bytes.isNotEmpty) {
            text = await extractDocumentTextFromBytes(bytes, ext);
          } else if (path != null) {
            text = await extractDocumentText(path);
          } else {
            buffer.writeln('===== ${file.name}（无法读取文件内容）=====');
            if (i < files.length - 1) buffer.writeln();
            continue;
          }

          if (files.length > 1) {
            buffer.writeln('===== ${file.name} =====');
          }
          buffer.writeln(text);
          if (i < files.length - 1) buffer.writeln();
        }

        final merged = buffer.toString().trim();
        if (merged.isEmpty) {
          throw Exception('未从文件中解析出文本');
        }

        if (!mounted) return;
        setState(() {
          _pendingAttachment = _pendingAttachment?.copyWith(text: merged);
          _parsingDoc = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _pendingAttachment = null;
          _parsingDoc = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('文件解析失败：$e')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择文件失败：$e')),
      );
    }
  }

  /// 选择文件夹并自动解析里面所有支持的文档（PDF/Word/TXT/MD）
  Future<void> _pickFolder() async {
    try {
      final dirPath = await FilePicker.platform.getDirectoryPath();
      if (dirPath == null || !mounted) return;

      final dir = Directory(dirPath);
      bool accessible = false;
      try {
        accessible = await dir.exists();
      } catch (_) {
        accessible = false;
      }

      if (!accessible) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('U 盘/移动硬盘文件夹暂不支持直接遍历，请改用「选择文件」方式进文件夹全选'),
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }

      final supportedFiles = <File>[];
      try {
        await for (final entity
            in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            final ext = entity.path.toLowerCase().split('.').last;
            if (kSupportedDocExts.contains(ext)) {
              supportedFiles.add(entity);
            }
          }
        }
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('U 盘/移动硬盘文件夹无法直接遍历，请改用「选择文件」方式进文件夹全选'),
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }

      if (supportedFiles.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该文件夹中没有找到支持的文档（PDF/Word/TXT/MD）')),
        );
        return;
      }

      setState(() {
        _pendingAttachment = ChatAttachment(
          type: ChatAttachmentType.document,
          name: '${dir.path.split('/').last}（${supportedFiles.length} 个文件）',
          filePath: dirPath,
        );
        _parsingDoc = true;
      });

      try {
        final buffer = StringBuffer();
        for (var i = 0; i < supportedFiles.length; i++) {
          final file = supportedFiles[i];
          try {
            final text = await extractDocumentText(file.path);
            final fileName = file.path.split('/').last;
            buffer.writeln('===== $fileName =====');
            buffer.writeln(text);
            if (i < supportedFiles.length - 1) buffer.writeln();
          } catch (e) {
            final fileName = file.path.split('/').last;
            buffer.writeln('===== $fileName（解析失败：$e）=====');
            if (i < supportedFiles.length - 1) buffer.writeln();
          }
        }

        final merged = buffer.toString().trim();
        if (merged.isEmpty) {
          throw Exception('未从文件夹中解析出有效文本');
        }

        if (!mounted) return;
        setState(() {
          _pendingAttachment = _pendingAttachment?.copyWith(text: merged);
          _parsingDoc = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _pendingAttachment = null;
          _parsingDoc = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('文件夹解析失败：$e')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择文件夹失败：$e')),
      );
    }
  }

  /// 功能按钮（胶囊样式，用于功能按钮区）
  Widget _buildFeatureButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0x0F000000),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xCC1A1B1C)),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(fontSize: 12, color: Color(0xCC1A1B1C))),
          ],
        ),
      ),
    );
  }

  /// 输入栏上方的待发送附件条
  Widget _buildAttachmentChip() {
    final att = _pendingAttachment!;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x0F000000),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (att.type == ChatAttachmentType.image && att.filePath != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(
                File(att.filePath!),
                width: 36,
                height: 36,
                fit: BoxFit.cover,
              ),
            )
          else
            const Icon(Icons.insert_drive_file_outlined,
                size: 20, color: Color(0xAA5B7FD4)),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              att.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Color(0xCC1A1B1C)),
            ),
          ),
          if (_parsingDoc) ...[
            const SizedBox(width: 6),
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => setState(() {
              _pendingAttachment = null;
              _parsingDoc = false;
            }),
            child: const Icon(Icons.close, size: 16, color: Color(0x991A1B1C)),
          ),
        ],
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty && !_isLoading
              ? _buildEmptyState()
              : _buildMessageList(),
        ),
        _buildInputBar(),
      ],
    );
  }

  /// 空状态：快捷指令卡片 + 居中提示
  Widget _buildEmptyState() {
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
      children: [
        _buildQuickCommandCard(),
        const SizedBox(height: 80),
        Column(
          children: [
            const Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Color(0x335B7FD4),
            ),
            const SizedBox(height: 12),
            const Text(
              '职管家，每个人的 AI 职业管家',
              style: TextStyle(fontSize: 16, color: Color(0xAA1A1B1C)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
      itemCount: 1 + _messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        // 滚动区最上面：快捷指令卡片
        if (index == 0) {
          return _buildQuickCommandCard();
        }
        final msgIndex = index - 1;
        if (msgIndex == _messages.length) {
          if (!_streamingReasoning && _streamBuffer.isNotEmpty) {
            return _MessageBubble(
              message: ChatMessage(
                role: 'assistant',
                content: mdToCnText(_streamBuffer.toString()),
              ),
            );
          }
          return _ThinkingBubble(text: _thinkingText);
        }
        final msg = _messages[msgIndex];
        return _MessageBubble(
          message: msg,
          // 已在会话里的 AI 回复才可「分叉」；流式中的气泡不挂（见上面分支）
          onFork: msg.role == 'assistant'
              ? () => forkConversation(msgIndex)
              : null,
        );
      },
    );
  }

  /// 快捷指令卡片（点击进入预设指令列表，选择后填入输入框）
  Widget _buildQuickCommandCard() {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PresetCommandsPage(
              onSelect: (command) => setInputText(command),
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF5B7FD4), Color(0xFF7C3AED)],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // 左侧图标
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.tips_and_updates_outlined,
                  size: 22, color: Colors.white),
            ),
            const SizedBox(width: 12),
            // 中间标题和小字
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '试试像这样给我下指令',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '正确的、完整的指令会得到更好的结果',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            // 右侧箭头
            const Icon(Icons.arrow_forward_ios,
                size: 16, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return ChatInputBar(
      controller: _controller,
      isLoading: _isLoading,
      pendingAttachment:
          _pendingAttachment != null ? _buildAttachmentChip() : null,
      selectedModel: _selectedModel,
      onModelChanged: (m) {
        setState(() => _selectedModel = m);
      },
      onAddAttachment: _showAttachmentSheet,
      onSend: _send,
      onConnectComputer: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('连接电脑功能开发中')),
        );
      },
      onSkillSelect: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('技能选择功能开发中')),
        );
      },
    );
  }
}

/// 单条消息气泡
class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  /// 点「分叉」的回调；为 null 时不显示该按钮（用户消息、流式中气泡）
  final VoidCallback? onFork;

  const _MessageBubble({required this.message, this.onFork});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * (isUser ? 0.72 : 0.9),
        ),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF5B7FD4) : const Color(0x0F000000),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.attachment != null)
              _AttachmentView(
                attachment: message.attachment!,
                isUser: isUser,
              ),
            if (message.content.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(
                  top: message.attachment != null ? 8 : 0,
                ),
                child: SelectableText(
                  message.content,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: isUser ? Colors.white : const Color(0xFF1A1B1C),
                  ),
                ),
              ),
            if (!isUser && message.content.isNotEmpty)
              MessageActionBar(
                content: message.content,
                source: '通用对话',
                onFork: onFork,
              ),
          ],
        ),
      ),
    );
  }
}

/// 消息内的附件展示（图片缩略图 / 文档名）
class _AttachmentView extends StatelessWidget {
  final ChatAttachment attachment;
  final bool isUser;

  const _AttachmentView({required this.attachment, required this.isUser});

  @override
  Widget build(BuildContext context) {
    if (attachment.type == ChatAttachmentType.image &&
        attachment.filePath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180, maxHeight: 240),
          child: Image.file(
            File(attachment.filePath!),
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.insert_drive_file_outlined,
          size: 18,
          color: isUser ? Colors.white : const Color(0xAA5B7FD4),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            attachment.name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: isUser ? Colors.white : const Color(0xCC1A1B1C),
            ),
          ),
        ),
      ],
    );
  }
}

/// AI 思考中的气泡
class _ThinkingBubble extends StatelessWidget {
  final String text;

  const _ThinkingBubble({this.text = '正在思考…'});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: Color(0x0F000000),
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              text,
              style: const TextStyle(fontSize: 14, color: Color(0x991A1B1C)),
            ),
          ],
        ),
      ),
    );
  }
}
