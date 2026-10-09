/// 强制更新拦截页（P5-b）
///
/// 当服务端下发的 `min_version_code` 高于本机 versionCode 时展示此页：
/// **必须升级才能继续使用**（用于紧急下线有严重缺陷的版本）。
/// 与网络失败严格区分：拿不到配置绝不进这一页。
///
/// 下载复用既有更新链路（`HttpUpdateService.download`），下载完交系统安装器，
/// 因此本页不引入任何新依赖。
library;

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../../contracts/app_api.dart';
import '../update/update_service_impl.dart';

class ForceUpdatePage extends StatefulWidget {
  final AppRemoteConfig config;
  final String currentVersion;

  const ForceUpdatePage({
    super.key,
    required this.config,
    this.currentVersion = '',
  });

  @override
  State<ForceUpdatePage> createState() => _ForceUpdatePageState();
}

class _ForceUpdatePageState extends State<ForceUpdatePage> {
  bool _downloading = false;
  double _progress = 0;

  Future<void> _download() async {
    final url = widget.config.updateUrl;
    if (url.isEmpty || _downloading) return;
    setState(() {
      _downloading = true;
      _progress = 0;
    });

    try {
      final service = HttpUpdateService(baseUrls: const <String>[]);
      final path = await service.download(
        url,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      await OpenFilex.open(path);
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('下载失败'),
          content: Text('请稍后重试，或到官网手动下载。\n\n$url',
              style: const TextStyle(fontSize: 13, height: 1.6)),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('知道了')),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.config.updateNote.trim();
    final target =
        widget.config.minVersionName.isEmpty ? '最新版本' : widget.config.minVersionName;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Spacer(flex: 2),
              Icon(Icons.system_update_alt_rounded,
                  size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 20),
              const Text('发现重要更新',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text(
                '当前版本${widget.currentVersion.isEmpty ? '' : ' ${widget.currentVersion}'}'
                ' 已不再支持，请升级到 $target 后继续使用。',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF6B7280), height: 1.6),
              ),
              if (note.isNotEmpty) ...<Widget>[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F5F7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      Text(note, style: const TextStyle(fontSize: 13, height: 1.6)),
                ),
              ],
              const Spacer(flex: 3),
              if (_downloading) ...<Widget>[
                LinearProgressIndicator(value: _progress == 0 ? null : _progress),
                const SizedBox(height: 8),
                Text('正在下载 ${(_progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
              ] else if (widget.config.updateUrl.isEmpty)
                const Text('请联系客服获取最新安装包',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)))
              else
                FilledButton(
                  onPressed: _download,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                  child: const Text('立即更新'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
