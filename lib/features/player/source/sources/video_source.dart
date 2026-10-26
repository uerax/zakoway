import 'dart:convert';
import 'package:zakoway/features/player/source/models/source_models.dart';

/// 安全解析任意 Dio 响应（无论服务器以 text/html、text/plain 或 application/json 返回）
Map<String, dynamic>? parseJsonMap(dynamic data) {
  if (data == null) return null;
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return Map<String, dynamic>.from(data);
  if (data is String && data.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  return null;
}

/// 模拟 JavaScript 原生 unescape() 函数（精准支持 %uXXXX 16位 Unicode 与标准 %XX 百分比解码）
String jsUnescape(String input) {
  if (input.isEmpty) return input;
  // 1. 替换 %uXXXX 为对应的 Unicode 字符
  final withUnicode = input.replaceAllMapped(
    RegExp(r'%u([0-9a-fA-F]{4})'),
    (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
  );
  // 2. 解码标准的百分比编码 (%XX)
  try {
    return Uri.decodeQueryComponent(withUnicode);
  } catch (_) {
    try {
      return Uri.decodeComponent(withUnicode);
    } catch (_) {
      return withUnicode.replaceAllMapped(
        RegExp(r'%([0-9a-fA-F]{2})'),
        (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
      );
    }
  }
}

/// 统一视频源抽象接口 (纯原生 Dart，零 QuickJS 损耗)
abstract class VideoSource {
  String get id;
  String get name;
  String get version;
  String get description;

  /// 视频源基础排序权重 (默认 50，高权重优先探活与前置展示)
  int get weight => 50;

  /// 是否支持国内网络直连（true: 国内可直连；false: 需代理/海外节点）
  bool get isDirect => true;

  /// 是否优先使用系统 WebView 进行视频流嗅探（针对无公开 API 或挂有复杂反爬的网页源）
  bool get preferWebviewSniff => false;

  Future<List<SourceSearchResult>> search(String keyword);
  Future<List<SourceChapterRoad>> chapters(String animeUrl);
  Future<SourceResolveResult> resolve(String episodeUrl);

  /// 清空视频源私有缓存（默认空实现）
  void clearCache() {}

  SourceMeta toMeta() => SourceMeta(
        id: id,
        name: name,
        version: version,
        isDirect: isDirect,
        weight: weight,
      );
}
