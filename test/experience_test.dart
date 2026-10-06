/// 职业经历模块测试（职管家 · 个人职业版）
///
/// 覆盖点：
/// 1. 数据层：新增 / 更新 / 删除 / 按类型过滤 / 条数统计 / JSON 往返；
/// 2. 排序：按起始时间倒序（由近及远），未填起始时间的排最后；
/// 3. 详情页：空态引导、已有经历平铺展示（含起止时间「至今」规则）；
/// 4. 编辑页：必填校验拦住空提交；填完后保存并回到列表；
/// 5. 回归：通栏卡片抽成公共组件后，发现页三行仍然照常渲染。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhiguanjia/features/common/plain_group.dart';
import 'package:zhiguanjia/features/data/experience_edit_page.dart';
import 'package:zhiguanjia/features/data/experience_list_page.dart';
import 'package:zhiguanjia/features/data/experience_models.dart';
import 'package:zhiguanjia/features/data/experience_store.dart';
import 'package:zhiguanjia/features/discover/discover_tab.dart';
import 'package:zhiguanjia/features/tabs/database_tab.dart';

const String _authKey = 'zhiguanjia.personal.auth';
const String _mePhone = '13800138000';

String _authJson() => jsonEncode({
      'token': 'mock-token',
      'phone': _mePhone,
      'name': '张三',
    });

/// 指定账号的经历存储键
String _key([String phone = _mePhone]) => 'experience_$phone';

