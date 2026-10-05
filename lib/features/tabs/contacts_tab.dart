/// 人脉 Tab（职管家 · 个人职业版）
///
/// 个人职业人脉网络：同行、前辈、合作伙伴、候选人等关系沉淀与连接。
/// MVP 阶段先搭结构占位。
/// 注意：本页不自带 AppBar，顶栏「人脉」标题由 ShellPage 统一提供。
library;

import 'package:flutter/material.dart';

/// 品牌活力橙（与 App 图标主色一致）
const Color _kBrandOrange = Color(0xFFFD5C13);

class ContactsTab extends StatefulWidget {
  const ContactsTab({super.key});

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> {
  /// 供主框架在切到本页时调用刷新（接口保留，占位期为空实现）
  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          children: [
            _buildPlaceholder(),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _kBrandOrange.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.groups_outlined,
                size: 36, color: _kBrandOrange),
          ),
          const SizedBox(height: 16),
          const Text(
            '人脉网络',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1B1C),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '同行、前辈、合作伙伴与候选人\n将在这里沉淀、连接并智能经营',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13, color: Color(0xFF9CA3AF), height: 1.6),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _kBrandOrange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '即将上线',
              style: TextStyle(fontSize: 12, color: _kBrandOrange),
            ),
          ),
        ],
      ),
    );
  }
}
