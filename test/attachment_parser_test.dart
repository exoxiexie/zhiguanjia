/// 附件解析器测试
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhiguanjia/features/chat/attachment_parser.dart';

void main() {
  group('extractDocumentText', () {
    test('TXT 直接读取', () async {
      final f = File('${Directory.systemTemp.path}/resume_${DateTime.now().microsecondsSinceEpoch}.txt');
      f.writeAsStringSync('姓名：张三\n工作经验：5 年\n期望岗位：AI 产品经理');
      final text = await extractDocumentText(f.path);
      expect(text, contains('张三'));
      expect(text, contains('AI 产品经理'));
      f.deleteSync();
    });

    test('DOCX 解压提取 document.xml 文本', () async {
      final dir = Directory.systemTemp.createTempSync('docx_test_');
      const xml =
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<w:document xmlns:w="urn:x"><w:body>'
          '<w:p><w:r><w:t>简历：李四</w:t></w:r></w:p>'
          '<w:p><w:r><w:t>教育背景：本科</w:t></w:r></w:p>'
          '</w:body></w:document>';
      final bytes = ZipEncoder().encode(
        Archive()
          ..addFile(ArchiveFile(
              'word/document.xml', xml.length, utf8.encode(xml))),
      );
      final f = File('${dir.path}/resume.docx');
      f.writeAsBytesSync(bytes!);

      final text = await extractDocumentText(f.path);
      expect(text, contains('简历：李四'));
      expect(text, contains('教育背景：本科'));
      dir.deleteSync(recursive: true);
    });

    test('不支持的格式抛异常', () async {
      final f = File('${Directory.systemTemp.path}/data_${DateTime.now().microsecondsSinceEpoch}.xlsx');
      f.writeAsStringSync('x');
      await expectLater(extractDocumentText(f.path), throwsException);
      f.deleteSync();
    });

    test('空文档抛异常', () async {
      final f = File('${Directory.systemTemp.path}/empty_${DateTime.now().microsecondsSinceEpoch}.txt');
      f.writeAsStringSync('   \n  ');
      await expectLater(extractDocumentText(f.path), throwsException);
      f.deleteSync();
    });
  });
}
