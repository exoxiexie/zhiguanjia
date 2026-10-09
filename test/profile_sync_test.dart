/// 职业档案同步层测试（P2）
///
/// 覆盖最容易出错的路径：
/// 1. 本地保存后**确实推送**服务端（字段映射正确）
/// 2. 拉取把云端数据写入本地缓存（换手机后档案自动出现的关键）
/// 3. 推送失败 / 拉取失败**不抛异常、不破坏本地数据**（离线可用）
/// 4. 未登录时**不上云**（游客数据留在本机）
/// 5. 节流：短时间内重复拉取只请求一次（避免切页狂发请求）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhiguanjia/contracts/auth_api.dart';
import 'package:zhiguanjia/contracts/profile_api.dart';
import 'package:zhiguanjia/features/data/basic_info_store.dart';
import 'package:zhiguanjia/features/data/experience_models.dart';
import 'package:zhiguanjia/features/data/experience_store.dart';
import 'package:zhiguanjia/features/data/profile_sync.dart';
import 'package:zhiguanjia/features/data/self_evaluation_store.dart';

/// 假接口：记录调用 + 可配置成功/失败
class FakeProfileApi implements ProfileApi {
  int fetchCalls = 0;
  Map<String, dynamic>? lastBasic;
  String? lastEvaluation;
  ExperienceDto? lastUpsert;
  String? lastDeleted;
  bool online = true;
  ProfileBundle bundle = const ProfileBundle();

  ApiError get _offline => const ApiError(
      statusCode: 0, code: 'network', message: '无法连接服务器，请检查网络后重试');

  @override
  Future<ApiResult<ProfileBundle>> fetch() async {
    fetchCalls++;
    if (!online) return ApiResult.failure(_offline);
    return ApiResult.success(bundle);
  }

  @override
  Future<ApiResult<bool>> saveBasic(Map<String, dynamic> basic) async {
    if (!online) return ApiResult.failure(_offline);
    lastBasic = basic;
    return const ApiResult.success(true);
  }

  @override
  Future<ApiResult<bool>> saveSelfEvaluation(String content) async {
    if (!online) return ApiResult.failure(_offline);
    lastEvaluation = content;
    return const ApiResult.success(true);
  }

  @override
  Future<ApiResult<bool>> upsertExperience(ExperienceDto dto) async {
    if (!online) return ApiResult.failure(_offline);
    lastUpsert = dto;
    return const ApiResult.success(true);
  }

  @override
  Future<ApiResult<bool>> deleteExperience(String id) async {
    if (!online) return ApiResult.failure(_offline);
    lastDeleted = id;
    return const ApiResult.success(true);
  }

  @override
  Future<ApiResult<bool>> saveIdentity({
    required String idCard,
    required String realName,
    String gender = '',
    String birthday = '',
    String province = '',
  }) async =>
      const ApiResult.success(true);
}

const String _phone = '13800001111';

/// 预置登录态（同步层只在已登录时才上云）
void _seedLoggedIn() {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'zhiguanjia.personal.auth':
        '{"token":"t","phone":"$_phone","name":"测试","idCard":"","gender":"","birthday":"","province":"","verifiedAt":"","avatarPath":""}',
  });
}

