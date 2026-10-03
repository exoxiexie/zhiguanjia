/// 会话实体（对应 sessions 表）
class SessionEntity {
  final String id;
  final String tenantId; // 个人手机号（租户ID）
  final String title;
  final int createdAt; // 毫秒时间戳
  final int updatedAt; // 毫秒时间戳
  final int messageCount;
  final String? lastExtractedMessageId; // 最后一次提炼时的消息ID（用于增量提炼）
  final String? createdBy; // 创建该会话的管理员手机号
  final String? businessTag; // 业务智能体标签（null=通用对话）

  const SessionEntity({
    required this.id,
    required this.tenantId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.messageCount = 0,
    this.lastExtractedMessageId,
    this.createdBy,
    this.businessTag,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'tenant_id': tenantId,
        'title': title,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'message_count': messageCount,
        'last_extracted_message_id': lastExtractedMessageId,
        'created_by': createdBy,
        'business_tag': businessTag,
      };

  factory SessionEntity.fromMap(Map<String, dynamic> map) => SessionEntity(
        id: map['id'] as String,
        tenantId: map['tenant_id'] as String,
        title: map['title'] as String,
        createdAt: map['created_at'] as int,
        updatedAt: map['updated_at'] as int,
        messageCount: map['message_count'] as int? ?? 0,
        lastExtractedMessageId: map['last_extracted_message_id'] as String?,
        createdBy: map['created_by'] as String?,
        businessTag: map['business_tag'] as String?,
      );

  SessionEntity copyWith({
    String? title,
    int? updatedAt,
    int? messageCount,
    String? lastExtractedMessageId,
    String? createdBy,
  }) =>
      SessionEntity(
        id: id,
        tenantId: tenantId,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        messageCount: messageCount ?? this.messageCount,
        lastExtractedMessageId: lastExtractedMessageId ?? this.lastExtractedMessageId,
        createdBy: createdBy ?? this.createdBy,
      );
}
