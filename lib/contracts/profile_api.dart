/// 职业档案 API 契约（P2 · 档案云化）
///
/// 覆盖范围：基础信息、自我评价、职业经历（教育/工作/培训）、实名认证。
/// 同步策略见《商业版改造方案》第五节 A 类「档案类」：**服务端为准 + 本地缓存**，
/// 因此接口只需「读全量 / 写单点」，不存在双向合并的复杂度。
library;

import 'auth_api.dart';

/// 一条职业经历（与 App 端 ExperienceEntry 的语义一致，字段值与线上线下一一对应）
class ExperienceDto {
  final String id;
  final String kindId;
  final Map<String, String> values;
  final int createdAt;
  final int updatedAt;

  const ExperienceDto({
    required this.id,
    required this.kindId,
    required this.values,
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  factory ExperienceDto.fromWire(Map<String, dynamic> json) => ExperienceDto(
        id: json['id']?.toString() ?? '',
        kindId: json['kind_id']?.toString() ?? '',
        values: {
          for (final e in ((json['values'] as Map?) ?? const <String, dynamic>{})
              .entries)
            e.key.toString(): e.value?.toString() ?? '',
        },
        createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
        updatedAt: (json['updated_at'] as num?)?.toInt() ?? 0,
      );
}

/// 一份完整档案（一次请求拉全，减少首屏往返）
class ProfileBundle {
  /// 基础信息（线上字段名，见 [ProfileApi.saveBasic]）
  final Map<String, dynamic> basic;

  /// 自我评价
  final String selfEvaluation;

  /// 全部职业经历
  final List<ExperienceDto> experiences;

  /// 服务端用户资料（含脱敏身份证号与实名状态，用于换设备后恢复"已认证"）
  final Map<String, dynamic> user;

  const ProfileBundle({
    this.basic = const {},
    this.selfEvaluation = '',
    this.experiences = const [],
    this.user = const {},
  });

  factory ProfileBundle.fromWire(Map<String, dynamic> json) => ProfileBundle(
        basic: ((json['basic'] as Map?) ?? const {}).cast<String, dynamic>(),
        selfEvaluation: json['self_evaluation']?.toString() ?? '',
        experiences: [
          for (final e in (json['experiences'] as List? ?? const []))
            ExperienceDto.fromWire((e as Map).cast<String, dynamic>()),
        ],
        user: ((json['user'] as Map?) ?? const {}).cast<String, dynamic>(),
      );
}

/// 职业档案接口
abstract class ProfileApi {
  /// 拉取整份档案
  Future<ApiResult<ProfileBundle>> fetch();

  /// 保存基础信息
  ///
  /// 线上字段名：`province` / `city` / `district` / `address` /
  /// `work_status` / `marital_status`（枚举值沿用 App 端的枚举名，如 employed）
  Future<ApiResult<bool>> saveBasic(Map<String, dynamic> basic);

  /// 保存自我评价（传空串即清空）
  Future<ApiResult<bool>> saveSelfEvaluation(String content);

  /// 新增或更新一条经历（按 id 幂等）
  Future<ApiResult<bool>> upsertExperience(ExperienceDto dto);

  /// 删除一条经历
  Future<ApiResult<bool>> deleteExperience(String id);

  /// 实名认证
  ///
  /// **只上传脱敏号与 SHA-256 哈希**：完整身份证号永不出客户端，
  /// 服务端用哈希查重、用脱敏号展示。
  Future<ApiResult<bool>> saveIdentity({
    required String idCardMasked,
    required String idCardHash,
    required String realName,
    String gender = '',
    String birthday = '',
    String province = '',
  });
}
