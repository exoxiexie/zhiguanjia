/// 我的 Tab · 个人信息 + 实名认证 + 退出登录 + 检查更新（职管家）
///
/// 本页只通过 [PersonalAuthService] / [UpdateService] 契约执行动作，
/// 不接触存储 / 网络实现细节；具体实现由外部注入或默认装配。
library;

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../../contracts/update_service.dart';
import '../personal/personal_auth_service.dart';
import '../personal/personal_login_page.dart';
import '../personal/personal_model.dart';
import '../personal/personal_verify_page.dart';
import '../update/update_service_impl.dart';

/// 更新服务器地址（多源：Gitee API 优先，GitHub 回退；均公网可访问）
/// Gitee 用 API 方式获取文件内容，避免 raw URL 302 重定向导致超时
const List<String> _kUpdateBaseUrls = [
  'https://gitee.com/api/v5/repos/laoxie2076/zhiguanjia/contents',
  'https://raw.githubusercontent.com/exoxiexie/zhiguanjia/main',
];

class ProfileTab extends StatefulWidget {
  final UpdateService? updateService;

  const ProfileTab({super.key, this.updateService});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  late Future<PersonalAuth?> _authFuture;
  bool _checking = false;
  bool _downloading = false;
  double _progress = 0;
  StateSetter? _setDialogState; // 用于更新下载进度对话框内部状态

  UpdateService get _updateSvc =>
      widget.updateService ?? HttpUpdateService(baseUrls: _kUpdateBaseUrls);

  @override
  void initState() {
    super.initState();
    _authFuture = PersonalAuthService.getAuth();
  }

  /// 重新加载登录态（实名认证返回后刷新卡片）
  void _refreshAuth() {
    setState(() {
      _authFuture = PersonalAuthService.getAuth();
    });
  }

  Future<void> _logout(BuildContext context) async {
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
      MaterialPageRoute(builder: (_) => PersonalVerifyPage(onVerified: _refreshAuth)),
    );
    _refreshAuth();
  }

  Future<void> _checkUpdate(BuildContext context) async {
    if (_checking || _downloading) return;
    setState(() => _checking = true);

    CheckResult result;
    try {
      result = await _updateSvc.checkForUpdate();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
    if (!mounted) return;

    if (result.hasUpdate && result.latest != null) {
      final info = result.latest!;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('发现新版本'),
          content: Text(
              '最新版本：${info.version}\n\n更新内容：\n${info.note.isEmpty ? '暂无' : info.note}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('立即更新')),
          ],
        ),
      );
      if (proceed == true) {
        await _downloadAndInstall(context, info);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message ?? '已是最新版本',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
  }

  Future<void> _downloadAndInstall(BuildContext context, UpdateInfo info) async {
    setState(() => _downloading = true);
    BuildContext? dialogRebuild;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogRebuild = ctx;
        return AlertDialog(
          title: const Text('正在下载更新'),
          content: StatefulBuilder(
            builder: (ctx, setDialogState) {
              _setDialogState = setDialogState; // 存起来，供 onProgress 回调使用
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_progress >= 0)
                    LinearProgressIndicator(value: _progress > 0 ? _progress / 100 : null)
                  else
                    const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  if (_progress >= 0)
                    Text('${_progress.toStringAsFixed(0)}%')
                  else
                    Text('已下载 ${(_progress.abs() / 1024 / 1024).toStringAsFixed(1)} MB'),
                ],
              );
            },
          ),
        );
      },
    );

    try {
      final path = await _updateSvc.download(
        info.url,
        onProgress: (p) {
          // 用 setDialogState 更新对话框内部 UI（setState 不会触发 StatefulBuilder 重建）
          _setDialogState?.call(() {
            if (p >= 0) {
              _progress = p * 100; // 已知总大小：百分比
            } else {
              _progress = p; // 未知总大小：已下载字节数（负数标识）
            }
          });
        },
      );
      if (dialogRebuild != null && dialogRebuild!.mounted) {
        Navigator.of(dialogRebuild!).pop();
      }
      if (!mounted) return;
      setState(() => _downloading = false);

      final r = await OpenFilex.open(path);
      final ok = r.type == ResultType.done;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? '下载完成，请在系统安装界面确认安装' : '下载完成，但打开安装器失败（${r.message}）'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloading = false);
      if (dialogRebuild != null && dialogRebuild!.mounted) {
        Navigator.of(dialogRebuild!).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败：$e')),
      );
    }
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
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F5FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      // 用户头像（圆形）
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: const Color(0xFF5B7FD4).withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person,
                            size: 30, color: Color(0xFF5B7FD4)),
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
                                        ? const Color(0xFF10B981).withOpacity(0.1)
                                        : const Color(0xFFF59E0B).withOpacity(0.12),
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

                  // 分组：设置
                  _buildGroup([
                    _ListItem(
                      icon: Icons.settings_outlined,
                      iconColor: const Color(0xFF6B7280),
                      title: '设置',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('设置功能开发中')),
                        );
                      },
                    ),
                  ]),
                  const SizedBox(height: 12),

                  // 分组：关于
                  _buildGroup([
                    _ListItem(
                      icon: Icons.system_update_alt,
                      iconColor: const Color(0xFF10B981),
                      title: '检查更新',
                      trailing: _checking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                      onTap: () => _checkUpdate(context),
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
                            style: TextStyle(fontSize: 16, color: Color(0xFFD05656))),
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
      margin: const EdgeInsets.symmetric(horizontal: 12),
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