/// 构造一条经历 JSON
String _entryJson({
  required String id,
  required String kind,
  required Map<String, String> values,
  int createdAt = 1,
  int updatedAt = 1,
}) =>
    jsonEncode({
      'id': id,
      'kind': kind,
      'values': values,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('数据层：经历增删改查', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({_authKey: _authJson()});
    });

    test('保存后能按类型读回，条数统计正确', () async {
      await ExperienceStore.save(const ExperienceEntry(
        id: 'e1',
        kindId: 'education',
        values: {'school': '北京大学', 'major': '计算机'},
        createdAt: 1,
        updatedAt: 1,
      ));
      await ExperienceStore.save(const ExperienceEntry(
        id: 'w1',
        kindId: 'work',
        values: {'company': '腾讯'},
        createdAt: 2,
        updatedAt: 2,
      ));

      final edu = await ExperienceStore.listByKind('education');
      expect(edu.length, 1);
      expect(edu.first.v('school'), '北京大学');

      final counts = await ExperienceStore.counts();
      expect(counts['education'], 1);
      expect(counts['work'], 1);
      expect(counts['training'], 0, reason: '未录入的类型应为 0 条');
    });

    test('同 id 再次保存为更新而不是新增', () async {
      await ExperienceStore.save(const ExperienceEntry(
        id: 'e1',
        kindId: 'education',
        values: {'school': '北京大学'},
        createdAt: 1,
        updatedAt: 1,
      ));
      await ExperienceStore.save(const ExperienceEntry(
        id: 'e1',
        kindId: 'education',
        values: {'school': '清华大学'},
        createdAt: 1,
        updatedAt: 2,
      ));

      final edu = await ExperienceStore.listByKind('education');
      expect(edu.length, 1, reason: '同 id 必须覆盖，不能产生重复记录');
      expect(edu.first.v('school'), '清华大学');
    });

    test('删除只移除目标条目', () async {
      for (final id in ['a', 'b']) {
        await ExperienceStore.save(ExperienceEntry(
          id: id,
          kindId: 'work',
          values: {'company': '公司$id'},
          createdAt: 1,
          updatedAt: 1,
        ));
      }
      await ExperienceStore.delete('a');

      final list = await ExperienceStore.listByKind('work');
      expect(list.length, 1);
      expect(list.first.id, 'b');
    });

    test('按起始时间倒序，未填起始时间的排最后', () async {
      SharedPreferences.setMockInitialValues({
        _authKey: _authJson(),
        _key(): [
          _entryJson(
              id: 'old',
              kind: 'work',
              values: {'company': '老东家', 'start': '2018-03'}),
          _entryJson(
              id: 'none', kind: 'work', values: {'company': '没填时间'}),
          _entryJson(
              id: 'new',
              kind: 'work',
              values: {'company': '现东家', 'start': '2022-07'}),
        ],
      });

      final list = await ExperienceStore.listByKind('work');
      expect(list.map((e) => e.id).toList(), ['new', 'old', 'none']);
    });

    test('损坏条目被跳过，不影响其他经历', () async {
      SharedPreferences.setMockInitialValues({
        _authKey: _authJson(),
        _key(): [
          '这不是合法 JSON',
          _entryJson(
              id: 'ok', kind: 'work', values: {'company': '正常公司'}),
        ],
      });

      final list = await ExperienceStore.listByKind('work');
      expect(list.length, 1);
      expect(list.first.v('company'), '正常公司');
    });

    test('经历数据按账号隔离', () async {
      SharedPreferences.setMockInitialValues({
        _authKey: _authJson(),
        _key('13900139000'): [
          _entryJson(
              id: 'other',
              kind: 'work',
              values: {'company': '别人的公司'}),
        ],
      });

      final list = await ExperienceStore.listByKind('work');
      expect(list, isEmpty, reason: '不应读到其他账号的经历');
    });
  });

  group('模型：起止时间与 JSON', () {
    test('rangeText：结束为空显示「至今」，两者都空则留空', () {
      ExperienceEntry e(Map<String, String> v) => ExperienceEntry(
          id: '1', kindId: 'work', values: v, createdAt: 1, updatedAt: 1);

      expect(e({'start': '2022-07'}).rangeText(ExperienceKind.work),
          '2022.07 - 至今');
      expect(e({'start': '2020-09', 'end': '2024-06'}).rangeText(
              ExperienceKind.work),
          '2020.09 - 2024.06');
      expect(e({}).rangeText(ExperienceKind.work), '');
    });

    test('JSON 往返不丢字段值', () {
      const entry = ExperienceEntry(
        id: '1',
        kindId: 'training',
        values: {'org': '某机构', 'course': 'PMP'},
        createdAt: 10,
        updatedAt: 20,
      );
      final back = ExperienceEntry.fromJson(jsonDecode(jsonEncode(entry.toJson())));
      expect(back.kindId, 'training');
      expect(back.v('org'), '某机构');
      expect(back.createdAt, 10);
      expect(back.updatedAt, 20);
    });

    test('三类经历都有主字段与起止时间字段', () {
      for (final k in ExperienceKind.all) {
        expect(k.primaryField.required, isTrue,
            reason: '${k.label} 的主字段应当是必填项');
        expect(k.startField, isNotNull, reason: '${k.label} 应能识别起始时间字段');
      }
    });
  });

  group('详情页', () {
    testWidgets('空态：提示还没有该类经历', (tester) async {
      SharedPreferences.setMockInitialValues({_authKey: _authJson()});
      await tester.pumpWidget(const MaterialApp(
        home: ExperienceListPage(kind: ExperienceKind.education),
      ));
      await tester.pumpAndSettle();

      expect(find.text('还没有教育经历'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('已有经历：平铺展示主字段、起止时间与其余字段', (tester) async {
      SharedPreferences.setMockInitialValues({
        _authKey: _authJson(),
        _key(): [
          _entryJson(id: 'e1', kind: 'education', values: {
            'school': '北京大学',
            'major': '计算机科学与技术',
            'degree': '本科',
            'start': '2020-09',
            'end': '2024-06',
          }),
          // 在职中：结束时间留空 → 显示「至今」
          _entryJson(id: 'w1', kind: 'work', values: {
            'company': '腾讯科技',
            'position': '产品经理',
            'start': '2024-07',
          }),
        ],
      });

      await tester.pumpWidget(const MaterialApp(
        home: ExperienceListPage(kind: ExperienceKind.work),
      ));
      await tester.pumpAndSettle();

      // 只展示工作经历，且结束时间留空显示「至今」
      expect(find.text('腾讯科技'), findsOneWidget);
      expect(find.text('产品经理'), findsOneWidget);
      expect(find.text('2024.07 - 至今'), findsOneWidget);
      expect(find.text('北京大学'), findsNothing, reason: '教育经历不应出现在工作经历页');
    });

    testWidgets('必填校验拦住空提交；填写后可保存并回到列表', (tester) async {
      SharedPreferences.setMockInitialValues({_authKey: _authJson()});
      await tester.pumpWidget(const MaterialApp(
        home: ExperienceListPage(kind: ExperienceKind.education),
      ));
      await tester.pumpAndSettle();

      // 空表单直接保存 → 不允许通过
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.byType(ExperienceEditPage), findsOneWidget);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请填写「学校名称」'), findsOneWidget);
      expect(find.byType(ExperienceEditPage), findsOneWidget,
          reason: '校验失败不应离开编辑页');

      // 填必填项后保存 → 回到列表并出现新记录
      await tester.enterText(find.byType(TextField).first, '北京大学');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.byType(ExperienceEditPage), findsNothing);
      expect(find.text('北京大学'), findsOneWidget);
    });
  });

  group('数据页接入与通栏组件回归', () {
    testWidgets('数据页出现三张经历通栏卡片，并显示已填条数', (tester) async {
      SharedPreferences.setMockInitialValues({
        _authKey: _authJson(),
        _key(): [
          _entryJson(id: 'e1', kind: 'education', values: {'school': '北京大学'}),
        ],
      });
      // 放大画布，让页面底部的卡片也被布局出来
      await tester.binding.setSurfaceSize(const Size(400, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: DatabaseTab()));
      await tester.pumpAndSettle();

      expect(find.byType(PlainGroup), findsNWidgets(3));
      expect(find.text('教育经历'), findsOneWidget);
      expect(find.text('工作经历'), findsOneWidget);
      expect(find.text('培训经历'), findsOneWidget);
      // 只给教育经历录了 1 条 → 只有它显示条数
      expect(find.text('1 条'), findsOneWidget);
    });

    testWidgets('数据页点「教育经历」进入其详情页', (tester) async {
      SharedPreferences.setMockInitialValues({_authKey: _authJson()});
      await tester.binding.setSurfaceSize(const Size(400, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: DatabaseTab()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('教育经历'));
      await tester.pumpAndSettle();

      expect(find.byType(ExperienceListPage), findsOneWidget);
      expect(find.text('还没有教育经历'), findsOneWidget);
    });

    testWidgets('通栏组件抽取后，发现页三行照常渲染', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: DiscoverTab()));
      await tester.pumpAndSettle();

      expect(find.byType(PlainGroup), findsNWidgets(3));
      expect(find.text('说说'), findsOneWidget);
      expect(find.text('学习'), findsOneWidget);
      expect(find.text('招聘'), findsOneWidget);
    });
  });
}
