/// 职业档案同步层（P2）
///
/// 策略（《商业版改造方案》第五节 A 类「档案类」）：**服务端为准 + 本地缓存**
///
/// - 写：先落本地（离线也能立刻看到效果）→ 再尽力推送服务端；推送失败静默，
///   下次拉取时以服务端为准覆盖（不引入合并复杂度）。
/// - 读：本地缓存随时可读（离线可用）；进入数据页时**节流拉取**一次云端全量，
///   保证换手机后档案自动出现、多设备改动能及时看到。
///
/// 设计取舍：不做 outbox 队列（那是 C 类「对话类」才需要的量级），
/// 档案类数据量小、以服务端为准即可；代价是"离线修改可能在下次拉取时被覆盖"，
/// 这在「同一份简历」的场景下是可接受的（同一时刻只有一个人改）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../contracts/profile_api.dart';
import '../api/profile_api_impl.dart';
import '../personal/id_card_util.dart';
import '../personal/personal_auth_service.dart';
import 'basic_info_store.dart';
import 'experience_models.dart';
import 'experience_store.dart';
import 'self_evaluation_store.dart';

class ProfileSync {
  /// 档案接口（契约类型，便于替换实现与单元测试）
  static ProfileApi _api = const HttpProfileApi();

  /// 测试注入口：替换接口实现（仅单元测试使用）
  @visibleForTesting
  static set apiForTest(ProfileApi value) => _api = value;

  /// 拉取节流：同一会话内 90 秒最多拉一次，避免切页反复请求
  static const Duration minPullInterval = Duration(seconds: 90);

  /// 单次拉取的硬超时：离线/弱网时不能把"进入数据页"卡住
  static const Duration pullTimeout = Duration(seconds: 6);

  /// 节流时间按账号记录（换账号后应立即同步）
  static final Map<String, DateTime> _lastPullAt = <String, DateTime>{};
  static bool _pulling = false;

  /// 是否处于可同步状态（未登录只是本机游客数据，不上云）
  static Future<bool> _canSync() async {
    final auth = await PersonalAuthService.getAuth();
    return auth != null && auth.phone.isNotEmpty;
  }

  // ────────────────────────── 推送（写） ──────────────────────────

  /// 推送基础信息
  static Future<void> pushBasic(BasicInfo info) async {
    if (!await _canSync()) return;
    try {
      await _api.saveBasic(<String, dynamic>{
        'province': info.province,
        'city': info.city,
        'district': info.district,
        'address': info.address,
        'work_status': info.workStatus?.name ?? '',
        'marital_status': info.maritalStatus?.name ?? '',
      });
    } catch (_) {
      // 静默：本地已保存，联网后拉取会以服务端为准
    }
  }

  /// 推送自我评价（空串即清空）
  static Future<void> pushSelfEvaluation(String text) async {
    if (!await _canSync()) return;
    try {
      await _api.saveSelfEvaluation(text.trim());
    } catch (_) {
      // 静默
    }
  }

  /// 推送一条经历（新增或更新）
  static Future<void> pushExperience(ExperienceEntry entry) async {
    if (!await _canSync()) return;
    try {
      await _api.upsertExperience(ExperienceDto(
        id: entry.id,
        kindId: entry.kindId,
        values: entry.values,
        createdAt: entry.createdAt,
        updatedAt: entry.updatedAt,
      ));
    } catch (_) {
      // 静默
    }
  }

  /// 推送删除一条经历
  static Future<void> pushDeleteExperience(String id) async {
    if (!await _canSync()) return;
    try {
      await _api.deleteExperience(id);
    } catch (_) {
      // 静默
    }
  }

  /// 推送实名认证
  ///
  /// **只上传脱敏号 + SHA-256 哈希**（完整身份证号永不出客户端），
  /// 因此不需要等 HTTPS：HTTP 下也不会泄漏证件号。
  static Future<void> pushIdentity({
    required String masked,
    required String hash,
    required String realName,
    String gender = '',
    String birthday = '',
    String province = '',
  }) async {
    if (!await _canSync()) return;
    try {
      await _api.saveIdentity(
        idCardMasked: masked,
        idCardHash: hash,
        realName: realName,
        gender: gender,
        birthday: birthday,
        province: province,
      );
    } catch (_) {
      // 静默
    }
  }

  // ────────────────────────── 拉取（读） ──────────────────────────

