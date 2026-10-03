/// 个人注册页（职管家）
///
/// 单步注册：手机号 + 姓名 + 密码。
/// 注册成功自动登录进入主界面；实名认证在登录后于「我的」中完成。
import 'package:flutter/material.dart';
import '../../contracts/agent_service.dart';
import '../../contracts/chat_service.dart';
import '../agent/agent_service_impl.dart';
import '../chat/chat_service_impl.dart';
import '../shell/shell_page.dart';
import 'personal_auth_service.dart';
import 'personal_model.dart';

class PersonalRegisterPage extends StatefulWidget {
  final ChatService? chatService;
  final AgentService? agentService;

  const PersonalRegisterPage({super.key, this.chatService, this.agentService});

  @override
  State<PersonalRegisterPage> createState() => _PersonalRegisterPageState();
}

class _PersonalRegisterPageState extends State<PersonalRegisterPage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String _error = '';
  bool _loading = false;
  late final ChatService _chatService;
  late final AgentService _agentService;

  @override
  void initState() {
    super.initState();
    _chatService = widget.chatService ?? HttpChatService();
    _agentService = widget.agentService ?? HttpAgentService();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _doRegister() async {
    final phone = _phoneController.text.trim();
    final name = _nameController.text.trim();
    final password = _passwordController.text;

    if (phone.isEmpty || name.isEmpty || password.isEmpty) {
      setState(() => _error = '请填写完整信息');
      return;
    }
    if (phone.length != 11 || !phone.startsWith('1')) {
      setState(() => _error = '请输入正确的11位手机号');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = '密码至少6位');
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final result = await PersonalAuthService.registerUser(
        phone: phone,
        password: password,
        name: name,
      );
      if (!result['ok']) {
        setState(() {
          _error = result['error'] ?? '注册失败';
          _loading = false;
        });
        return;
      }

      final user = result['user'] as PersonalUser;
      await PersonalAuthService.setAuth(PersonalAuth.fromUser(user));

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => ShellPage(
              chatService: _chatService,
              agentService: _agentService,
            ),
          ),
          (route) => false,
        );
      }
    } catch (_) {
      setState(() {
        _error = '注册失败，请稍后重试';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('注册账号'),
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
              const SizedBox(height: 8),
              const Text(
                '创建你的职管家账号',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF1A1B1C)),
              ),
              const SizedBox(height: 8),
              const Text(
                '先注册账号，登录后可在「我的」完成实名认证',
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 28),
              const Text('手机号', style: TextStyle(fontSize: 14, color: Color(0xFF374151))),
              const SizedBox(height: 8),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                maxLength: 11,
                decoration: InputDecoration(
                  hintText: '请输入手机号',
                  counterText: '',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              const Text('姓名', style: TextStyle(fontSize: 14, color: Color(0xFF374151))),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: '请输入真实姓名',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              const Text('密码', style: TextStyle(fontSize: 14, color: Color(0xFF374151))),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: '请设置密码（至少6位）',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _loading ? null : _doRegister,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    disabledBackgroundColor: const Color(0xFFCBD5E1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(_loading ? '注册中…' : '注册并登录',
                      style: const TextStyle(fontSize: 16, color: Colors.white)),
                ),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(_error, style: const TextStyle(color: Color(0xFFEA6668), fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
