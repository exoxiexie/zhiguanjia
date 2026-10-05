/// 业务智能体详情页
///
/// 左上角：返回箭头 + 双横杠菜单（打开左侧抽屉，显示本智能体历史对话）
/// 右上角：新建对话按钮
/// 内容区：智能体占位信息 + 对话消息列表（持久化到数据库）
/// 底部：与对话页完全一致的输入栏（ChatInputBar），支持图片/文件/文件夹附件
/// 上下文：打开时加载该业务标签（[title]）下已沉淀的数据，
/// 组装成系统提示词注入对话（BusinessContextService）
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../contracts/agent_service.dart';
import '../../contracts/chat_service.dart';
import '../data/business_agent_role.dart';
import '../data/business_context_service.dart';
import '../personal/personal_auth_service.dart';
import '../storage/database/dao/message_dao.dart';
import '../storage/database/dao/session_dao.dart';
import '../storage/database/models/message_entity.dart';
import '../storage/database/models/session_entity.dart';
import 'attachment_parser.dart';
import 'chat_input_bar.dart';

/// 业务智能体详情页
class BusinessAgentPage extends StatefulWidget {
  final String title;
  final String tenantId;
  final ChatService chatService;
  final AgentService? agentService;

  const BusinessAgentPage({
    super.key,
    required this.title,
    required this.tenantId,
    required this.chatService,
    this.agentService,
  });

  @override
  State<BusinessAgentPage> createState() => _BusinessAgentPageState();
}

