/// 对话模块 · mdToCnText（Markdown → 中文排版）单元测试
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:zhiguanjia/contracts/chat_service.dart';

void main() {
  test('去掉 Markdown 标记并按中文习惯编号', () {
    const input = '# 产品经理的发展路径\n\n'
        '**核心建议**：持续沉淀。\n\n'
        '1. 明确目标\n'
        '2. 提升技能\n'
        '   - 硬技能：数据分析\n'
        '   - 软技能：沟通\n'
        '3. 积累作品\n\n'
        '> 引用：长期主义\n\n'
        '**加粗**和*斜体*以及`代码`，还有[链接文字](https://x.com)\n';
    final out = mdToCnText(input);
    expect(out, isNot(contains('#')));
    expect(out, isNot(contains('*')));
    expect(out, isNot(contains('`')));
    expect(out, isNot(contains('>')));
    expect(out, contains('一、明确目标'));
    expect(out, contains('二、提升技能'));
    expect(out, contains('三、积累作品'));
    expect(out, contains('· 硬技能：数据分析'));
    expect(out, contains('核心建议：持续沉淀。'));
    expect(out, contains('加粗和斜体以及代码，还有链接文字'));
  });

  test('普通文本保持不变', () {
    const input = '你好，这是一段普通的中文文本。';
    expect(mdToCnText(input), input);
  });
}
