/// 我的 Tab · 个人信息 + 实名认证 + 退出登录 + 检查更新（职管家）
///
/// 本页只通过 [PersonalAuthService] / [UpdateService] 契约执行动作，
/// 不接触存储 / 网络实现细节；具体实现由外部注入或默认装配。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../chat/session_reset.dart';
import '../app/app_config_service.dart';
import '../app/settings_page.dart';
import '../app/test_panel_page.dart';
import '../common/plain_group.dart';
import '../data/favorite_store.dart';
import '../data/favorites_page.dart';
import '../personal/avatar_store.dart';
import '../personal/personal_auth_service.dart';
import '../personal/personal_login_page.dart';
import '../personal/personal_model.dart';
import '../personal/personal_verify_page.dart';
import '../personal/user_avatar.dart';

/// 头像图片选择回调（可注入，便于测试；默认走 image_picker）
typedef AvatarPickFn = Future<String?> Function(ImageSource source);

/// 默认头像选择实现：调用系统相机 / 相册，返回所选图片的临时路径
Future<String?> defaultPickAvatar(ImageSource source) async {
  final picked = await ImagePicker().pickImage(
    source: source,
    maxWidth: 800,
    maxHeight: 800,
    imageQuality: 85,
  );
  return picked?.path;
}

class ProfileTab extends StatefulWidget {
  /// 头像选择器（默认使用 image_picker 的相机 / 相册；测试可注入假实现）
  final AvatarPickFn? avatarPicker;

  const ProfileTab({super.key, this.avatarPicker});

  @override
  State<ProfileTab> createState() => ProfileTabState();
}

class ProfileTabState extends State<ProfileTab> {
  late Future<PersonalAuth?> _authFuture;

  /// 收藏条数（我的页「收藏」卡右侧显示；异步加载，不阻塞首屏）
  int? _favCount;

  /// 测试入口是否可见（服务端下发开关；正式用户默认隐藏）
  bool _testPanelVisible = false;

  @override
  void initState() {
    super.initState();
    _authFuture = PersonalAuthService.getAuth();
    unawaited(_loadFavCount());
    unawaited(_loadTestPanelVisibility());
  }

  /// 重新加载登录态（实名认证返回后刷新卡片）
  void _refreshAuth() {
    setState(() {
      _authFuture = PersonalAuthService.getAuth();
    });
  }

  /// 供主框架在切到本页时调用刷新
  ///
  /// 本页常驻在 ShellPage 的 IndexedStack 中，initState 只执行一次；
  /// 若用户在「数据」页完成实名认证，本页不会重建，必须由外部触发刷新，
  /// 否则会出现「已认证但我的页仍显示未认证」。
  void refresh() {
    if (mounted) _refreshAuth();
  }

  /// 加载收藏条数（异步，不阻塞首屏）
  /// 「测试」入口是否显示：由服务端 flags 控制（灰度），正式用户默认隐藏
  Future<void> _loadTestPanelVisibility() async {
    final auth = await PersonalAuthService.getAuth();
    if (AppConfigService.cachedConfig == null) {
      // 冷启动离线时可能还没拿到配置：补一次，拿到后刷新入口
      await AppConfigService.check();
    }
    if (!mounted) return;
    setState(() {
      _testPanelVisible = AppConfigService.testPanelVisible(auth?.phone ?? '');
    });
  }

  Future<void> _loadFavCount() async {
    final n = await FavoriteStore.count();
    if (mounted) setState(() => _favCount = n);
  }

