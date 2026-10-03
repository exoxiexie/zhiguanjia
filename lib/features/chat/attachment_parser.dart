/// 附件解析模块 · 文档文本提取
///
/// 目录隔离：本模块只属于 chat 域，负责把用户选择的本地文档
/// （PDF / Word / 纯文本）解析为可注入模型的纯文本。
/// 不依赖其他业务模块，纯函数 + 文件系统。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// 文档文本注入模型前的截断上限（字符数，控制 token 量）
const int kMaxDocChars = 8000;

/// 支持解析的文档扩展名（小写，不含点）
const Set<String> kSupportedDocExts = {'pdf', 'docx', 'txt', 'md', 'text'};

/// 从文件路径解析本地文档为纯文本；解析失败或格式不支持时抛异常。
///
/// 先读取文件字节，再委托 [extractDocumentTextFromBytes] 解析。
Future<String> extractDocumentText(String filePath) async {
  final bytes = await File(filePath).readAsBytes();
  final ext = filePath.toLowerCase().split('.').last;
  return extractDocumentTextFromBytes(bytes, ext);
}

/// 从字节数据解析文档为纯文本；解析失败或格式不支持时抛异常。
///
/// 适用于 U 盘/云存储等没有真实文件路径、只有 content:// URI 的场景。
/// - PDF：逐页提取文本层（扫描件无文本层会得到空/极少文本）
/// - DOCX：解压 zip 读取 word/document.xml 并剥离 XML 标签
/// - TXT/MD：直接读取原文
/// 返回文本按 [kMaxDocChars] 截断。
Future<String> extractDocumentTextFromBytes(
    Uint8List bytes, String extension) async {
  final ext = extension.toLowerCase();
  final String text;
  switch (ext) {
    case 'pdf':
      text = _extractPdfFromBytes(bytes);
    case 'docx':
      text = _extractDocxFromBytes(bytes);
    case 'txt':
    case 'md':
    case 'text':
      text = utf8.decode(bytes, allowMalformed: true);
    default:
      throw Exception('暂不支持该文件格式：.$ext（支持 PDF / Word / TXT）');
  }
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    throw Exception('未从文档中解析出文本，可能是扫描件或加密文档');
  }
  return trimmed.length <= kMaxDocChars
      ? trimmed
      : trimmed.substring(0, kMaxDocChars);
}

/// PDF 文本提取（syncfusion 纯 Dart 逐页提取文本层）
String _extractPdfFromBytes(Uint8List bytes) {
  final doc = PdfDocument(inputBytes: bytes);
  try {
    final extractor = PdfTextExtractor(doc);
    return extractor.extractText(
      startPageIndex: 0,
      endPageIndex: doc.pages.count - 1,
    );
  } finally {
    doc.dispose();
  }
}

/// DOCX 文本提取：zip 解压 → word/document.xml → 剥离 XML 标签
String _extractDocxFromBytes(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final entry = archive.findFile('word/document.xml');
  if (entry == null) {
    throw Exception('DOCX 结构异常：未找到 document.xml');
  }
  final content = entry.content;
  final xml = content is String ? content : utf8.decode(content);
  // 段落标签 <w:p> 替换为换行，其余标签剥离
  var s = xml.replaceAll(RegExp(r'</w:p>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<[^>]+>', dotAll: true), ' ');
  // 实体解码
  s = s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ');
  // 压缩空白与空行
  s = s.replaceAll(RegExp(r'[ \t\r\f\v]+'), ' ');
  s = s.replaceAll(RegExp(r'\n\s*\n+'), '\n');
  return s.trim();
}
