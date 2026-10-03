// 附件解析器冒烟验证（纯 Dart，不触发 pdfrx native）
// 用法：dart run tool/smoke_parser.dart
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import '../lib/features/chat/attachment_parser.dart';

int _fail = 0;

void _check(String name, bool ok, [String? detail]) {
  print('${ok ? "PASS" : "FAIL"}  $name${detail != null ? "  ($detail)" : ""}');
  if (!ok) _fail++;
}

Future<void> main() async {
  final tmp = Directory.systemTemp.createTempSync('zgj_smoke_');

  // 1. TXT 读取
  final txt = File('${tmp.path}/resume.txt');
  txt.writeAsStringSync('姓名：张三\n工作经验：5 年\n期望岗位：AI 产品经理');
  final t = await extractDocumentText(txt.path);
  _check('TXT 读取', t.contains('张三') && t.contains('AI 产品经理'), 'len=${t.length}');

  // 2. DOCX 解压（构造含 word/document.xml 的 zip）
  const xml = '<?xml version="1.0" encoding="UTF-8"?>'
      '<w:document xmlns:w="urn:x"><w:body>'
      '<w:p><w:r><w:t>简历：李四</w:t></w:r></w:p>'
      '<w:p><w:r><w:t>教育背景：本科</w:t></w:r></w:p>'
      '</w:body></w:document>';
  final zipBytes = ZipEncoder().encode(
    Archive()
      ..addFile(ArchiveFile('word/document.xml', xml.length, utf8.encode(xml))),
  );
  final docx = File('${tmp.path}/resume.docx');
  docx.writeAsBytesSync(zipBytes!);
  final d = await extractDocumentText(docx.path);
  _check('DOCX 解压提取', d.contains('简历：李四') && d.contains('教育背景：本科'), d.trim());

  // 3. 不支持的格式抛异常
  final xlsx = File('${tmp.path}/data.xlsx');
  xlsx.writeAsStringSync('x');
  try {
    await extractDocumentText(xlsx.path);
    _check('不支持格式抛异常', false);
  } catch (e) {
    _check('不支持格式抛异常', true, '${e.runtimeType}');
  }

  // 4. 空文档抛异常
  final empty = File('${tmp.path}/empty.txt');
  empty.writeAsStringSync('   \n  ');
  try {
    await extractDocumentText(empty.path);
    _check('空文档抛异常', false);
  } catch (e) {
    _check('空文档抛异常', true, '${e.runtimeType}');
  }

  // 5. MD 读取（走 txt 分支）
  final md = File('${tmp.path}/notes.md');
  md.writeAsStringSync('# 标题\n- 要点一');
  final m = await extractDocumentText(md.path);
  _check('MD 读取', m.contains('标题') && m.contains('要点一'));

  tmp.deleteSync(recursive: true);

  print(_fail == 0 ? '\n全部通过（$_fail 失败）' : '\n有 $_fail 项失败');
  exit(_fail == 0 ? 0 : 1);
}
