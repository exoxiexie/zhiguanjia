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

  static DateTime? _lastPullAt;
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
  /// ⚠️ **只允许 HTTPS 调用**：本接口传输完整身份证号。
  /// 备案前业务 API 是 HTTP，此时保持"实名只存本机"，
  /// 待域名备案通过、`apiBaseUrl` 切成 https 后由调用方自动启用。
  static Future<void> pushIdentity({
    required String idCard,
    required String realName,
    String gender = '',
    String birthday = '',
    String province = '',
  }) async {
    if (!await _canSync()) return;
    try {
      await _api.saveIdentity(
        idCard: idCard,
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
    if (!await _canSync()) return false;
    if (_pulling) return false;
    if (!force &&
        _lastPullAt != null &&
        DateTime.now().difference(_lastPullAt!) < minPullInterval) {
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
      _lastPullAt = DateTime.now();
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

  /// 仅测试使用：清空节流与进行中标记
  @visibleForTesting
  static void resetForTest() {
    _lastPullAt = null;
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
