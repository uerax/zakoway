import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/danmaku_item.dart';

/// Bilibili / Pakku XML 弹幕解析器 (1:1 对齐 animaku parseDanmakuXml)
class BilibiliXmlParser {
  BilibiliXmlParser._();

  static final RegExp _tagRegex = RegExp(
    r'<d\s+p="([^"]*)"[^>]*>([\s\S]*?)<\/d>',
    caseSensitive: false,
  );

  static final RegExp _decEntityRegex = RegExp(r'&#(\d+);');
  static final RegExp _hexEntityRegex = RegExp(r'&#x([0-9a-fA-F]+);');

  /// 异步在后台 Worker Isolate 解析 XML 字符串为 DanmakuItem 列表
  ///
  /// 特殊处理说明：
  /// B 站全量弹幕文件往往达到几百 KB 至数 MB，包含上万个标签。
  /// 在主 Isolate 中执行正则匹配与大规模排序会导致 UI 事件循环卡顿 100~300ms；
  /// 对于中大型文本，自动调度至 [compute] 后台线程解析，杜绝起播瞬间的掉帧阻塞。
  static Future<List<DanmakuItem>> parseAsync(String xmlContent) async {
    if (xmlContent.isEmpty) return const [];
    // 文本较小（< 16KB）时直接主线程同步解析，避免线程间内存拷贝开销
    if (xmlContent.length < 16 * 1024) {
      return parse(xmlContent);
    }
    return compute(parse, xmlContent);
  }

  /// 同步解析 XML 字符串为 DanmakuItem 列表
  static List<DanmakuItem> parse(String xmlContent) {
    if (xmlContent.isEmpty) return const [];
    final out = <DanmakuItem>[];

    final matches = _tagRegex.allMatches(xmlContent);
    for (final m in matches) {
      final p = m.group(1) ?? '';
      final rawText = m.group(2) ?? '';
      final text = decodeXmlEntities(rawText).trim();
      if (text.isEmpty) continue;

      final parts = p.split(',');
      if (parts.isEmpty) continue;

      final timeSec = double.tryParse(parts[0]);
      if (timeSec == null || !timeSec.isFinite || timeSec < 0) continue;
      final timeMs = (timeSec * 1000).round();

      final typeStr = parts.length > 1 ? parts[1].trim() : '1';
      final colorStr = parts.length > 3 ? parts[3].trim() : '';
      final senderHash = parts.length > 6 ? parts[6].trim() : null;

      final mode = switch (typeStr) {
        '4' => DanmakuMode.bottom,
        '5' => DanmakuMode.top,
        _ => DanmakuMode.scroll,
      };

      final color = _parseColorInt(colorStr);

      out.add(DanmakuItem(
        text: text,
        timeMs: timeMs,
        mode: mode,
        color: color,
        source: 'bilibili',
        senderHash: (senderHash != null && senderHash.isNotEmpty) ? senderHash : null,
      ));
    }

    out.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return out;
  }

  /// 解码常见 XML 实体字符
  static String decodeXmlEntities(String input) {
    var s = input
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");

    s = s.replaceAllMapped(_decEntityRegex, (m) {
      final numStr = m.group(1);
      if (numStr == null) return m.group(0)!;
      final code = int.tryParse(numStr);
      if (code == null) return m.group(0)!;
      return String.fromCharCode(code);
    });

    s = s.replaceAllMapped(_hexEntityRegex, (m) {
      final hexStr = m.group(1);
      if (hexStr == null) return m.group(0)!;
      final code = int.tryParse(hexStr, radix: 16);
      if (code == null) return m.group(0)!;
      return String.fromCharCode(code);
    });

    return s.replaceAll('&amp;', '&');
  }

  static Color _parseColorInt(String? colorStr) {
    if (colorStr == null || colorStr.isEmpty) return Colors.white;
    final n = int.tryParse(colorStr);
    if (n == null) return Colors.white;
    return Color(0xFF000000 | (n & 0x00FFFFFF));
  }
}
