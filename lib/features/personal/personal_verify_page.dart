/// 实名认证页（职管家）
///
/// 注册登录后补充实名认证：身份证号 + 真实姓名。
/// 本地按 GB11643 校验身份证号（校验码/出生日期/性别/籍贯），
/// 认证成功后回填个人档案并刷新登录态。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'id_card_util.dart';
import 'personal_auth_service.dart';
import 'personal_model.dart';

class PersonalVerifyPage extends StatefulWidget {
  /// 认证完成后的回调（用于刷新「我的」页面）
  final VoidCallback? onVerified;

  const PersonalVerifyPage({super.key, this.onVerified});

  @override
  State<PersonalVerifyPage> createState() => _PersonalVerifyPageState();
}

class _PersonalVerifyPageState extends State<PersonalVerifyPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _idCardController = TextEditingController();
  String _error = '';
  bool _loading = false;
  PersonalAuth? _auth;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = await PersonalAuthService.getAuth();
    setState(() {
      _auth = auth;
      _nameController.text = auth?.name ?? '';
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _idCardController.dispose();
    super.dispose();
  }

  Future<void> _doVerify() async {
    final phone = _auth?.phone ?? '';
    final idCard = _idCardController.text.trim();
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      setState(() => _error = '请输入真实姓名');
      return;
    }
    if (idCard.isEmpty) {
      setState(() => _error = '请输入身份证号');
      return;
    }
    final info = IdCardUtil.validate(idCard);
    if (!info.valid) {
      setState(() => _error = info.error);
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final result = await PersonalAuthService.verifyIdentity(
        phone: phone,
        idCard: idCard,
        realName: name,
      );
      if (!result['ok']) {
        setState(() {
          _error = result['error'] ?? '实名认证失败';
          _loading = false;
        });
        return;
      }
      // 刷新登录态
      final user = result['user'] as PersonalUser;
      await PersonalAuthService.setAuth(PersonalAuth.fromUser(user));

      if (mounted) {
        widget.onVerified?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('实名认证成功')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      setState(() {
        _error = '实名认证失败，请稍后重试';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('实名认证'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1B1C),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F7FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '实名认证用于建立你的职业身份档案，信息仅保存在本机，不会公开显示。',
                  style: TextStyle(
                      fontSize: 13, color: Color(0xFF1E40AF), height: 1.5),
                ),
              ),
              const SizedBox(height: 24),
              const Text('真实姓名',
                  style: TextStyle(fontSize: 14, color: Color(0xFF374151))),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: '请输入身份证上的姓名',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              const Text('身份证号',
                  style: TextStyle(fontSize: 14, color: Color(0xFF374151))),
              const SizedBox(height: 8),
              TextField(
                controller: _idCardController,
                keyboardType: TextInputType.text,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9Xx]')),
                  LengthLimitingTextInputFormatter(18),
                ],
                decoration: InputDecoration(
                  hintText: '请输入18位身份证号',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              // 实时预览解析结果
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _idCardController,
                builder: (context, value, _) {
                  final info = IdCardUtil.validate(value.text);
                  if (!info.valid || value.text.trim().length != 18) {
                    return const SizedBox.shrink();
                  }
                  final b = info.birthday!;
                  final bStr =
                      '${b.year}-${b.month.toString().padLeft(2, '0')}-${b.day.toString().padLeft(2, '0')}';
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '校验通过：${info.gender} · $bStr · ${info.province ?? ''}',
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF15803D)),
                    ),
                  );
                },
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _loading ? null : _doVerify,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    disabledBackgroundColor: const Color(0xFFCBD5E1),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(_loading ? '提交中…' : '提交认证',
                      style:
                          const TextStyle(fontSize: 16, color: Colors.white)),
                ),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(_error,
                    style: const TextStyle(
                        color: Color(0xFFEA6668), fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
