/// 用户主页（职管家 · 个人职业版）
///
/// **入口**：在说说卡片上点击**作者信息栏**（头像 + 昵称那一整横栏，
/// 不含下方标题与正文区）。
///
/// **定位与边界（刻意极简）**：
/// - 只做两件事：展示该作者的资料与 ta 发布的全部说说，并提供「关注 / 已关注」切换；
/// - 不做粉丝数、个人简介、私信等当前没有数据支撑的模块；
/// - 资料（昵称 / 头像）以**用户表**为准刷新，而不是沿用进入时的快照，
///   避免同一用户在不同入口长得不一样。
library;

import 'package:flutter/material.dart';

import '../personal/personal_auth_service.dart';
import '../personal/user_avatar.dart';
import 'blog_post_card.dart';
import 'blog_store.dart';
import 'follow_store.dart';

const Color _kBrandOrange = Color(0xFFFD5C13);
const Color _kPageBg = Color(0xFFF5F5F5);
const Color _kTitleColor = Color(0xFF1A1B1C);
const Color _kMetaColor = Color(0xFF9CA3AF);
const Color _kBorderColor = Color(0xFFE5E7EB);

class UserProfilePage extends StatefulWidget {
  /// 目标用户手机号：说说数据与关注关系都以手机号为准
  final String phone;

  /// 进入时的昵称快照（先立即渲染，随后以用户表为准刷新）
  final String name;

  /// 进入时的头像快照（同上）
  final String avatarPath;

  const UserProfilePage({
    super.key,
    required this.phone,
    this.name = '',
    this.avatarPath = '',
  });

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  late String _name = widget.name;
  late String _avatarPath = widget.avatarPath;

  List<BlogPost> _posts = const [];
  bool _following = false;

  /// 是否在看自己的主页（自己的主页不显示关注按钮）
  bool _isSelf = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final users = await PersonalAuthService.getUsers();
    final me = await PersonalAuthService.getAuth();
    final posts = await BlogStore.loadByAuthor(widget.phone);
    final following = await FollowStore.isFollowing(widget.phone);

    final matched = users.where((u) => u.phone == widget.phone).toList();
    if (!mounted) return;
    setState(() {
      // 资料以用户表为准（昵称 / 头像可能已变更，快照仅用于首帧）
      if (matched.isNotEmpty) {
        _name = matched.first.name;
        _avatarPath = matched.first.avatarPath;
      }
      _posts = posts;
      _following = following;
      _isSelf = me != null && me.phone == widget.phone;
      _loading = false;
    });
  }

  /// 关注 / 取关。列表页返回后会重新拉取关注流，无需在此通知上层。
  ///
  /// 反馈由按钮自身状态承担（「关注」⇄「已关注」），不再叠一个重复的提示条。
  Future<void> _toggleFollow() async {
    final next = await FollowStore.toggleFollow(widget.phone);
    if (!mounted) return;
    setState(() => _following = next);
  }

  String get _displayName =>
      _name.trim().isEmpty ? BlogPost.anonymousAuthor : _name.trim();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kPageBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: _kTitleColor),
        title: Text(
          _displayName,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: _kTitleColor,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                _buildHeader(),
                const SizedBox(height: 12),
                if (_posts.isEmpty)
                  _buildEmpty()
                else
                  ..._posts.map((p) => BlogPostCard(post: p)),
              ],
            ),
    );
  }

  /// 头部：头像 + 昵称 + 说说数 + 关注按钮
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          UserAvatar(
            avatarPath: _avatarPath,
            name: _displayName,
            seed: widget.phone,
            size: 56,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _kTitleColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_posts.length} 条说说',
                  style: const TextStyle(fontSize: 12, color: _kMetaColor),
                ),
              ],
            ),
          ),
          if (!_isSelf) ...[
            const SizedBox(width: 12),
            _buildFollowButton(),
          ],
        ],
      ),
    );
  }

  /// 关注按钮：未关注为品牌橙实心，已关注为灰描边（点击即取关）
  Widget _buildFollowButton() {
    if (_following) {
      return OutlinedButton(
        onPressed: _toggleFollow,
        style: OutlinedButton.styleFrom(
          foregroundColor: _kMetaColor,
          side: const BorderSide(color: _kBorderColor),
          minimumSize: const Size(76, 34),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: const Text('已关注'),
      );
    }
    return FilledButton(
      onPressed: _toggleFollow,
      style: FilledButton.styleFrom(
        backgroundColor: _kBrandOrange,
        minimumSize: const Size(76, 34),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      child: const Text('关注'),
    );
  }

  /// 空态：该作者还没有说说
  Widget _buildEmpty() {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: const Text(
        '还没有发布说说',
        style: TextStyle(fontSize: 14, color: _kMetaColor),
      ),
    );
  }
}
