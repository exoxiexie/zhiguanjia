/// 数据 Tab（职管家 · 个人职业版）
///
/// 顶部：实名认证信息卡片（已认证显示姓名/年龄/性别，未认证引导去认证）
/// 下方：三张职业经历通栏卡片（教育 / 工作 / 培训），点开进入各自的详情页；
/// 卡片右侧显示已填条数，空则留白。
/// 注意：本页不自带 AppBar，顶栏「数据」标题由 ShellPage 统一提供，避免重复。
library;

import 'package:flutter/material.dart';

import '../common/plain_group.dart';
import '../data/experience_list_page.dart';
import '../data/experience_models.dart';
import '../data/experience_store.dart';
import '../personal/personal_auth_service.dart';
import '../personal/personal_model.dart';
import '../personal/personal_verify_page.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = await PersonalAuthService.getAuth();
    final counts = await ExperienceStore.counts();
    if (mounted) {
      setState(() {
        _auth = auth;
        _counts = counts;
        _loading = false;
      });
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
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          children: [
            if (_loading) const SizedBox(height: 92) else _buildIdentityCard(),
            const SizedBox(height: 16),
            _buildExperienceGroups(),
          ],
        ),
      ),
    );
  }

  /// 三张职业经历通栏卡片（各自独立成卡，与发现页同一套通栏样式）
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
