/// 数据 Tab（职管家 · 个人职业版）
///
/// 顶部：实名认证信息卡片（已认证显示姓名/年龄/性别，未认证引导去认证）
/// 下方（自上而下）：自我评价 → 学历教育 / 工作经历 / 技能培训 →
/// 自主学习 → 对话记忆，点开进入各自详情页；
/// 卡片右侧显示已填条数 / 填写状态，空则留白。
///
/// **宽度口径**：本页滚动容器不带左右内边距，所有卡片（含顶部认证卡）
/// 一律使用 [kCardMargin]，与发现页、首页保持同一宽度。
/// 注意：本页不自带 AppBar，顶栏「数据」标题由 ShellPage 统一提供，避免重复。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../common/plain_group.dart';
import '../data/experience_list_page.dart';
import '../data/experience_models.dart';
import '../data/experience_store.dart';
import '../data/memory_detail_page.dart';
import '../data/self_evaluation_page.dart';
import '../data/self_evaluation_store.dart';
import '../data/study_output_list_page.dart';
import '../data/study_output_store.dart';
import '../personal/personal_auth_service.dart';
import '../personal/personal_model.dart';
import '../personal/personal_verify_page.dart';
import '../storage/memory_store.dart';

/// 品牌活力橙（与 App 图标主色一致）
const Color _kBrandOrange = Color(0xFFFD5C13);
const Color _kBrandOrangeLight = Color(0xFFFF7A3D);

class DatabaseTab extends StatefulWidget {
  const DatabaseTab({super.key});

  @override
  State<DatabaseTab> createState() => DatabaseTabState();
}

class DatabaseTabState extends State<DatabaseTab> {
  PersonalAuth? _auth;
  bool _loading = true;

  /// 三类经历的条数（通栏卡片右侧显示「N 条」，为 0 时留白）
  Map<String, int> _counts = const {};

  /// 自我评价文本（为空表示未填写，卡片右侧显示「已填写」）
  String _selfEvaluation = '';

  /// 自主学习成果条数（同经历规则，为 0 时留白）
  int _studyCount = 0;

