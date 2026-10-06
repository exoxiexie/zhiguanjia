/// 基础信息 + 省市区选择器 + 圆形新增按钮 测试（职管家 · 个人职业版）
///
/// 覆盖点：
/// 1. 基础信息数据层：保存 / 读回 / 全空不写键 / 清空删键 / 按账号隔离 / 损坏容错 / JSON 往返；
/// 2. 省市区数据规模与选择结果（RegionSelection）的拼接与解析；
/// 3. 数据页「基础信息」卡的插入位置（自我评价之上）与跳转；
/// 4. 基础信息页：选项选择 → 保存 → 读回；已存省市区与详细地址回显；弹出选择器；
/// 5. 全站新增按钮为**正圆**（覆盖 M3 默认的圆角方形）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhiguanjia/features/common/app_fab.dart';
import 'package:zhiguanjia/features/data/basic_info_page.dart';
import 'package:zhiguanjia/features/data/basic_info_store.dart';
import 'package:zhiguanjia/features/data/region_data.dart';
import 'package:zhiguanjia/features/data/region_picker.dart';
import 'package:zhiguanjia/features/tabs/database_tab.dart';

const String _authKey = 'zhiguanjia.personal.auth';
const String _mePhone = '13800138000';

String _authJson([String phone = _mePhone]) => jsonEncode({
      'token': 'mock-token',
      'phone': phone,
      'name': '张三',
    });

