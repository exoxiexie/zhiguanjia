/// 消息实体（对应 messages 表）
class MessageEntity {
  final String id;
  final String sessionId;
  final String role; // user / assistant
  final String content;
  final String? attachmentType; // image / file / null
  final String? attachmentPath;
  final int createdAt; // 毫秒时间戳

  const MessageEntity({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    this.attachmentType,
    this.attachmentPath,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'session_id': sessionId,
        'role': role,
        'content': content,
        'attachment_type': attachmentType,
        'attachment_path': attachmentPath,
        'created_at': createdAt,
      };

  factory MessageEntity.fromMap(Map<String, dynamic> map) => MessageEntity(
        id: map['id'] as String,
        sessionId: map['session_id'] as String,
        role: map['role'] as String,
        content: map['content'] as String,
        attachmentType: map['attachment_type'] as String?,
        attachmentPath: map['attachment_path'] as String?,
        createdAt: map['created_at'] as int,
      );
}