class _BusinessAgentPageState extends State<BusinessAgentPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _isLoading = false;
  ChatModel _selectedModel = kChatModels[0];

  /// 业务域上下文
  String? _businessContext;
  bool _contextLoading = true;

  // === 会话管理 ===
  final SessionDao _sessionDao = SessionDao();
  final MessageDao _messageDao = MessageDao();
  List<SessionEntity> _sessions = [];
  SessionEntity? _currentSession;
  List<ChatMessage> _messages = [];
  String? _currentUserPhone;

  // === 附件 ===
  ChatAttachment? _pendingAttachment;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final auth = await PersonalAuthService.getAuth();
    _currentUserPhone = auth?.phone;
    await _loadBusinessContext();
    await _loadSessions();
  }

  Future<void> _loadBusinessContext() async {
    try {
      final context = await BusinessContextService.build(
          tenantId: widget.tenantId, businessTag: widget.title);
      final fullPrompt =
          BusinessAgentRole.buildSystemPrompt(widget.title, context);
      if (mounted) {
        setState(() {
          _businessContext = fullPrompt;
          _contextLoading = false;
        });
      }
    } catch (e) {
      debugPrint('加载业务上下文失败: $e');
      if (mounted) setState(() => _contextLoading = false);
    }
  }

  Future<void> _loadSessions() async {
    try {
      // 个人版只有账号本人，加载该任务域下的全部会话
      final list = await _sessionDao.findByTenantAndBusiness(
          widget.tenantId, widget.title);
      if (mounted) {
        setState(() => _sessions = list);
        if (list.isNotEmpty) {
          _switchSession(list.first);
        } else {
          _createNewSession();
        }
      }
    } catch (e) {
      debugPrint('加载会话列表失败: $e');
    }
  }

  void _createNewSession() async {
    // 先检测是否存在0消息的空会话，有就直接切换过去，不重复创建
    for (final s in _sessions) {
      if (s.messageCount == 0) {
        _switchSession(s);
        if (mounted) {
          setState(() {
            _controller.clear();
            _isLoading = false;
          });
        }
        return;
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final session = SessionEntity(
      id: now.toString(),
      tenantId: widget.tenantId,
      title: '${widget.title}对话',
      createdAt: now,
      updatedAt: now,
      createdBy: _currentUserPhone,
      businessTag: widget.title,
    );
    await _sessionDao.insert(session);
    if (mounted) {
      setState(() {
        _currentSession = session;
        _messages = [];
        _pendingAttachment = null;
        _sessions.insert(0, session);
      });
    }
  }

  void _switchSession(SessionEntity session) async {
    final msgs = await _messageDao.findBySession(session.id);
    if (mounted) {
      setState(() {
        _currentSession = session;
        _messages = msgs
            .map((m) => ChatMessage(role: m.role, content: m.content))
            .toList();
        _pendingAttachment = null;
      });
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // === 附件功能（与通用对话页一致） ===

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
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择图片失败：$e')),
      );
    }
  }

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

          buffer.writeln('===== ${file.name} =====');
          buffer.writeln(text);
          if (i < files.length - 1) buffer.writeln();
        }
        final merged = buffer.toString();
        if (mounted) {
          setState(() {
            _pendingAttachment = _pendingAttachment?.copyWith(text: merged);
          });
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _pendingAttachment = null;
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
            content: Text('U 盘/移动硬盘文件夹暂不支持直接遍历，请改用「选择文件」方式'),
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
      } catch (_) {}

      if (supportedFiles.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该文件夹下没有支持的文档')),
        );
        return;
      }

      setState(() {
        _pendingAttachment = ChatAttachment(
          type: ChatAttachmentType.document,
          name: '${dir.path.split('/').last}（${supportedFiles.length} 个文件）',
          filePath: dirPath,
        );
      });

      try {
        final buffer = StringBuffer();
        for (var i = 0; i < supportedFiles.length; i++) {
          final file = supportedFiles[i];
          final text = await extractDocumentText(file.path);
          buffer.writeln('===== ${file.path.split('/').last} =====');
          buffer.writeln(text);
          if (i < supportedFiles.length - 1) buffer.writeln();
        }
        final merged = buffer.toString();
        if (mounted) {
          setState(() {
            _pendingAttachment = _pendingAttachment?.copyWith(text: merged);
          });
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _pendingAttachment = null;
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

  Future<void> _send() async {
    final text = _controller.text.trim();
    final attachment = _pendingAttachment;
    if ((text.isEmpty && attachment == null) ||
        _isLoading ||
        _currentSession == null) return;
    final sessionId = _currentSession!.id;

    final userMsg = ChatMessage(
      role: 'user',
      content: text,
      attachment: attachment,
    );

    setState(() {
      _messages.add(userMsg);
      _controller.clear();
      _pendingAttachment = null;
      _isLoading = true;
    });
    _scrollToBottom();

    // 保存用户消息到数据库
    final now = DateTime.now().millisecondsSinceEpoch;
    await _messageDao.insert(MessageEntity(
      id: 'u$now',
      sessionId: sessionId,
      role: 'user',
      content: text,
      createdAt: now,
    ));
    await _sessionDao.incrementMessageCount(sessionId);

    try {
      final reply = await widget.chatService.sendMessage(
        _messages
            .map((m) => ChatMessage(
                role: m.role, content: m.content, attachment: m.attachment))
            .toList(),
        model: _selectedModel.id,
        systemExtra: _businessContext,
      );
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(role: 'assistant', content: reply));
          _isLoading = false;
        });
        _scrollToBottom();

        final now2 = DateTime.now().millisecondsSinceEpoch;
        await _messageDao.insert(MessageEntity(
          id: 'a$now2',
          sessionId: sessionId,
          role: 'assistant',
          content: reply,
          createdAt: now2,
        ));
        await _sessionDao.incrementMessageCount(sessionId);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages
              .add(ChatMessage(role: 'assistant', content: '请求失败，请稍后重试（$e）'));
          _isLoading = false;
        });
        _scrollToBottom();
      }
    }
  }

  Widget _buildMenuIcon() {
    return Center(
      child: InkWell(
        onTap: () => _scaffoldKey.currentState?.openDrawer(),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                  width: 22,
                  height: 2.5,
                  decoration: BoxDecoration(
                    color: const Color(0xCC1A1B1C),
                    borderRadius: BorderRadius.circular(1.25),
                  )),
              const SizedBox(height: 6),
              Container(
                  width: 14,
                  height: 2.5,
                  decoration: BoxDecoration(
                    color: const Color(0xCC1A1B1C),
                    borderRadius: BorderRadius.circular(1.25),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.8,
      child: Column(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    _createNewSession();
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新建对话'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5B7FD4),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _sessions.isEmpty
                ? const Center(
                    child: Text('暂无历史对话',
                        style:
                            TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _sessions.length,
                    itemBuilder: (ctx, i) {
                      final s = _sessions[i];
                      final active = s.id == _currentSession?.id;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          active
                              ? Icons.chat_bubble
                              : Icons.chat_bubble_outline,
                          size: 18,
                          color: active
                              ? const Color(0xFF5B7FD4)
                              : const Color(0x661A1B1C),
                        ),
                        title: Text(
                          s.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                active ? FontWeight.w600 : FontWeight.w400,
                            color: active
                                ? const Color(0xFF5B7FD4)
                                : const Color(0xFF1A1B1C),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${s.messageCount} 条消息',
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF9CA3AF)),
                        ),
                        selected: active,
                        onTap: () {
                          _switchSession(s);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // === 附件预览 chip（与通用对话页一致） ===
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
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => setState(() => _pendingAttachment = null),
            child: const Icon(Icons.close, size: 16, color: Color(0x991A1B1C)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
        backgroundColor: Colors.white,
        automaticallyImplyLeading: false,
        leadingWidth: 122,
        leading: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    size: 16, color: Color(0xFF1B3A5C)),
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: '返回',
              ),
              const SizedBox(width: 6),
              _buildMenuIcon(),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, size: 22),
            onPressed: _createNewSession,
            tooltip: '新建对话',
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: _buildDrawer(),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyAgent(context)
                : _buildMessageList(),
          ),
          ChatInputBar(
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
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyAgent(BuildContext context) {
    final subtitle =
        _contextLoading ? '正在加载本业务域沉淀数据…' : '已加载业务域数据上下文，可以在下方直接对话';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF5B7FD4).withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.smart_toy_outlined,
                size: 32, color: Color(0xFF5B7FD4)),
          ),
          const SizedBox(height: 14),
          Text(
            widget.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1B1C),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
      itemCount: _messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          return const _ThinkingBubble();
        }
        return _Bubble(message: _messages[index]);
      },
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
}

/// 单条消息气泡（支持附件展示）
class _Bubble extends StatelessWidget {
  final ChatMessage message;

  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final att = message.attachment;
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
            if (att != null) _AttachmentView(attachment: att, isUser: isUser),
            if (message.content.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: att != null ? 8 : 0),
                child: Text(
                  message.content,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: isUser ? Colors.white : const Color(0xFF1A1B1C),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 消息内的附件展示
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
    // 文档附件
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isUser
            ? Colors.white.withOpacity(0.2)
            : const Color(0xFF5B7FD4).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file,
              size: 18, color: isUser ? Colors.white : const Color(0xFF5B7FD4)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              attachment.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: isUser ? Colors.white : const Color(0xFF1A1B1C),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Text(
          '正在思考…',
          style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
        ),
      ),
    );
  }
}
