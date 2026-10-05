/// SearchDataStore（联网搜索数据）文件读写往返测试
///
/// 对应修复：**改权重/改标题会新建重复文件、删除会删错文件**。
/// 原根因：落盘名是 `{id}_{slug}.md`，但读回后 id 变成整段文件名，
/// 而 update/delete 仍按 `{id}_` 前缀匹配 → 永远匹配不到原文件。
/// 修复后约定：**id == 文件名（去 .md）**，update/delete 精确定位同一文件。
///
/// 用假 PathProvider 把应用文档目录指到临时目录，做真实文件读写。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:zhiguanjia/features/storage/search_data_store.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String root;
  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  const tenantId = '13800138000';

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('search_data_test');
    PathProviderPlatform.instance = _FakePathProvider(tempRoot.path);
  });

  tearDown(() async {
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  /// 数据目录
  Directory dataDir() =>
      Directory(p.join(tempRoot.path, 'tenants', tenantId, 'search_data'));

  /// 目录下的 md 文件名（去扩展名）
  List<String> fileStems() => dataDir()
      .listSync()
      .whereType<File>()
      .map((f) => p.basenameWithoutExtension(f.path))
      .toList();

  Future<SearchDataItem> create(String title) => SearchDataStore.create(
        tenantId: tenantId,
        title: title,
        searchQuery: 'AI 产品经理 薪资',
        content: '搜索结果正文：整体 15,000–50,000 元/月。',
        weight: 30,
      );

  group('create / listAll', () {
    test('id 与落盘文件名严格一致（去 .md）', () async {
      final created = await create('AI 产品经理薪资');
      final stems = fileStems();

      expect(stems.length, 1);
      expect(stems.first, created.id,
          reason: 'id 必须等于文件名去扩展名，否则读回后 update/delete 会失联');
    });

    test('listAll 读回的 id 与 create 返回的 id 一致', () async {
      final created = await create('AI 产品经理薪资');
      final all = await SearchDataStore.listAll(tenantId);

      expect(all.length, 1);
      expect(all.first.id, created.id);
      expect(all.first.title, 'AI 产品经理薪资');
      expect(all.first.weight, 30);
      expect(all.first.searchQuery, 'AI 产品经理 薪资');
    });
  });

  group('updateWeight 原地更新（原缺陷：新建重复文件）', () {
    test('改权重后仍只有一条记录，权重已生效', () async {
      await create('AI 产品经理薪资');
      final before = await SearchDataStore.listAll(tenantId);
      expect(before.length, 1);

      final updated =
          await SearchDataStore.updateWeight(tenantId, before.first.id, 60);

      expect(updated, isNotNull);
      expect(updated!.weight, 60);

      final after = await SearchDataStore.listAll(tenantId);
      expect(after.length, 1, reason: '改权重不得新建重复文件');
      expect(after.first.weight, 60);
      expect(fileStems().length, 1, reason: '目录里也不应出现第二个文件');
    });

    test('连续多次改权重不会累积文件', () async {
      await create('AI 产品经理薪资');
      for (final w in [40, 50, 60, 70]) {
        final all = await SearchDataStore.listAll(tenantId);
        await SearchDataStore.updateWeight(tenantId, all.first.id, w);
      }
      final all = await SearchDataStore.listAll(tenantId);
      expect(all.length, 1);
      expect(all.first.weight, 70);
    });

    test('id 不存在时返回 null，不产生新文件', () async {
      final result = await SearchDataStore.updateWeight(tenantId, '不存在的id', 60);
      expect(result, isNull);
      expect(fileStems(), isEmpty);
    });
  });

  group('update 改标题原地覆盖', () {
    test('改标题后 id 不变、文件不新增、内容已更新', () async {
      await create('原标题');
      final all = await SearchDataStore.listAll(tenantId);
      final target = all.first;

      final updated = await SearchDataStore.update(
        tenantId,
        target.copyWith(title: '新标题', weight: 80),
      );

      expect(updated.id, target.id, reason: 'id 应保持稳定');
      final after = await SearchDataStore.listAll(tenantId);
      expect(after.length, 1, reason: '改标题不得新建重复文件');
      expect(after.first.title, '新标题');
      expect(after.first.weight, 80);
    });
  });

  group('delete 精确删除（原缺陷：删错文件）', () {
    test('删除指定记录后，另一条完整保留', () async {
      final a = await create('第一条 AI 薪资');
      // 避免同一毫秒内 id 相同
      await Future.delayed(const Duration(milliseconds: 2));
      final b = await create('第二条 简历优化');

      expect((await SearchDataStore.listAll(tenantId)).length, 2);

      final ok = await SearchDataStore.delete(tenantId, a.id);
      expect(ok, isTrue);

      final after = await SearchDataStore.listAll(tenantId);
      expect(after.length, 1, reason: '应精确删除目标文件，不误删另一条');
      expect(after.first.id, b.id);
      expect(after.first.title, '第二条 简历优化');
    });

    test('删除不存在的 id 返回 false', () async {
      await create('唯一一条');
      expect(await SearchDataStore.delete(tenantId, '不存在的id'), isFalse);
      expect((await SearchDataStore.listAll(tenantId)).length, 1);
    });

    test('删除后 getById 取不到', () async {
      final created = await create('待删除');
      await SearchDataStore.delete(tenantId, created.id);
      expect(await SearchDataStore.getById(tenantId, created.id), isNull);
    });
  });

  group('历史文件兼容（旧命名 id 只有时间戳）', () {
    test('旧文件按前缀回退匹配，update/delete 仍可精确定位', () async {
      // 直接写一个历史格式文件：{时间戳}_{slug}.md
      final dir = dataDir();
      await dir.create(recursive: true);
      const legacyStem = '1750000000000_旧标题';
      await File(p.join(dir.path, '$legacyStem.md')).writeAsString('''
---
title: 旧标题
weight: 30
tags:
category: 联网搜索
search_query: 旧搜索词
source: 联网搜索
created_at: 2025-06-15T10:00:00.000
updated_at: 2025-06-15T10:00:00.000
---
旧正文
''');

      final all = await SearchDataStore.listAll(tenantId);
      expect(all.length, 1);
      expect(all.first.id, legacyStem, reason: '旧文件读回的 id 即文件名去扩展名');

      // 改权重：应原地覆盖旧文件，不新建
      final updated =
          await SearchDataStore.updateWeight(tenantId, all.first.id, 60);
      expect(updated!.weight, 60);
      expect((await SearchDataStore.listAll(tenantId)).length, 1);
      expect(fileStems(), [legacyStem]);

      // 删除：应删掉这个文件
      expect(await SearchDataStore.delete(tenantId, legacyStem), isTrue);
      expect(fileStems(), isEmpty);
    });

    test('用裸时间戳 id 也能定位旧文件（前缀回退）', () async {
      final dir = dataDir();
      await dir.create(recursive: true);
      await File(p.join(dir.path, '1750000000001_旧标题.md')).writeAsString('''
---
title: 旧标题
weight: 30
tags:
category: 联网搜索
search_query: 旧搜索词
source: 联网搜索
---
旧正文
''');

      expect((await SearchDataStore.listAll(tenantId)).length, 1);
      // 裸 id（只有毫秒时间戳）应通过前缀回退命中
      final found = await SearchDataStore.getById(tenantId, '1750000000001');
      expect(found, isNotNull);
      expect(found!.title, '旧标题');
    });
  });

  test('多租户目录互相隔离', () async {
    await create('A 的数据');
    await SearchDataStore.create(
      tenantId: '13900139000',
      title: 'B 的数据',
      searchQuery: 'q',
      content: 'c',
    );

    final a = await SearchDataStore.listAll(tenantId);
    final b = await SearchDataStore.listAll('13900139000');
    expect(a.length, 1);
    expect(b.length, 1);
    expect(a.first.title, 'A 的数据');
    expect(b.first.title, 'B 的数据');
  });
}
