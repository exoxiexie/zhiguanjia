/// 对话会话服务实现
///
/// 从 home_tab.dart 抽取，负责所有数据库/存储操作：
/// 多租户数据库初始化、会话 CRUD、消息持久化、原始 JSON 存档、
/// AI 回复后的自动记忆提炼。UI 层只调用本类，不直接接触 DAO/Entity。
library;

import 'package:flutter/foundation.dart';

import '../../contracts/chat_service.dart';
import '../../contracts/chat_session_service.dart';
import '../memory/memory_distiller.dart';
import '../personal/personal_auth_service.dart';
import '../storage/database/app_database.dart';
import '../storage/database/dao/message_dao.dart';
import '../storage/database/dao/session_dao.dart';
import '../storage/database/models/message_entity.dart';
import '../storage/database/models/session_entity.dart';
import '../storage/session_archive.dart';

class ChatSessionServiceImpl implements ChatSessionService {
  final SessionDao _sessionDao = SessionDao();
  final MessageDao _messageDao = MessageDao();

  final List<Conversation> _conversations = [
    Conversation(id: 'default', title: '新对话'),
  ];
  int _currentIndex = 0;
  String? _tenantId;
  bool _ready = false;

  /// 当前登录人手机号（用于会话按人隔离）
  String? _currentUserPhone;

  @override
  bool get isReady => _ready;

  @override
  List<Conversation> get conversations => _conversations;

  @override
  int get currentIndex => _currentIndex;

  @override
  Conversation get currentConversation => _conversations[_currentIndex];

  @override
  List<ChatMessage> get currentMessages =>
      _conversations[_currentIndex].messages;

  @override
  Future<void> init() async {
    try {
      final auth = await PersonalAuthService.getAuth();
      if (auth == null) {
        _ready = true;
        return;
      }

      // 个人版以手机号作为租户ID（注册即有、永不变，认证前后一致）
      final tenantId = auth.phone;
      _tenantId = tenantId;
      _currentUserPhone = auth.phone;

      // 打开该租户的数据库
      await appDatabase.open(tenantId);

      // 个人版只有账号本人，加载该租户的全部历史会话
      final sessions = await _sessionDao.findByTenant(tenantId);
      if (sessions.isNotEmpty) {
        final convList = sessions
            .map((s) => Conversation(
                  id: s.id,
                  title: s.title,
                  createdAt: DateTime.fromMillisecondsSinceEpoch(s.createdAt),
                  updatedAt: DateTime.fromMillisecondsSinceEpoch(s.updatedAt),
                ))
            .toList();

        // 加载每个会话的消息
        for (final conv in convList) {
          final msgs = await _messageDao.findBySession(conv.id);
          conv.messages.addAll(msgs.map((m) => ChatMessage(
                role: m.role,
                content: m.content,
                attachment: m.attachmentPath != null
                    ? ChatAttachment(
                        type: m.attachmentType == 'image'
                            ? ChatAttachmentType.image
                            : ChatAttachmentType.document,
                        filePath: m.attachmentPath!,
                        name: '',
                      )
                    : null,
              )));
        }

        _conversations.clear();
        _conversations.addAll(convList);
        _currentIndex = 0;
      } else {
        // 没有历史会话，把默认的"新对话"存入数据库
        final now = DateTime.now().millisecondsSinceEpoch;
        final session = SessionEntity(
          id: _conversations.first.id,
          tenantId: tenantId,
          title: '新对话',
          createdAt: now,
          updatedAt: now,
          createdBy: auth.phone,
        );
        await _sessionDao.insert(session);
      }
      _ready = true;
    } catch (e) {
      debugPrint('数据库初始化失败: $e');
      _ready = true;
    }
  }

