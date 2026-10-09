/// 内容 API 契约（P3 · 内容云化）
///
/// 覆盖范围：说说/博客（含配图）、收藏、关注。
/// 同步策略见《商业版改造方案》第五节 B 类「内容类」：**服务端为准 + 本地缓存**。
///
/// 关于可见范围：`fetch()` 返回「全站说说（含我的）+ 我的收藏 + 我的关注」，
/// 客户端按作者手机号分组写回本机原有的 `blog_posts_{作者}` 键，
/// 因此「推荐 / 关注 / 我的」三个子 Tab 的既有逻辑一行都不用改。
library;

import 'auth_api.dart';

/// 一条说说（字段与 App 端 BlogPost 对应）
class PostDto {
  final String id;
  final String title;
  final String content;

  /// 图片地址：可能是服务端 URL（跨设备可见），也可能是本机路径
  final List<String> images;

  final String authorPhone;
  final String authorName;
  final String authorAvatarPath;
  final int createdAt;

  const PostDto({
    required this.id,
    this.title = '',
    this.content = '',
    this.images = const [],
    this.authorPhone = '',
    this.authorName = '',
    this.authorAvatarPath = '',
    this.createdAt = 0,
  });

  factory PostDto.fromWire(Map<String, dynamic> json) => PostDto(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        content: json['content']?.toString() ?? '',
        images: [
          for (final x in (json['images'] as List? ?? const [])) x.toString(),
        ],
        authorPhone: json['author_phone']?.toString() ?? '',
        authorName: json['author_name']?.toString() ?? '',
        authorAvatarPath: json['author_avatar_path']?.toString() ?? '',
        createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      );
}

/// 一条收藏
class FavoriteDto {
  final String id;
  final String content;
  final String source;
  final int createdAt;

  const FavoriteDto({
    required this.id,
    this.content = '',
    this.source = '',
    this.createdAt = 0,
  });

  factory FavoriteDto.fromWire(Map<String, dynamic> json) => FavoriteDto(
        id: json['id']?.toString() ?? '',
        content: json['content']?.toString() ?? '',
        source: json['source']?.toString() ?? '',
        createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      );
}

/// 一次拉取的全部内容
class ContentBundle {
  final List<PostDto> posts;
  final List<FavoriteDto> favorites;

  /// 我关注的手机号
  final List<String> follows;

  const ContentBundle({
    this.posts = const [],
    this.favorites = const [],
    this.follows = const [],
  });

  factory ContentBundle.fromWire(Map<String, dynamic> json) => ContentBundle(
        posts: [
          for (final e in (json['posts'] as List? ?? const []))
            PostDto.fromWire((e as Map).cast<String, dynamic>()),
        ],
        favorites: [
          for (final e in (json['favorites'] as List? ?? const []))
            FavoriteDto.fromWire((e as Map).cast<String, dynamic>()),
        ],
        follows: [
          for (final e in (json['follows'] as List? ?? const [])) e.toString(),
        ],
      );
}

/// 内容接口
abstract class ContentApi {
  /// 拉取全站说说 + 我的收藏 + 我的关注
  Future<ApiResult<ContentBundle>> fetch({int feedLimit = 100});

  /// 发布 / 修改说说
  Future<ApiResult<bool>> publishPost(PostDto post);

  /// 删除说说（仅本人；当前 App 尚未提供删除入口，接口先备好）
  Future<ApiResult<bool>> deletePost(String id);

  /// 新增/更新收藏
  Future<ApiResult<bool>> upsertFavorite(FavoriteDto item);

  /// 删除收藏
  Future<ApiResult<bool>> deleteFavorite(String id);

  /// 关注 / 取关
  Future<ApiResult<bool>> setFollow(String targetPhone, bool follow);

  /// 上传一张图片，返回可对外访问的地址（相对路径，如 /uploads/xx/yy.png）
  Future<ApiResult<String>> uploadImage(String localFilePath);
}
