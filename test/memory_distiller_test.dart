/// MemoryDistiller.parseResult（提炼结果 JSON 容错解析）单元测试
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zhiguanjia/features/memory/memory_distiller.dart';

void main() {
  group('parseResult 容错解析', () {
    test('标准 JSON 直接解析', () {
      const raw =
          '{"has_memory": true, "title": "产品定位", "weight": 80, '
          '"tags": ["AI管家", "产品"], "category": "产品定位", '
          '"content": "智懂你定位为垂类AI管家集合"}';
      final r = MemoryDistiller.parseResult(raw);
      expect(r, isNotNull);
      expect(r!['has_memory'], true);
      expect(r['title'], '产品定位');
      expect(r['weight'], 80);
      expect((r['tags'] as List).length, 2);
    });

    test('带 Markdown 围栏可解析', () {
      const raw = '```json\n{"has_memory": true, "title": "记忆A"}\n```';
      final r = MemoryDistiller.parseResult(raw);
      expect(r, isNotNull);
      expect(r!['title'], '记忆A');
    });

    test('前后有杂散文字可解析', () {
      const raw = '好的，以下是提炼结果：\n{"has_memory": true, '
          '"title": "记忆B", "weight": 60}\n完毕。';
      final r = MemoryDistiller.parseResult(raw);
      expect(r, isNotNull);
      expect(r!['title'], '记忆B');
      expect(r['weight'], 60);
    });

    test('has_memory=false 时返回 false 语义字段', () {
      const raw = '{"has_memory": false}';
      final r = MemoryDistiller.parseResult(raw);
      expect(r, isNotNull);
      expect(r!['has_memory'], false);
    });

    test('空输入返回 null', () {
      expect(MemoryDistiller.parseResult(''), isNull);
      expect(MemoryDistiller.parseResult('   \n  '), isNull);
    });

    test('非法 JSON 返回 null', () {
      expect(MemoryDistiller.parseResult('这不是JSON'), isNull);
      expect(MemoryDistiller.parseResult('{broken json'), isNull);
    });

    test('无 has_memory 字段的 JSON 也能解析出 Map', () {
      const raw = '{"title": "只有标题"}';
      final r = MemoryDistiller.parseResult(raw);
      expect(r, isNotNull);
      expect(r!['title'], '只有标题');
    });
  });
}