void main() {
  late FakeProfileApi api;

  setUp(() {
    api = FakeProfileApi();
    ProfileSync.apiForTest = api;
    ProfileSync.resetForTest();
  });

  test('保存基础信息：本地落盘 + 推送服务端（字段映射正确）', () async {
    _seedLoggedIn();

    await BasicInfoStore.save(const BasicInfo(
      province: '四川省',
      city: '成都市',
      district: '武侯区',
      address: '科技园路 1 号',
      workStatus: WorkStatus.employed,
      maritalStatus: MaritalStatus.single,
    ));

    // 本地立即可读（离线可用）
    final local = await BasicInfoStore.load();
    expect(local.province, '四川省');
    expect(local.address, '科技园路 1 号');

    // 已推送，且线上字段名/枚举值正确
    expect(api.lastBasic, isNotNull);
    expect(api.lastBasic!['province'], '四川省');
    expect(api.lastBasic!['address'], '科技园路 1 号');
    expect(api.lastBasic!['work_status'], 'employed');
    expect(api.lastBasic!['marital_status'], isNotNull);
  });

  test('保存自我评价：本地落盘 + 推送', () async {
    _seedLoggedIn();

    await SelfEvaluationStore.save('十年产品经验');
    expect(await SelfEvaluationStore.load(), '十年产品经验');
    expect(api.lastEvaluation, '十年产品经验');

    await SelfEvaluationStore.save('   ');
    expect(await SelfEvaluationStore.load(), '');
    expect(api.lastEvaluation, '');
  });

  test('经历保存与删除：本地生效 + 推送（含字段映射）', () async {
    _seedLoggedIn();

    const entry = ExperienceEntry(
      id: 'exp-1',
      kindId: 'work',
      values: {'company': '某某科技', 'title': '产品经理'},
      createdAt: 1000,
      updatedAt: 2000,
    );
    await ExperienceStore.save(entry);

    expect((await ExperienceStore.listByKind('work')).length, 1);
    expect(api.lastUpsert, isNotNull);
    expect(api.lastUpsert!.id, 'exp-1');
    expect(api.lastUpsert!.kindId, 'work');
    expect(api.lastUpsert!.values['company'], '某某科技');
    expect(api.lastUpsert!.updatedAt, 2000);

    await ExperienceStore.delete('exp-1');
    expect(await ExperienceStore.listByKind('work'), isEmpty);
    expect(api.lastDeleted, 'exp-1');
  });

  test('拉取：把云端档案写入本地缓存（换手机后档案自动出现）', () async {
    _seedLoggedIn();
    api.bundle = const ProfileBundle(
      basic: {
        'province': '广东省',
        'city': '深圳市',
        'district': '南山区',
        'address': '科技南路 9 号',
        'work_status': 'resigned',
        'marital_status': 'married',
      },
      selfEvaluation: '云端自我评价',
      experiences: [
        ExperienceDto(
          id: 'cloud-exp-1',
          kindId: 'education',
          values: {'school': '某大学'},
          createdAt: 10,
          updatedAt: 20,
        ),
      ],
    );

    final ok = await ProfileSync.pull(force: true);

    expect(ok, isTrue);
    final basic = await BasicInfoStore.load();
    expect(basic.province, '广东省');
    expect(basic.workStatus, WorkStatus.resigned);
    expect(await SelfEvaluationStore.load(), '云端自我评价');
    final exps = await ExperienceStore.listByKind('education');
    expect(exps.length, 1);
    expect(exps.first.values['school'], '某大学');
  });

  test('离线时：推送失败不抛异常，本地数据保留', () async {
    _seedLoggedIn();
    api.online = false;

    await BasicInfoStore.save(const BasicInfo(province: '四川省', address: '本地地址'));
    await SelfEvaluationStore.save('离线写的评价');

    // 本地数据必须还在（离线可用）
    final basic = await BasicInfoStore.load();
    expect(basic.province, '四川省');
    expect(await SelfEvaluationStore.load(), '离线写的评价');
    // 没推送成功
    expect(api.lastBasic, isNull);
  });

  test('离线时：拉取失败返回 false，不清空本地缓存', () async {
    _seedLoggedIn();
    await BasicInfoStore.save(const BasicInfo(province: '四川省'));
    api.online = false;

    final ok = await ProfileSync.pull(force: true);

    expect(ok, isFalse);
    expect((await BasicInfoStore.load()).province, '四川省',
        reason: '拉取失败不得清空本地已有数据');
  });

  test('未登录（游客）时不上云', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await BasicInfoStore.save(const BasicInfo(province: '四川省'));
    await SelfEvaluationStore.save('游客评价');
    await ProfileSync.pull(force: true);

    expect(api.lastBasic, isNull, reason: '游客数据不应上云');
    expect(api.lastEvaluation, isNull);
    expect(api.fetchCalls, 0);
  });

  test('节流：短时间内重复拉取只请求一次', () async {
    _seedLoggedIn();
    api.bundle = const ProfileBundle(basic: {'province': '四川省'});

    await ProfileSync.pull(force: true);
    await ProfileSync.pullIfNeeded();
    await ProfileSync.pullIfNeeded();

    expect(api.fetchCalls, 1, reason: '90 秒内不应重复请求');

    await ProfileSync.pull(force: true);
    expect(api.fetchCalls, 2, reason: 'force 应忽略节流');
  });
}