  /// 拉取云端档案并写入本地缓存。
  ///
  /// [force] 为 true 时忽略节流（登录后调用）。
  /// 返回 true 表示确实同步成功。任何网络问题都返回 false 且**保留本地缓存**。
  static Future<bool> pull({bool force = false}) async {
    final phone = (await PersonalAuthService.getAuth())?.phone ?? '';
    if (phone.isEmpty) return false;
    if (_pulling) return false;
    final last = _lastPullAt[phone];
    if (!force && last != null && DateTime.now().difference(last) < minPullInterval) {
      return false;
    }

    _pulling = true;
    try {
      final result = await _api.fetch().timeout(pullTimeout);
      if (!result.ok || result.data == null) return false;
      final bundle = result.data!;

      await BasicInfoStore.writeCache(_basicFromWire(bundle.basic));
      await SelfEvaluationStore.writeCache(bundle.selfEvaluation);
      await ExperienceStore.replaceCache(
        bundle.experiences.map(_entryFromDto).toList(),
      );

      final remoteUser = bundle.user;

      // S-1：本机已实名、服务端还没有 → 补推一次（v1.0.40 之前认证过的老账号）
      await _backfillIdentityIfNeeded(phone, remoteUser);

      // 实名状态回写：换设备后本机没有完整证件号，用服务端脱敏号占位，
      // 让「我的」页正确显示"已认证"（本机已有完整号时不覆盖）
      final masked = remoteUser['id_card_masked']?.toString() ?? '';
      if (remoteUser['is_verified'] == true && masked.isNotEmpty) {
        await PersonalAuthService.applyRemoteVerification(
          phone: phone,
          maskedIdCard: masked,
          verifiedAt: remoteUser['verified_at']?.toString() ?? '',
        );
      }

      _lastPullAt[phone] = DateTime.now();
      return true;
    } catch (_) {
      // 超时/离线：保留本地缓存，绝不阻塞用户
      return false;
    } finally {
      _pulling = false;
    }
  }

  /// 进入数据页时调用：节流 + 超时保护，失败静默
  static Future<void> pullIfNeeded() => pull();

  /// 登录后调用：强制拉取一次（忽略节流）
  static Future<void> pullOnLogin() => pull(force: true);

  /// 实名回填：本机存有**完整证件号**而服务端尚未实名时，补推一次
  ///
  /// 背景：`pushIdentity` 原本只在「重新做实名认证」时调用，
  /// 因此老账号的实名信息从未上传 —— 换设备后显示未认证（缺陷 S-1）。
  /// 幂等：服务端一旦标记已实名，后续同步不会再推。
  static Future<void> _backfillIdentityIfNeeded(
      String phone, Map<String, dynamic> remoteUser) async {
    final serverVerified = remoteUser['is_verified'] == true;
    final serverMasked = remoteUser['id_card_masked']?.toString() ?? '';
    if (serverVerified || serverMasked.isNotEmpty) return;

    final users = await PersonalAuthService.getUsers();
    final idx = users.indexWhere((u) => u.phone == phone);
    if (idx < 0) return;
    final local = users[idx];

    // 用权威校验区分「完整证件号」与「脱敏占位」：
    // 脱敏号含 * 校验必失败，因此不会被误当成真实证件号推上去
    final info = IdCardUtil.validate(local.idCard);
    if (!info.valid) return;

    final normalized = local.idCard.trim().toUpperCase();
    final birthday = info.birthday;
    final birthdayStr = birthday == null
        ? local.birthday
        : '${birthday.year.toString().padLeft(4, '0')}'
            '-${birthday.month.toString().padLeft(2, '0')}'
            '-${birthday.day.toString().padLeft(2, '0')}';

    await pushIdentity(
      masked: maskIdCard(normalized),
      hash: sha256IdCard(normalized),
      realName: local.name,
      gender: info.gender ?? local.gender,
      birthday: birthdayStr,
      province: info.province ?? local.province,
    );
  }

  /// 仅测试使用：清空节流与进行中标记
  @visibleForTesting
  static void resetForTest() {
    _lastPullAt.clear();
    _pulling = false;
  }

  // ────────────────────────── 线上 ↔ 本地字段映射 ──────────────────────────

  static BasicInfo _basicFromWire(Map<String, dynamic> wire) => BasicInfo(
        province: wire['province']?.toString() ?? '',
        city: wire['city']?.toString() ?? '',
        district: wire['district']?.toString() ?? '',
        address: wire['address']?.toString() ?? '',
        workStatus: WorkStatus.fromName(wire['work_status']?.toString()),
        maritalStatus:
            MaritalStatus.fromName(wire['marital_status']?.toString()),
      );

  static ExperienceEntry _entryFromDto(ExperienceDto dto) => ExperienceEntry(
        id: dto.id,
        kindId: dto.kindId,
        values: dto.values,
        createdAt: dto.createdAt,
        updatedAt: dto.updatedAt,
      );
}
