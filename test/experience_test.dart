/// 职业数据模块测试（职管家 · 个人职业版）
///
/// 覆盖点：
/// 1. 经历数据层：新增 / 更新 / 删除 / 按类型过滤 / 条数统计 / JSON 往返；
/// 2. 排序：按起始时间倒序（由近及远），未填起始时间的排最后；
/// 3. 经历详情页：空态引导、已有经历平铺展示（含起止时间「至今」规则）；
/// 4. 经历编辑页：必填校验拦住空提交；填完后保存并回到列表；
/// 5. 自我评价：单段文本的保存 / 读回 / 清空 / 账号隔离；
/// 6. 自主学习成果：增删改查、JSON 往返（含图片与 PDF 附件）、列表页链路；
/// 7. 数据页：七张通栏卡片（基础信息 / 自我评价 / 学历教育 / 工作经历 /
///    技能培训 / 自主学习 / 对话记忆）与卡片宽度一致性；
/// 8. 回归：通栏卡片抽成公共组件后，发现页三行仍然照常渲染。
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
import 'package:zhiguanjia/features/data/self_evaluation_page.dart';
import 'package:zhiguanjia/features/data/self_evaluation_store.dart';
import 'package:zhiguanjia/features/data/study_file_store.dart';
import 'package:zhiguanjia/features/data/study_output_edit_page.dart';
import 'package:zhiguanjia/features/data/study_output_list_page.dart';
import 'package:zhiguanjia/features/data/study_output_store.dart';
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

      expect(find.text('还没有学历教育'), findsOneWidget);
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
      expect(find.text('北京大学'), findsNothing, reason: '学历教育不应出现在工作经历页');
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
    testWidgets('数据页出现七张职业数据卡片，并显示已填条数', (tester) async {
      SharedPreferences.setMockInitialValues({
        _authKey: _authJson(),
        _key(): [
          _entryJson(id: 'e1', kind: 'education', values: {'school': '北京大学'}),
        ],
      });
      // 放大画布，让页面底部的卡片也被布局出来
      await tester.binding.setSurfaceSize(const Size(400, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: DatabaseTab()));
      await tester.pumpAndSettle();

      // 基础信息 / 自我评价 / 学历教育 / 工作经历 / 技能培训 / 自主学习 / 对话记忆
      expect(find.byType(PlainGroup), findsNWidgets(7));
      expect(find.text('基础信息'), findsOneWidget);
      expect(find.text('自我评价'), findsOneWidget);
      expect(find.text('学历教育'), findsOneWidget);
      expect(find.text('工作经历'), findsOneWidget);
      expect(find.text('技能培训'), findsOneWidget);
      expect(find.text('自主学习'), findsOneWidget);
      expect(find.text('对话记忆'), findsOneWidget);
      // 只给学历教育录了 1 条 → 只有它显示条数
      expect(find.text('1 条'), findsOneWidget);
    });

    testWidgets('数据页所有卡片左右内缩一致（顶部认证卡与通栏卡同宽）', (tester) async {
      SharedPreferences.setMockInitialValues({_authKey: _authJson()});
      await tester.binding.setSurfaceSize(const Size(400, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: DatabaseTab()));
      await tester.pumpAndSettle();

      // 所有使用全站统一边距的卡片，卡片本体（不含外边距）宽度必须完全一致。
      // 曾经这里出过 bug：页面自带左右内边距 + 卡片又带一遍，卡片窄一圈。
      final cards = find.byWidgetPredicate(
        (w) => w is Container && w.margin == kCardMargin,
      );
      expect(cards, findsWidgets);

      final widths = <double>{};
      for (final e in cards.evaluate()) {
        // Container 的渲染盒含外边距，取内层 DecoratedBox（即卡片本体）来量
        final body = find
            .descendant(
              of: find.byWidget(e.widget),
              matching: find.byType(DecoratedBox),
            )
            .first;
        widths.add(tester.getSize(body).width);
      }

      expect(widths.length, 1, reason: '同页卡片宽度不一致：$widths');
      expect(widths.first, 400 - 2 * kCardSideMargin);
    });

    testWidgets('数据页点「学历教育」进入其详情页', (tester) async {
      SharedPreferences.setMockInitialValues({_authKey: _authJson()});
      await tester.binding.setSurfaceSize(const Size(400, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: DatabaseTab()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('学历教育'));
      await tester.pumpAndSettle();

      expect(find.byType(ExperienceListPage), findsOneWidget);
      expect(find.text('还没有学历教育'), findsOneWidget);
    });

    testWidgets('通栏组件抽取后，发现页三行照常渲染', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: DiscoverTab()));
      await tester.pumpAndSettle();

      expect(find.byType(PlainGroup), findsNWidgets(3));
      expect(find.text('职说'), findsOneWidget);
      expect(find.text('学习与成长'), findsOneWidget);
      expect(find.text('找工作'), findsOneWidget);
    });
  });

  group('自我评价', () {
    test('保存后可读回并去除首尾空白，且按账号隔离', () async {
      SharedPreferences.setMockInitialValues({_authKey: _authJson()});
      expect(await SelfEvaluationStore.load(), '');

      await SelfEvaluationStore.save('  8 年 ToB 产品经验  ');
      expect(await SelfEvaluationStore.load(), '8 年 ToB 产品经验');

      // 换账号：读不到别人的自我评价
      SharedPreferences.setMockInitialValues({
        _authKey: jsonEncode({
          'token': 'mock-token',
          'phone': '13900139000',
          'name': '李四',
        }),
      });
      expect(await SelfEvaluationStore.load(), '');
    });

    test('保存空串即清空', () async {
      SharedPreferences.setMockInitialValues({_authKey: _authJson()});
      await SelfEvaluationStore.save('内容');
      await SelfEvaluationStore.save('   ');
      expect(await SelfEvaluationStore.load(), '');
    });

    testWidgets('数据页点「自我评价」可编辑保存，返回后卡片显示「已填写」', (tester) async {
      SharedPreferences.setMockInitialValues({_authKey: _authJson()});
      await tester.binding.setSurfaceSize(const Size(400, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: DatabaseTab()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('自我评价'));
      await tester.pumpAndSettle();
      expect(find.byType(SelfEvaluationPage), findsOneWidget);

      await tester.enterText(find.byType(TextField), '结构化思考，擅长复杂系统拆解');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.byType(SelfEvaluationPage), findsNothing);
      expect(await SelfEvaluationStore.load(), '结构化思考，擅长复杂系统拆解');
      expect(find.text('已填写'), findsOneWidget);
    });
  });

  group('自主学习成果', () {
    StudyOutput make(String id, String title, {int updatedAt = 1}) =>
        StudyOutput(
          id: id,
          title: title,
          content: '内容$id',
          createdAt: 1,
          updatedAt: updatedAt,
        );

    test('保存 / 读回 / 更新 / 删除，按最近更新倒序', () async {
      SharedPreferences.setMockInitialValues({_authKey: _authJson()});
      await StudyOutputStore.save(make('a', '论文A', updatedAt: 10));
      await StudyOutputStore.save(make('b', '报告B', updatedAt: 20));

      var list = await StudyOutputStore.loadAll();
      expect(list.map((e) => e.id).toList(), ['b', 'a']);

      // 同 id 再次保存 = 更新，不产生重复
      await StudyOutputStore.save(make('a', '论文A（改）', updatedAt: 30));
      list = await StudyOutputStore.loadAll();
      expect(list.length, 2);
      expect(list.first.title, '论文A（改）');

      await StudyOutputStore.delete('b');
      expect((await StudyOutputStore.loadAll()).length, 1);
      expect(await StudyOutputStore.count(), 1);
    });

    test('成果数据按账号隔离', () async {
      SharedPreferences.setMockInitialValues({
        _authKey: jsonEncode({
          'token': 'mock-token',
          'phone': '13900139000',
          'name': '李四',
        }),
        'study_output_$_mePhone': [jsonEncode(make('x', '别人的成果').toJson())],
      });
      expect(await StudyOutputStore.loadAll(), isEmpty);
    });

    test('JSON 往返保留图片与 PDF 附件', () {
      const o = StudyOutput(
        id: 'x',
        title: '基于大模型的研究',
        content: '说明',
        images: ['/tmp/a.png'],
        files: [
          StudyAttachment(path: '/tmp/p.pdf', name: '论文.pdf', size: 2048),
        ],
        createdAt: 1,
        updatedAt: 2,
      );
      final back = StudyOutput.fromJson(jsonDecode(jsonEncode(o.toJson())));
      expect(back.images, ['/tmp/a.png']);
      expect(back.files.length, 1);
      expect(back.files.first.name, '论文.pdf');
      expect(back.files.first.size, 2048);
      expect(back.updatedAt, 2);
    });

    test('历史数据缺字段时兼容为空列表', () {
      final back = StudyOutput.fromJson({'id': 'y', 'title': 't'});
      expect(back.images, isEmpty);
      expect(back.files, isEmpty);
      expect(back.content, '');
      expect(back.displayTitle, 't');
    });

    test('附件体积文案', () {
      expect(StudyFileStore.formatSize(0), '');
      expect(StudyFileStore.formatSize(900), '900 B');
      expect(StudyFileStore.formatSize(2048), '2 KB');
      expect(StudyFileStore.formatSize(3 * 1024 * 1024), '3.0 MB');
    });

    testWidgets('列表空态 → 新增成果（标题必填）→ 保存后回到列表', (tester) async {
      SharedPreferences.setMockInitialValues({_authKey: _authJson()});
      await tester.pumpWidget(const MaterialApp(home: StudyOutputListPage()));
      await tester.pumpAndSettle();

      expect(find.text('还没有学习成果'), findsOneWidget);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.byType(StudyOutputEditPage), findsOneWidget);

      // 标题为空 → 被拦下
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请填写「标题」'), findsOneWidget);
      expect(find.byType(StudyOutputEditPage), findsOneWidget,
          reason: '校验失败不应离开编辑页');

      // 填标题后保存 → 回到列表并出现该成果
      await tester.enterText(find.byType(TextField).first, '基于大模型的求职研究');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.byType(StudyOutputEditPage), findsNothing);
      expect(find.text('基于大模型的求职研究'), findsOneWidget);
      expect(await StudyOutputStore.count(), 1);
    });

    testWidgets('数据页点「自主学习」进入成果页', (tester) async {
      SharedPreferences.setMockInitialValues({_authKey: _authJson()});
      await tester.binding.setSurfaceSize(const Size(400, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: DatabaseTab()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('自主学习'));
      await tester.pumpAndSettle();

      expect(find.byType(StudyOutputListPage), findsOneWidget);
      expect(find.text('还没有学习成果'), findsOneWidget);
    });
  });
}