String _key([String phone = _mePhone]) => 'basic_info_$phone';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('基础信息数据层', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({_authKey: _authJson()});
    });

    test('保存后可读回全部字段', () async {
      await BasicInfoStore.save(const BasicInfo(
        province: '广东省',
        city: '深圳市',
        district: '南山区',
        address: '科技园路 1 号',
        workStatus: WorkStatus.employed,
        maritalStatus: MaritalStatus.single,
      ));

      final info = await BasicInfoStore.load();
      expect(info.province, '广东省');
      expect(info.city, '深圳市');
      expect(info.district, '南山区');
      expect(info.address, '科技园路 1 号');
      expect(info.workStatus, WorkStatus.employed);
      expect(info.maritalStatus, MaritalStatus.single);
      expect(info.isNotEmpty, isTrue);
    });

    test('全部为空时不写键（等同未填写）', () async {
      await BasicInfoStore.save(const BasicInfo());
      expect(await BasicInfoStore.hasAny(), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_key()), isNull, reason: '空信息不应留下键');
    });

    test('由有到无：清空后键被删除', () async {
      await BasicInfoStore.save(const BasicInfo(
          province: '北京市', city: '市辖区', district: '东城区'));
      expect(await BasicInfoStore.hasAny(), isTrue);

      await BasicInfoStore.save(const BasicInfo());
      expect(await BasicInfoStore.hasAny(), isFalse);
    });

    test('按账号隔离：换账号读不到上一个账号的基础信息', () async {
      SharedPreferences.setMockInitialValues({
        _authKey: _authJson('13900139000'),
        _key(): jsonEncode(const BasicInfo(
                province: '上海市', city: '市辖区', district: '黄浦区')
            .toJson()),
      });
      expect(await BasicInfoStore.hasAny(), isFalse);
    });

    test('数据损坏时按未填写处理', () async {
      SharedPreferences.setMockInitialValues({
        _authKey: _authJson(),
        _key(): '这不是合法 JSON',
      });
      expect((await BasicInfoStore.load()).isEmpty, isTrue);
    });

    test('JSON 往返不丢字段', () {
      const info = BasicInfo(
        province: '浙江省',
        city: '杭州市',
        district: '西湖区',
        address: '文三路 1 号',
        workStatus: WorkStatus.resigned,
        maritalStatus: MaritalStatus.married,
      );
      final back = BasicInfo.fromJson(jsonDecode(jsonEncode(info.toJson())));
      expect(back.province, '浙江省');
      expect(back.city, '杭州市');
      expect(back.district, '西湖区');
      expect(back.address, '文三路 1 号');
      expect(back.workStatus, WorkStatus.resigned);
      expect(back.maritalStatus, MaritalStatus.married);
    });

    test('regionText / fullAddress 拼接正确', () {
      const info = BasicInfo(
          province: '广东省', city: '深圳市', district: '南山区', address: '科技园路 1 号');
      expect(info.regionText, '广东省 深圳市 南山区');
      expect(info.fullAddress, '广东省 深圳市 南山区 科技园路 1 号');
    });

    test('枚举名解析：未知值返回 null', () {
      expect(WorkStatus.fromName('employed'), WorkStatus.employed);
      expect(WorkStatus.fromName('nope'), isNull);
      expect(MaritalStatus.fromName('other'), MaritalStatus.other);
      expect(MaritalStatus.fromName(null), isNull);
    });
  });

  group('省市区数据与选择结果', () {
    test('覆盖 34 个省级单位（含港澳台），且每个省都有下级', () {
      expect(kChinaRegions.length, 34);
      for (final e in kChinaRegions.entries) {
        expect(e.value, isNotEmpty, reason: '${e.key} 没有下级');
      }
      expect(kChinaRegions.containsKey('香港特别行政区'), isTrue);
      expect(kChinaRegions.containsKey('澳门特别行政区'), isTrue);
      expect(kChinaRegions.containsKey('台湾省'), isTrue);
    });

    test('RegionSelection 文本与解析可往返', () {
      const r = RegionSelection(
          province: '广东省', city: '深圳市', district: '南山区');
      expect(r.text, '广东省 深圳市 南山区');
      expect(RegionSelection.parse(r.text), r);
    });

    test('层级不足时解析返回 null', () {
      expect(RegionSelection.parse('广东省'), isNull);
      expect(RegionSelection.parse(''), isNull);
    });
  });

  group('数据页基础信息卡', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({_authKey: _authJson()});
    });

    testWidgets('位于自我评价上方，点开进入基础信息页', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: DatabaseTab()));
      await tester.pumpAndSettle();

      expect(find.text('基础信息'), findsOneWidget);
      final basicY = tester.getTopLeft(find.text('基础信息')).dy;
      final evalY = tester.getTopLeft(find.text('自我评价')).dy;
      expect(basicY, lessThan(evalY), reason: '基础信息应在自我评价上方');

      await tester.tap(find.text('基础信息'));
      await tester.pumpAndSettle();
      expect(find.byType(BasicInfoPage), findsOneWidget);
    });
  });

  group('基础信息页', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({_authKey: _authJson()});
    });

    /// 以 push 方式打开页面，保证「保存」里的 pop 行为与真实一致
    Future<void> openPage(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BasicInfoPage()),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
    }

    testWidgets('三个填写区都在；选状态后保存并读回', (tester) async {
      await openPage(tester);

      expect(find.text('现在住址'), findsOneWidget);
      expect(find.text('工作状态'), findsOneWidget);
      expect(find.text('婚姻状况'), findsOneWidget);

      await tester.tap(find.text('在职'));
      await tester.tap(find.text('已婚'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final info = await BasicInfoStore.load();
      expect(info.workStatus, WorkStatus.employed);
      expect(info.maritalStatus, MaritalStatus.married);
    });

    testWidgets('再点一次可取消已选状态', (tester) async {
      await openPage(tester);

      await tester.tap(find.text('在职'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('在职'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect((await BasicInfoStore.load()).workStatus, isNull);
    });

    testWidgets('已保存的省市区与详细地址能回显', (tester) async {
      await BasicInfoStore.save(const BasicInfo(
          province: '广东省',
          city: '深圳市',
          district: '南山区',
          address: '科技园路 1 号'));
      await openPage(tester);

      expect(find.text('广东省 深圳市 南山区'), findsOneWidget);
      expect(find.text('科技园路 1 号'), findsOneWidget);
    });

    testWidgets('点住址弹出省市区选择器，取消不改变已选', (tester) async {
      await openPage(tester);

      await tester.tap(find.text('请选择省 / 市 / 区'));
      await tester.pumpAndSettle();

      expect(find.text('选择所在地区'), findsOneWidget);
      expect(find.text('确定'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('选择所在地区'), findsNothing);
      expect(find.text('请选择省 / 市 / 区'), findsOneWidget);
    });

    testWidgets('选择器默认定位第一项，确定后写回住址', (tester) async {
      await openPage(tester);

      await tester.tap(find.text('请选择省 / 市 / 区'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      // 默认第一项：北京市 / 市辖区 / 东城区
      expect(find.text('北京市 市辖区 东城区'), findsOneWidget);

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final info = await BasicInfoStore.load();
      expect(info.province, '北京市');
      expect(info.city, '市辖区');
      expect(info.district, '东城区');
    });
  });

  group('新增按钮为正圆', () {
    testWidgets('AppFab 使用 CircleBorder，覆盖 M3 默认的圆角方形', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          floatingActionButton: AppFab(onPressed: () {}, tooltip: '添加'),
        ),
      ));

      final fab = tester.widget<FloatingActionButton>(
          find.byType(FloatingActionButton));
      expect(fab.shape, isA<CircleBorder>());
      expect(fab.tooltip, '添加');
    });
  });
}
