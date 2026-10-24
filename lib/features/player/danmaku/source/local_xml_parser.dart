import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../models/danmaku_item.dart';
import 'bilibili_xml_parser.dart';

/// 本地 XML 导入解析结果
class LocalXmlParseResult {
  const LocalXmlParseResult({
    required this.fileName,
    required this.comments,
  });

  final String fileName;
  final List<DanmakuItem> comments;
}

/// 本地 XML 弹幕文件选取与解析器
class LocalXmlDanmakuParser {
  LocalXmlDanmakuParser._();

  /// 打开系统文件选择器，选取 .xml 弹幕文件并解析
  static Future<LocalXmlParseResult?> pickAndParse() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xml'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.first;
    final name = file.name;

    String content = '';
    if (file.bytes != null) {
      content = utf8.decode(file.bytes!, allowMalformed: true);
    } else if (file.path != null) {
      content = await File(file.path!).readAsString();
    }

    if (content.isEmpty) {
      throw Exception('选取的 XML 文件内容为空');
    }

    final rawList = await BilibiliXmlParser.parseAsync(content);
    final taggedList = rawList
        .map((c) => c.copyWith(source: 'upload'))
        .toList();

    return LocalXmlParseResult(
      fileName: name,
      comments: taggedList,
    );
  }
}