  /// 打开收藏列表页；返回后刷新收藏条数
  Future<void> _openFavorites() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FavoritesPage()),
    );
    unawaited(_loadFavCount());
  }

  /// 头像选择实现（默认 image_picker）
  AvatarPickFn get _pickAvatar => widget.avatarPicker ?? defaultPickAvatar;

  /// 点击头像：弹出「拍照 / 从相册选择 / 移除头像」
  Future<void> _showAvatarSheet() async {
    final auth = await PersonalAuthService.getAuth();
    if (!mounted || auth == null) return;
    final hasAvatar = auth.avatarPath.isNotEmpty;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                '更换头像',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1B1C),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: Color(0xFF5B7FD4)),
              title: const Text('拍照'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSaveAvatar(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: Color(0xFF5B7FD4)),
              title: const Text('从相册选择'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSaveAvatar(ImageSource.gallery);
              },
            ),
            if (hasAvatar)
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                title: const Text('移除头像',
                    style: TextStyle(color: Color(0xFFEF4444))),
                onTap: () {
                  Navigator.pop(ctx);
                  _removeAvatar();
                },
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  /// 选图 → 复制进私有目录 → 写入用户档案与登录态 → 刷新界面
  Future<void> _pickAndSaveAvatar(ImageSource source) async {
    final auth = await PersonalAuthService.getAuth();
    if (auth == null) return;
    try {
      // image_picker 返回的是系统临时缓存路径，必须复制进私有目录长期保存
      final sourcePath = await _pickAvatar(source);
      if (sourcePath == null) return; // 用户取消
      final savedPath =
          await AvatarStore.save(phone: auth.phone, sourcePath: sourcePath);
      final result = await PersonalAuthService.updateAvatar(
        phone: auth.phone,
        avatarPath: savedPath,
      );
      if (!mounted) return;
      if (result['ok'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${result['error'] ?? '头像更新失败'}')),
        );
        return;
      }
      _refreshAuth();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('头像已更新')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('头像更新失败：$e')),
      );
    }
  }

  /// 移除头像（删除文件 + 清空档案字段，回落默认图标）
  Future<void> _removeAvatar() async {
    final auth = await PersonalAuthService.getAuth();
    if (auth == null) return;
    await AvatarStore.remove(auth.phone);
    await PersonalAuthService.updateAvatar(phone: auth.phone, avatarPath: '');
    if (!mounted) return;
    _refreshAuth();
  }

  /// P5：导出账号数据（服务端打包 JSON → 写入本机文件 → 可打开查看）
  Future<void> _logout(BuildContext context) async {
    // 【P0-1 / P0-2】先重置进程级单例里的账号态，再清登录态。
    // 顺序不能反：服务容器不会随退出登录自动清空，若不先重置，
    // 下一个账号（本机无历史会话）会直接读到上一个账号的会话与消息。
    resetUserSessionState();
    await PersonalAuthService.clearAuth();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PersonalLoginPage()),
      (route) => false,
    );
  }

  /// 打开实名认证页
  Future<void> _openVerify() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => PersonalVerifyPage(onVerified: _refreshAuth)),
    );
    _refreshAuth();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PersonalAuth?>(
      future: _authFuture,
      builder: (context, snap) {
        final auth = snap.data;
        final verified = auth?.isVerified ?? false;

        return Scaffold(
          backgroundColor: const Color(0xFFF5F5F5),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 12),
              children: [
                // === 顶部个人信息卡片（浅色） ===
                Container(
                  margin: kCardMargin,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F5FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      // 用户头像（圆形，点击可更换）
                      GestureDetector(
                        onTap: _showAvatarSheet,
                        behavior: HitTestBehavior.opaque,
                        child: UserAvatar(
                          avatarPath: auth?.avatarPath ?? '',
                          name: auth?.name ?? '',
                          seed: auth?.phone ?? '',
                          size: 56,
                          editable: true,
                        ),
                      ),
                      const SizedBox(width: 14),
                      // 个人信息
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 第一行：姓名 + 实名状态标签
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    auth?.name ?? '未登录',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1A1B1C),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: verified
                                        ? const Color(0xFF10B981)
                                            .withOpacity(0.1)
                                        : const Color(0xFFF59E0B)
                                            .withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    verified ? '已实名' : '未认证',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: verified
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFFD97706),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            // 第二行：脱敏身份证号（含性别）或认证提示
                            Text(
                              verified
                                  ? '${auth!.maskedIdCard}${auth.gender.isNotEmpty ? ' · ${auth.gender}' : ''}'
                                  : '点击下方「实名认证」完善职业身份档案',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7280),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // === 收藏（收拢所有收藏的 AI 输出） ===
                _buildGroup([
                  _ListItem(
                    icon: Icons.star_outline_rounded,
                    iconColor: const Color(0xFFF59E0B),
                    title: '收藏',
                    subtitle: _favCount == null
                        ? '收拢你收藏的 AI 输出'
                        : '$_favCount 条收藏',
                    onTap: _openFavorites,
                  ),
                ]),
                const SizedBox(height: 12),

                // === 功能列表（仅登录后显示） ===
                if (auth != null) ...[
                  // 分组：实名认证（未认证时显示，已认证则展示认证详情）
                  if (!verified) ...[
                    _buildGroup([
                      _ListItem(
                        icon: Icons.verified_user_outlined,
                        iconColor: const Color(0xFFF59E0B),
                        title: '实名认证',
                        subtitle: '认证后建立完整职业身份档案',
                        onTap: _openVerify,
                      ),
                    ]),
                    const SizedBox(height: 12),
                  ] else ...[
                    _buildGroup([
                      _ListItem(
                        icon: Icons.badge_outlined,
                        iconColor: const Color(0xFF10B981),
                        title: '实名信息',
                        subtitle:
                            '${auth.maskedIdCard}${auth.province.isNotEmpty ? ' · ${auth.province}' : ''}',
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('你已完成实名认证')),
                          );
                        },
                      ),
                    ]),
                    const SizedBox(height: 12),
                  ],

                  // 分组：设置 / 测试（通栏入口，具体条目在各自页面里维护）
                  _buildGroup([
                    _ListItem(
                      icon: Icons.settings_outlined,
                      iconColor: const Color(0xFF6B7280),
                      title: '设置',
                      subtitle: '检查更新 · 导出数据 · 账号注销',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const SettingsPage()),
                      ),
                    ),
                    // 测试入口：仅灰度/开发可见，正式用户不显示（避免体验突兀）
                    if (_testPanelVisible)
                      _ListItem(
                        icon: Icons.science_outlined,
                        iconColor: const Color(0xFF7C3AED),
                        title: '测试',
                        subtitle: '诊断与灰度功能（正式用户不可见）',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => const TestPanelPage()),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 24),

                  // 退出登录
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: TextButton(
                        onPressed: () => _logout(context),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFFD05656),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('退出登录',
                            style: TextStyle(
                                fontSize: 16, color: Color(0xFFD05656))),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// 构建一个白色圆角分组卡片
  Widget _buildGroup(List<Widget> items) {
    return Container(
      margin: kCardMargin,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            items[i],
            if (i < items.length - 1)
              const Padding(
                padding: EdgeInsets.only(left: 56),
                child: Divider(height: 1, color: Color(0xFFF0F0F0)),
              ),
          ],
        ],
      ),
    );
  }
}

/// 微信风格列表项：左边图标+标题，右边箭头
class _ListItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const _ListItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15, color: Color(0xFF1A1B1C))),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF9CA3AF))),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
            if (trailing == null)
              const Icon(Icons.chevron_right,
                  size: 20, color: Color(0xFFC0C0C0)),
          ],
        ),
      ),
    );
  }
}