  @override
  Future<String> newConversation() async {
    // 先检测是否存在0消息的空会话，有就直接切换过去，不重复创建
    for (int i = 0; i < _conversations.length; i++) {
      if (_conversations[i].messages.isEmpty) {
        _currentIndex = i;
        return _conversations[i].id;
      }
    }

    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    _conversations.insert(
      0,
      Conversation(
        id: newId,
        title: '新对话',
      ),
    );
    _currentIndex = 0;

    // 写入数据库
    if (_tenantId != null && _ready) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _sessionDao.insert(SessionEntity(
        id: newId,
        tenantId: _tenantId!,
        title: '新对话',
        createdAt: now,
        updatedAt: now,
        createdBy: _currentUserPhone,
      ));
    }
    return newId;
  }

  @override
  void switchConversation(int index) {
    if (index < 0 || index >= _conversations.length) return;
    _currentIndex = index;
  }

  @override
  Future<void> persistMessage(ChatMessage msg) async {
    if (_tenantId == null || !_ready) return;
    final sessionId = _conversations[_currentIndex].id;
    final now = DateTime.now().millisecondsSinceEpoch;
    final entity = MessageEntity(
      id: '${now}_${msg.role}_${msg.content.length}',
      sessionId: sessionId,
      role: msg.role,
      content: msg.content,
      attachmentType: msg.attachment?.type.name,
      attachmentPath: msg.attachment?.filePath,
      createdAt: now,
    );
    try {
      await _messageDao.insert(entity);
      await _sessionDao.incrementMessageCount(sessionId);
    } catch (e) {
      debugPrint('消息持久化失败: $e');
      return;
    }
    // 同步把整个会话覆盖写入原始 JSON 存档
    await syncArchive();
    // AI 回复完成后，后台自动提炼对话记忆（不阻塞、失败静默）
    if (msg.role == 'assistant') {
      _triggerDistill();
    }
  }

  @override
  Future<void> updateSessionTitle(String title) async {
    if (_tenantId == null || !_ready) return;
    final sessionId = _conversations[_currentIndex].id;
    try {
      final session = await _sessionDao.findById(sessionId);
      if (session != null) {
        await _sessionDao.update(session.copyWith(
          title: title,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ));
      }
    } catch (e) {
      debugPrint('更新会话标题失败: $e');
    }
  }

  @override
  Future<void> syncArchive() async {
    if (_tenantId == null || !_ready) return;
    final sessionId = _conversations[_currentIndex].id;
    try {
      final session = await _sessionDao.findById(sessionId);
      if (session == null) return;
      final msgs = await _messageDao.findBySession(sessionId);
      await sessionArchive.save(
        tenantId: _tenantId!,
        session: session,
        messages: msgs,
      );
    } catch (e) {
      debugPrint('会话存档失败: $e');
    }
  }

  /// 后台触发对话记忆自动提炼（fire-and-forget）
  void _triggerDistill() {
    if (_tenantId == null || !_ready) return;
    final conv = _conversations[_currentIndex];
    MemoryDistiller.distillAndSave(
      tenantId: _tenantId!,
      conversationText: _conversationToText(conv),
    ).catchError((Object e) {
      debugPrint('自动提炼失败: $e');
      return false;
    });
  }

  /// 把会话消息转为模型可读的对话文本（带附件名，不携带文档正文）
  String _conversationToText(Conversation conv) {
    final buf = StringBuffer();
    for (final m in conv.messages) {
      final role = m.role == 'user' ? '用户' : '职管家';
      buf.writeln('【$role】${m.content}');
      if (m.attachment != null && m.attachment!.name.isNotEmpty) {
        buf.writeln('（附件：${m.attachment!.name}）');
      }
    }
    return buf.toString();
  }

  @override
  Future<String?> getLastExtractedMessageId() async {
    if (_tenantId == null || !_ready) return null;
    final sessionId = _conversations[_currentIndex].id;
    try {
      final session = await _sessionDao.findById(sessionId);
      return session?.lastExtractedMessageId;
    } catch (e) {
      debugPrint('获取最后提炼消息ID失败: $e');
      return null;
    }
  }

  @override
  Future<void> updateLastExtractedMessageId(String messageId) async {
    if (_tenantId == null || !_ready) return;
    final sessionId = _conversations[_currentIndex].id;
    try {
      await _sessionDao.updateLastExtractedMessageId(sessionId, messageId);
    } catch (e) {
      debugPrint('更新最后提炼消息ID失败: $e');
    }
  }

  @override
  Future<bool> extractToMemory({bool incremental = true}) async {
    if (_tenantId == null || !_ready) return false;
    final sessionId = _conversations[_currentIndex].id;
    try {
      // 从数据库获取当前会话的所有消息（带 id，按时间正序）
      final allMessages = await _messageDao.findBySession(sessionId);
      if (allMessages.isEmpty) return false;

      // 确定提炼范围
      List<MessageEntity> messagesToExtract;
      if (incremental) {
        final lastId = await getLastExtractedMessageId();
        if (lastId != null && lastId.isNotEmpty) {
          // 找到最后提炼的消息的索引，只提炼之后的增量消息
          final lastIndex = allMessages.indexWhere((m) => m.id == lastId);
          if (lastIndex >= 0 && lastIndex < allMessages.length - 1) {
            messagesToExtract = allMessages.sublist(lastIndex + 1);
          } else {
            // 找不到或已经是最后一条，没有新消息
            return false;
          }
        } else {
          // 从未提炼过，提炼全部
          messagesToExtract = allMessages;
        }
      } else {
        // 非增量模式，提炼全部
        messagesToExtract = allMessages;
      }

      if (messagesToExtract.isEmpty) return false;

      // 把消息转为对话文本
      final buf = StringBuffer();
      for (final m in messagesToExtract) {
        final role = m.role == 'user' ? '用户' : '职管家';
        buf.writeln('【$role】${m.content}');
      }
      final conversationText = buf.toString();

      // 调用 MemoryDistiller 做提炼（手动提炼时 forceSave=true，强制保存）
      final success = await MemoryDistiller.distillAndSave(
        tenantId: _tenantId!,
        conversationText: conversationText,
        forceSave: true,
        source: '手动提炼',
      );

      // 提炼成功后，更新最后提炼的消息ID为最后一条消息的ID
      if (success) {
        await updateLastExtractedMessageId(messagesToExtract.last.id);
      }

      return success;
    } catch (e) {
      debugPrint('提炼为记忆失败: $e');
      return false;
    }
  }
}
