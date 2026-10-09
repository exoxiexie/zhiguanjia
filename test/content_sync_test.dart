/// 内容同步层测试（P3）：说说 / 收藏 / 关注
///
/// 覆盖：
/// 1. 发布说说：本地落盘 + 推送，且**本机图片先上传换成服务端地址**
/// 2. 图片上传失败时保留本机路径（不阻塞发布）
/// 3. 收藏新增/按 id 删除/按内容删除都能同步
/// 4. 关注/取关同步
/// 5. 拉取：云端说说按作者写回本机键；收藏与关注覆盖本地缓存
/// 6. 离线不抛异常、本地数据保留；游客不上云；拉取节流
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhiguanjia/contracts/auth_api.dart';
import 'package:zhiguanjia/contracts/content_api.dart';
import 'package:zhiguanjia/features/blog/blog_store.dart';
import 'package:zhiguanjia/features/blog/content_sync.dart';
import 'package:zhiguanjia/features/blog/follow_store.dart';
import 'package:zhiguanjia/features/data/favorite_store.dart';

class FakeContentApi implements ContentApi {
  int fetchCalls = 0;
  int uploadCalls = 0;
  bool online = true;
  bool uploadFails = false;
  PostDto? lastPost;
  FavoriteDto? lastFavorite;
  String? lastDeletedFavorite;
  String? lastFollowPhone;
  bool? lastFollowValue;
  ContentBundle bundle = const ContentBundle();

  ApiError get _offline => const ApiError(
      statusCode: 0, code: 'network', message: '无法连接服务器，请检查网络后重试');

  @override
  Future<ApiResult<ContentBundle>> fetch({int feedLimit = 100}) async {
    fetchCalls++;
    if (!online) return ApiResult.failure(_offline);
    return ApiResult.success(bundle);
  }

  @override
  Future<ApiResult<bool>> publishPost(PostDto post) async {
    if (!online) return ApiResult.failure(_offline);
    lastPost = post;
    return const ApiResult.success(true);
  }

  @override
  Future<ApiResult<bool>> deletePost(String id) async =>
      const ApiResult.success(true);

  @override
  Future<ApiResult<bool>> upsertFavorite(FavoriteDto item) async {
    if (!online) return ApiResult.failure(_offline);
    lastFavorite = item;
    return const ApiResult.success(true);
  }

  @override
  Future<ApiResult<bool>> deleteFavorite(String id) async {
    if (!online) return ApiResult.failure(_offline);
    lastDeletedFavorite = id;
    return const ApiResult.success(true);
  }

  @override
  Future<ApiResult<bool>> setFollow(String targetPhone, bool follow) async {
    if (!online) return ApiResult.failure(_offline);
    lastFollowPhone = targetPhone;
    lastFollowValue = follow;
    return const ApiResult.success(true);
  }

  @override
  Future<ApiResult<String>> uploadImage(String localFilePath) async {
    uploadCalls++;
    if (uploadFails) {
      return ApiResult.failure(_offline);
    }
    return ApiResult.success('/uploads/u1/${uploadCalls}.png');
  }
}

const String _phone = '13800001111';

void _seedLoggedIn() {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'zhiguanjia.personal.auth':
        '{"token":"t","phone":"$_phone","name":"我","idCard":"","gender":"","birthday":"","province":"","verifiedAt":"","avatarPath":""}',
  });
}