  /// 对话记忆条数（同规则，为 0 时留白）
  int _memoryCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = await PersonalAuthService.getAuth();
    final counts = await ExperienceStore.counts();
    final selfEvaluation = await SelfEvaluationStore.load();
    final studyCount = await StudyOutputStore.count();
    if (mounted) {
      setState(() {
        _auth = auth;
        _counts = counts;
        _selfEvaluation = selfEvaluation;
        _studyCount = studyCount;
        _loading = false;
      });
    }
    // 对话记忆条数要读磁盘（MD 文件），单独异步刷新：
    // 不拖住首屏渲染，失败也不影响页面其它内容。
    unawaited(_refreshMemoryCount(auth));
  }

  /// 刷新对话记忆条数（未登录 / 读取失败按 0 处理）
  Future<void> _refreshMemoryCount(PersonalAuth? auth) async {
    final phone = auth?.phone ?? '';
    if (phone.isEmpty) return;
    try {
      final list = await MemoryStore.listAll(phone);
      if (mounted) setState(() => _memoryCount = list.length);
    } catch (_) {
      // 读取失败保持原值（多为 0），不打扰用户
    }
  }

  /// 供主框架在切到本页时调用刷新（认证返回后也能立即更新）
  void refresh() => _load();

  /// 进入某类经历的详情页，返回后刷新条数
  Future<void> _openExperience(ExperienceKind kind) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ExperienceListPage(kind: kind)),
    );
    await _load();
  }

  /// 进入自我评价页，返回后刷新填写状态
  Future<void> _openSelfEvaluation() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const SelfEvaluationPage()),
    );
    await _load();
  }

  /// 进入自主学习成果页，返回后刷新条数
  Future<void> _openStudyOutputs() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const StudyOutputListPage()),
    );
    await _load();
  }

  /// 进入对话记忆详情页，返回后刷新条数
  Future<void> _openMemory() async {
    final phone = _auth?.phone ?? '';
    if (phone.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => MemoryDetailPage(tenantId: phone)),
    );
    await _load();
  }

  /// 由出生日期（yyyy-MM-dd）计算周岁
  int _ageOf(String birthday) {
    try {
      final p = birthday.split('-');
      final birth = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
      final now = DateTime.now();
      var age = now.year - birth.year;
      if (now.month < birth.month ||
          (now.month == birth.month && now.day < birth.day)) {
        age--;
      }
      return age < 0 ? 0 : age;
    } catch (_) {
      return 0;
    }
  }

  /// 跳转实名认证页，返回后刷新
  Future<void> _goVerify() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PersonalVerifyPage()),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: ListView(
          // 左右不留内边距：宽度由各卡片自己的 kCardMargin 统一决定
          padding: const EdgeInsets.only(top: 12, bottom: 16),
          children: [
            if (_loading) const SizedBox(height: 92) else _buildIdentityCard(),
            const SizedBox(height: 16),
            _buildSelfEvaluationGroup(),
            const SizedBox(height: 12),
            _buildExperienceGroups(),
            const SizedBox(height: 12),
            _buildStudyOutputGroup(),
            const SizedBox(height: 12),
            _buildMemoryGroup(),
          ],
        ),
      ),
    );
  }

  /// 自我评价卡片（实名认证卡下方，独立成卡）
  Widget _buildSelfEvaluationGroup() {
    return PlainGroup(
      entries: [
        PlainGroupEntry(
          icon: Icons.rate_review_outlined,
          color: const Color(0xFFF59E0B),
          label: '自我评价',
          trailingText: _selfEvaluation.isEmpty ? '' : '已填写',
          onTap: _openSelfEvaluation,
        ),
      ],
    );
  }

  /// 自主学习成果卡片（技能培训卡下方，独立成卡）
  Widget _buildStudyOutputGroup() {
    return PlainGroup(
      entries: [
        PlainGroupEntry(
          icon: Icons.science_outlined,
          color: const Color(0xFF0EA5E9),
          label: '自主学习',
          trailingText: _studyCount > 0 ? '$_studyCount 条' : '',
          onTap: _openStudyOutputs,
        ),
      ],
    );
  }

  /// 对话记忆卡片（与经历卡同一套通栏样式，独立成卡）
  Widget _buildMemoryGroup() {
    return PlainGroup(
      entries: [
        PlainGroupEntry(
          icon: Icons.forum_outlined,
          color: const Color(0xFF8B5CF6),
          label: '对话记忆',
          trailingText: _memoryCount > 0 ? '$_memoryCount 条' : '',
          onTap: _openMemory,
        ),
      ],
    );
  }

  /// 职业经历通栏卡片（教育 / 工作 / 培训，各自独立成卡，与发现页同一套通栏样式）
  Widget _buildExperienceGroups() {
    return Column(
      children: [
        for (var i = 0; i < ExperienceKind.all.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          PlainGroup(
            entries: [
              PlainGroupEntry(
                icon: ExperienceKind.all[i].icon,
                color: ExperienceKind.all[i].color,
                label: ExperienceKind.all[i].label,
                trailingText: _countText(ExperienceKind.all[i]),
                onTap: () => _openExperience(ExperienceKind.all[i]),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// 条数文案：为 0 时留白（避免满屏「0 条」噪音）
  String _countText(ExperienceKind kind) {
    final n = _counts[kind.id] ?? 0;
    return n > 0 ? '$n 条' : '';
  }

  /// 顶部实名信息卡片
  Widget _buildIdentityCard() {
    final auth = _auth;
    final verified = auth != null && auth.isVerified;
    return verified ? _buildVerifiedCard(auth) : _buildUnverifiedCard();
  }

  /// 已认证：姓名 / 年龄 / 性别
  Widget _buildVerifiedCard(PersonalAuth auth) {
    final age = _ageOf(auth.birthday);
    return Container(
      margin: kCardMargin,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [_kBrandOrangeLight, _kBrandOrange],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.22),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person, size: 30, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        auth.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified, size: 12, color: Colors.white),
                          SizedBox(width: 3),
                          Text(
                            '已认证',
                            style: TextStyle(fontSize: 11, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '年龄 $age岁　·　性别 ${auth.gender}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.88),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 未认证：提示 + 引导去认证
  Widget _buildUnverifiedCard() {
    return Container(
      margin: kCardMargin,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [_kBrandOrangeLight, _kBrandOrange],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.22),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.how_to_reg, size: 28, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '你还尚未通过实名认证',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '完成认证后可获得更精准的职业管家服务',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.85),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _goVerify,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '去认证',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _kBrandOrange,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
