/// 设置页（从「我的」页收纳进来：检查更新 / 导出数据 / 注销账号）
///
/// 为什么单独成页：这三项都属于"低频但重要"的设置操作，
/// 放在「我的」页首屏会与高频的个人信息卡片争夺注意力。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../contracts/app_api.dart';
import '../../contracts/update_service.dart';
import '../api/app_api_impl.dart';
import '../chat/session_reset.dart';
import '../common/app_snack_bar.dart';
import '../common/plain_group.dart';
import '../personal/personal_auth_service.dart';
import '../personal/personal_login_page.dart';
import '../update/update_service_impl.dart';
import 'local_data_cleaner.dart';

/// 更新服务器地址（多源：Gitee API 优先，GitHub 回退；均公网可访问）
const List<String> _kUpdateBaseUrls = <String>[
  'https://gitee.com/api/v5/repos/laoxie2076/zhiguanjia/contents',
  'https://raw.githubusercontent.com/exoxiexie/zhiguanjia/main',
];

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _checking = false;
  bool _downloading = false;
  double _progress = 0;
  StateSetter? _setDialogState;

  UpdateService get _updateSvc =>
      HttpUpdateService(baseUrls: _kUpdateBaseUrls);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: <Widget>[
          PlainGroup(entries: <PlainGroupEntry>[
            PlainGroupEntry(
              icon: Icons.system_update_alt,
              color: const Color(0xFF10B981),
              label: '检查更新',
              trailingText: _checking ? '检查中…' : '',
              onTap: () => _checkUpdate(context),
            ),
            PlainGroupEntry(
              icon: Icons.download_outlined,
              color: const Color(0xFF2563EB),
              label: '导出我的数据',
              onTap: () => _exportData(context),
            ),
          ]),
          const SizedBox(height: 12),
          PlainGroup(entries: <PlainGroupEntry>[
            PlainGroupEntry(
              icon: Icons.no_accounts_outlined,
              color: const Color(0xFFD05656),
              label: '注销账号',
              trailingText: '不可恢复',
              onTap: () => _deleteAccount(context),
            ),
          ]),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '注销账号会永久删除服务端与本机的全部数据（对话、记忆、档案、说说、收藏等），'
              '且无法恢复。',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF9CA3AF), height: 1.6),
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────── 检查更新 ──────────────────────────

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
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('立即更新')),
          ],
        ),
      );
      if (proceed == true && mounted) {
        await _downloadAndInstall(context, info);
      }
    } else {
      showAppSnackBar(context, result.message ?? '已是最新版本');
    }
  }

  Future<void> _downloadAndInstall(BuildContext context, UpdateInfo info) async {
    setState(() => _downloading = true);
    BuildContext? dialogRebuild;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogRebuild = ctx;
        return AlertDialog(
          title: const Text('正在下载更新'),
          content: StatefulBuilder(
            builder: (ctx, setDialogState) {
              _setDialogState = setDialogState;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (_progress >= 0)
                    LinearProgressIndicator(
                        value: _progress > 0 ? _progress / 100 : null)
                  else
                    const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  if (_progress >= 0)
                    Text('${_progress.toStringAsFixed(0)}%')
                  else
                    Text(
                        '已下载 ${(_progress.abs() / 1024 / 1024).toStringAsFixed(1)} MB'),
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
        onProgress: (percent) {
          _setDialogState?.call(() {
            _progress = percent >= 0 ? percent * 100 : percent;
          });
        },
      );
      if (dialogRebuild != null && dialogRebuild!.mounted) {
        Navigator.of(dialogRebuild!).pop();
      }
      if (!mounted) return;
      setState(() => _downloading = false);

      final result = await OpenFilex.open(path);
      if (!mounted) return;
      showAppSnackBar(
        context,
        result.type == ResultType.done
            ? '下载完成，请在系统安装界面确认安装'
            : '下载完成，但打开安装器失败（${result.message}）',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloading = false);
      if (dialogRebuild != null && dialogRebuild!.mounted) {
        Navigator.of(dialogRebuild!).pop();
      }
      showAppSnackBar(context, '下载失败：$e');
    }
  }

  // ────────────────────────── 导出数据 ──────────────────────────

  Future<void> _exportData(BuildContext context) async {
    showAppSnackBar(context, '正在导出…');

    final res = await const HttpAppApi().exportMyData();
    if (!mounted) return;
    if (!res.ok || res.data == null) {
      showAppSnackBar(context, res.error?.message ?? '导出失败，请稍后重试');
      return;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path,
          'zhiguanjia-export-${DateTime.now().millisecondsSinceEpoch}.json'));
      await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(res.data));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导出成功'),
          content: Text('已保存到：\n${file.path}',
              style: const TextStyle(fontSize: 13, height: 1.6)),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('关闭')),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                OpenFilex.open(file.path);
              },
              child: const Text('打开文件'),
            ),
          ],
        ),
      );
    } catch (_) {
      showAppSnackBar(context, '保存文件失败');
    }
  }

  // ────────────────────────── 注销账号 ──────────────────────────

  Future<void> _deleteAccount(BuildContext context) async {
    final auth = await PersonalAuthService.getAuth();
    if (auth == null || !context.mounted) return;

    final step1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认注销账号？'),
        content: const Text(
            '注销后，服务端与本机的**全部数据**（对话、记忆、档案、说说、收藏等）都会被永久删除，'
            '且无法恢复。',
            style: TextStyle(fontSize: 14, height: 1.7)),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('继续',
                  style: TextStyle(color: Color(0xFFD05656)))),
        ],
      ),
    );
    if (step1 != true || !context.mounted) return;

    final step2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('再次确认'),
        content: Text('账号 ${auth.phone} 注销后不可恢复，确定继续吗？',
            style: const TextStyle(fontSize: 14, height: 1.7)),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('我再想想')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('确认注销',
                  style: TextStyle(color: Color(0xFFD05656)))),
        ],
      ),
    );
    if (step2 != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final res = await const HttpAppApi().deleteAccount();
    if (!res.ok) {
      showAppSnackBar(context, res.error?.message ?? '注销失败，请稍后重试');
      return;
    }

    resetUserSessionState();
    await LocalDataCleaner.purgeAccount(auth.phone);
    await PersonalAuthService.clearAuth();

    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PersonalLoginPage()),
      (route) => false,
    );
  }
}