void main() {
  late FakeContentApi api;

  setUp(() {
    api = FakeContentApi();
    ContentSync.apiForTest = api;
    ContentSync.resetForTest();
  });

  test('发布说说：本地落盘 + 推送，本机图片先上传换成服务端地址', () async {
    _seedLoggedIn();

    await BlogStore.addPost(BlogPost(
      id: 'p1',
      title: '标题',
      content: '正文',
      images: ['/tmp/local-a.jpg', '/tmp/local-b.jpg'],
      createdAt: 1000,
    ));

    // 本地立即可见（推送是后台异步的，断言前先把事件队列跑空）
    await pumpEventQueue();
    final mine = await BlogStore.loadMyPosts();
    expect(mine.length, 1);
    expect(mine.first.content, '正文');

    // 两张图都上传了，推送的是服务端地址
    expect(api.uploadCalls, 2);
    expect(api.lastPost, isNotNull);
    expect(api.lastPost!.images.length, 2);
    expect(api.lastPost!.images.every((p) => p.startsWith('/uploads/')), isTrue,
        reason: '推送的应是服务端地址：${api.lastPost!.images}');

    // 上传后的地址已回写本地，避免重复上传
    final cached = await BlogStore.loadMyPosts();
    expect(cached.first.images.every((p) => p.startsWith('/uploads/')), isTrue,
        reason: '本地缓存应换成服务端地址：${cached.first.images}');
  });

  test('图片上传失败：保留本机路径，不阻塞发布', () async {
    _seedLoggedIn();
    api.uploadFails = true;

    await BlogStore.addPost(BlogPost(
      id: 'p2',
      title: '',
      content: '带图的说说',
      images: ['/tmp/local.jpg'],
      createdAt: 2000,
    ));
    await pumpEventQueue();

    expect(api.lastPost, isNotNull, reason: '图片失败也要把文字发出去');
    expect(api.lastPost!.images, ['/tmp/local.jpg']);
  });

  test('已是服务端地址的图片不重复上传', () async {
    _seedLoggedIn();
    await BlogStore.addPost(BlogPost(
      id: 'p3',
      title: '',
      content: '转发',
      images: ['/uploads/u1/old.png'],
      createdAt: 3000,
    ));
    await pumpEventQueue();
    expect(api.uploadCalls, 0);
    expect(api.lastPost!.images, ['/uploads/u1/old.png']);
  });

  test('收藏：新增 / 按 id 删除 / 按内容删除都能同步', () async {
    _seedLoggedIn();

    final added = await FavoriteStore.add(content: '一段回答', source: '通用对话');
    await pumpEventQueue();
    expect(added, isTrue);
    expect(api.lastFavorite, isNotNull);
    expect(api.lastFavorite!.content, '一段回答');

    final items = await FavoriteStore.list();
    expect(items.length, 1);
    await FavoriteStore.removeById(items.first.id);
    await pumpEventQueue();
    expect(api.lastDeletedFavorite, items.first.id);

    await FavoriteStore.add(content: '另一段', source: '通用对话');
    await FavoriteStore.removeByContent('另一段');
    await pumpEventQueue();
    expect((await FavoriteStore.list()), isEmpty);
    expect(api.lastDeletedFavorite, isNotNull, reason: '按内容删除也要同步');
  });

  test('关注 / 取关同步', () async {
    _seedLoggedIn();

    await FollowStore.setFollow('13900002222', true);
    await pumpEventQueue();
    expect(api.lastFollowPhone, '13900002222');
    expect(api.lastFollowValue, isTrue);
    expect(await FollowStore.isFollowing('13900002222'), isTrue);

    await FollowStore.setFollow('13900002222', false);
    await pumpEventQueue();
    expect(api.lastFollowValue, isFalse);
    expect(await FollowStore.isFollowing('13900002222'), isFalse);
  });

  test('拉取：云端说说按作者写回本机键，收藏与关注覆盖本地', () async {
    _seedLoggedIn();
    // 预置一条本地旧数据，验证会被云端数据覆盖
    await FollowStore.setFollow('13900009999', true);

    api.bundle = const ContentBundle(
      posts: [
        PostDto(id: 'cloud-1', title: 'A 的说说', content: '内容A', authorPhone: '13800001111', createdAt: 100),
        PostDto(id: 'cloud-2', title: 'B 的说说', content: '内容B', authorPhone: '13900002222',
                images: ['/uploads/u2/x.png'], createdAt: 200),
      ],
      favorites: [
        FavoriteDto(id: 'fav-1', content: '云端收藏', source: '通用对话', createdAt: 1),
      ],
      follows: ['13900002222'],
    );

    final ok = await ContentSync.pull(force: true);
    expect(ok, isTrue);

    expect((await BlogStore.loadMyPosts()).length, 1);
    expect((await BlogStore.loadByAuthor('13900002222')).first.content, '内容B');
    expect((await BlogStore.loadFeed()).length, 2, reason: '推荐流聚合所有作者');

    final favs = await FavoriteStore.list();
    expect(favs.length, 1);
    expect(favs.first.content, '云端收藏');

    final following = await FollowStore.loadFollowing();
    expect(following, {'13900002222'}, reason: '关注列表以云端为准');
  });

  test('离线：推送失败不抛异常，本地数据保留', () async {
    _seedLoggedIn();
    api.online = false;

    await BlogStore.addPost(BlogPost(id: 'p9', title: '', content: '离线说说', createdAt: 9000));
    await FavoriteStore.add(content: '离线收藏', source: '通用对话');

    expect((await BlogStore.loadMyPosts()).length, 1);
    expect((await FavoriteStore.list()).length, 1);
    await pumpEventQueue();
    expect(api.lastPost, isNull);
  });

  test('离线：拉取失败返回 false，不清空本地非空数据', () async {
    _seedLoggedIn();
    await BlogStore.addPost(BlogPost(id: 'p10', title: '', content: '本地内容', createdAt: 10));
    api.online = false;

    final ok = await ContentSync.pull(force: true);
    expect(ok, isFalse);
    expect((await BlogStore.loadMyPosts()).length, 1);
  });

  test('游客（未登录）不上云', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await BlogStore.addPost(BlogPost(id: 'g1', title: '', content: '游客说说', createdAt: 1));
    await ContentSync.pull(force: true);
    await pumpEventQueue();

    expect(api.lastPost, isNull);
    expect(api.fetchCalls, 0);
  });

  test('拉取节流：90 秒内只请求一次，force 可忽略', () async {
    _seedLoggedIn();
    await ContentSync.pull(force: true);
    await ContentSync.pullIfNeeded();
    expect(api.fetchCalls, 1);

    await ContentSync.pull(force: true);
    expect(api.fetchCalls, 2);
  });
}
