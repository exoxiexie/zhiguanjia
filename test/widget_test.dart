// 职管家 · 基础冒烟测试
//
// 完整的 Widget / 服务测试依赖 SharedPreferences、SQLite 等平台插件，
// 需在 TestWidgetsFlutterBinding 下注入 mock，后续随功能迭代补充。
// 这里先保留一个可稳定通过的最小用例，确保测试管线可用。

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('冒烟测试：测试管线可用', () {
    expect(1 + 1, 2);
  });
}
