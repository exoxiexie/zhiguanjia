/// 身份问句识别单元测试（对应修复：身份问题误拦截）
///
/// 历史缺陷：含「你/您」且命中任意宽泛子串即本地拦截、不调模型，
/// 导致「你能帮我介绍下这个岗位吗」等正常业务提问被替换成固定身份话术。
/// 本测试同时钉住两侧：真身份问句必须拦、业务提问必须放行。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zhiguanjia/features/chat/identity_question.dart';

void main() {
  group('normalizeQuestion 归一化', () {
    test('去标点、空白、表情并转小写', () {
      expect(normalizeQuestion('  你是谁？ '), '你是谁');
      expect(normalizeQuestion('你是谁！！！'), '你是谁');
      expect(normalizeQuestion('你是 AI 吗？'), '你是ai吗');
      expect(normalizeQuestion('你是谁😊'), '你是谁');
    });

    test('剥离开场白（含叠加、反复剥离）', () {
      expect(normalizeQuestion('请问你是谁'), '你是谁');
      expect(normalizeQuestion('你好，请问你是谁？'), '你是谁');
      expect(normalizeQuestion('你好你好你是谁'), '你是谁');
      expect(normalizeQuestion('我想问一下你是哪个模型'), '你是哪个模型');
      expect(normalizeQuestion('Hello 你是谁'), '你是谁');
    });

    test('开场白本身不剥离（避免剥离后为空）', () {
      expect(normalizeQuestion('你好'), '你好');
      expect(normalizeQuestion('请问'), '请问');
    });

    test('空输入与非中文输入', () {
      expect(normalizeQuestion(''), '');
      expect(normalizeQuestion('？？？'), '');
      expect(normalizeQuestion('   '), '');
    });
  });

  group('isIdentityQuestion 身份问句必须拦截', () {
    const shouldBlock = [
      '你是谁',
      '你是谁？',
      '你好，请问你叫什么名字？',
      '你是 AI 吗',
      '你是不是人工智能',
      '你用的是什么模型',
      '你是哪家公司开发的',
      '职管家是干什么的',
      '你能做什么',
      '你会做什么',
      '你的版本号',
    ];

    for (final q in shouldBlock) {
      test('拦截：$q', () {
        expect(isIdentityQuestion(q), isTrue);
      });
    }
  });

  group('isIdentityQuestion 业务提问必须放行（本次修复的核心）', () {
    const shouldPass = [
      // 历史误拦截的真实案例
      '你能帮我介绍下这个岗位吗',
      '你能给我推荐一个 AI 产品经理的岗位吗',
      '你能介绍一下这个行业的发展前景吗',
      '你能用什么方法帮我优化简历',
      '你觉得我适合做什么工作',
      '我想问一下薪资谈判的技巧',
      '你能帮我看看这份 JD 的要求吗',
      '这个岗位是做什么的',
      '帮我写一个自我介绍',
      '介绍一下产品经理这个职业',
      '什么叫大模型',
      'AI 产品经理的薪资大概多少',
      '你的建议是什么',
      '我该学什么技能才能转行',
      // 其他正常提问
      '帮我分析一下这份简历的优缺点',
      '面试时该怎么回答离职原因',
    ];

    for (final q in shouldPass) {
      test('放行：$q', () {
        expect(isIdentityQuestion(q), isFalse, reason: '「$q」是业务提问，不应被本地身份话术拦截');
      });
    }
  });

  test('大小写与全角符号不影响判定', () {
    expect(isIdentityQuestion('你是AI吗？'), isTrue);
    expect(isIdentityQuestion('你是ai吗'), isTrue);
  });

  test('空白输入不拦截', () {
    expect(isIdentityQuestion(''), isFalse);
    expect(isIdentityQuestion('   '), isFalse);
  });
}
