/// 个人登录页（职管家）
///
/// 手机号 + 密码登录，成功后进入主界面。
import 'package:flutter/material.dart';
import '../../contracts/agent_service.dart';
import '../../contracts/chat_service.dart';
import '../agent/agent_service_impl.dart';
import '../chat/chat_service_impl.dart';
import '../shell/shell_page.dart';
import 'personal_auth_service.dart';
import 'personal_model.dart';
import 'personal_register_page.dart';

class PersonalLoginPage extends StatefulWidget {
  final ChatService? chatService;
  final AgentService? agentService;

  const PersonalLoginPage({super.key, this.chatService, this.agentService});

  @override
  State<PersonalLoginPage> createState() => _PersonalLoginPageState();
}

class _PersonalLoginPageState extends State<PersonalLoginPage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _passwordFocusNode = FocusNode();
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
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _doLogin() async {
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;

    if (phone.isEmpty || password.isEmpty) {
      setState(() => _error = '请输入手机号和密码');
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final result = await PersonalAuthService.loginUser(phone, password);
      if (!result['ok']) {
        setState(() {
          _error = result['error'] ?? '登录失败';
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
        _error = '登录失败，请稍后重试';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录'),
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
              const SizedBox(height: 20),
              const Text(
                '职管家 · AI职业管家',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF1A1B1C)),
              ),
              const SizedBox(height: 8),
              const Text(
                '每个人，都拥有自己的终身职业智能管家',
                style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 40),
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
              const Text('密码', style: TextStyle(fontSize: 14, color: Color(0xFF374151))),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                focusNode: _passwordFocusNode,
                obscureText: true,
                onTap: () {
                  // 确保首次点击时焦点稳定落在密码框
                  _passwordFocusNode.requestFocus();
                },
                decoration: InputDecoration(
                  hintText: '请输入密码',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _loading ? null : _doLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    disabledBackgroundColor: const Color(0xFFCBD5E1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(_loading ? '登录中…' : '登 录',
                      style: const TextStyle(fontSize: 16, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('还没有账号？', style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PersonalRegisterPage(
                            chatService: _chatService,
                            agentService: _agentService,
                          ),
                        ),
                      );
                    },
                    child: const Text('注册账号', style: TextStyle(color: Color(0xFF2563EB), fontSize: 13)),
                  ),
                ],
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
