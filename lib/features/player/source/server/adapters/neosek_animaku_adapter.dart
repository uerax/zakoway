import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';
import 'package:zakoway/features/player/source/sources/neosek_source.dart';
import 'animaku_source_adapter.dart';

const String _kDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

/// neosek.ai (neosek) Animaku 服务端模式专属适配器
///
/// 特殊处理说明：
/// 1. Neosek 源站核心特性与痛点：
///    - 该源提供 1080P 原画/无修 MP4 直链，起播秒开且支持快速 Seek；
///    - 但原始 MP4 为日文生肉（不带中文字幕），字幕以外挂 ASS 特效字幕与 WebVTT 文件提供；
///    - 该站 HLS 切片中的长分片 VTT 在 libmpv 解析时容易因交错时间戳导致丢帧黑屏；
/// 2. 适配器职责契约：
///    - 注入与规范化源站防盗链 Referer（'https://neosek.ai/'）与标准 UA；
///    - 优先采用服务端返回的 `subtitle` 契约，对多字幕轨做智能排序，优先激活 ASS 简中特效字幕为默认轨；
///    - 【无缝兜底 Fallback】：若服务端因版本未更新或临时漏抓未提供外挂字幕（result.subtitles 为空），
///      通过轻量级异步请求从 Neosek 源站 units/items 提取外挂字幕与字体包补齐，实现客户端双重自愈；
///    - 在服务端彻底不可用（如日本 IP 封禁阻断）时，通过本地 NeosekSource 进行局部 Fallback 兜底。
class NeosekAnimakuAdapter extends AnimakuSourceAdapter {
  NeosekAnimakuAdapter({Dio? dio, NeosekSource? localSource})
      : _dio = dio ?? Dio(),
        _localSource = localSource ?? NeosekSource();

  final Dio _dio;
  final NeosekSource _localSource;
  static const String _baseUrl = 'https://neosek.ai';

  @override
  String get sourceId => 'neosekai';

  void _log(String message) {
    debugPrint('[NeosekAnimakuAdapter] $message');
  }

  @override
  Future<SourceResolveResult> transformResolve(
    SourceResolveResult result, {
    required String episodeUrl,
  }) async {
    final playUrl = result.url.trim();
    if (playUrl.isEmpty) return result;

    // 1. 规范化防盗链请求头（必须包含 Referer: https://neosek.ai/ 与标准 UA）
    final mergedHeaders = Map<String, String>.from(result.headers);
    if (!mergedHeaders.containsKey('Referer') || mergedHeaders['Referer']!.isEmpty) {
      mergedHeaders['Referer'] = '$_baseUrl/';
    }
    if (!mergedHeaders.containsKey('User-Agent') || mergedHeaders['User-Agent']!.isEmpty) {
      mergedHeaders['User-Agent'] = _kDefaultUserAgent;
    }

    final format = result.format == 'mp4' || playUrl.contains('.mp4') ? 'mp4' : 'hls';
    List<SourceSubtitleTrack> subtitles = List.from(result.subtitles);
    List<String> fonts = List.from(result.fonts);

    // 2. 若服务端已经返回字幕轨，清洗并确保 ASS 简中特效字幕为 default 首选轨
    if (subtitles.isNotEmpty) {
      subtitles = _optimizeSubtitlePriorities(subtitles);
      _log('成功采纳服务端返回的 ${subtitles.length} 条字幕轨');
    } else {
      // 3. 【无缝兜底 Fallback】：服务端未给字幕（旧版本服务端），尝试从 Neosek 源站提取补齐
      try {
        final enriched = await _fetchSubtitlesFromSource(episodeUrl);
        if (enriched.subtitles.isNotEmpty) {
          subtitles = _optimizeSubtitlePriorities(enriched.subtitles);
          fonts = enriched.fonts;
          _log('成功通过源站 units API 兜底补齐 ${subtitles.length} 条外挂字幕轨');
        }
      } catch (e) {
        _log('源站字幕补齐兜底轻量跳过: $e');
      }
    }

    return SourceResolveResult(
      url: playUrl,
      headers: mergedHeaders,
      format: format,
      subtitles: subtitles,
      fonts: fonts,
    );
  }

  /// 服务端直链解析异常兜底（如服务端触发日本 IP 封禁或临时故障，尝试本地直连源兜底）
  @override
  Future<SourceResolveResult?> onResolveFallback(
    Object error, {
    required String episodeUrl,
  }) async {
    _log('服务端解析异常 ($error)，尝试本地 NeosekSource 兜底...');
    try {
      final localResult = await _localSource.resolve(episodeUrl);
      if (localResult.url.isNotEmpty) {
        _log('本地 NeosekSource 兜底成功: ${localResult.url}');
        return await transformResolve(localResult, episodeUrl: episodeUrl);
      }
    } catch (e) {
      _log('本地 NeosekSource 兜底失败: $e');
    }
    return null;
  }

  /// 对字幕轨做智能排序与默认标记：
  /// 优先选择 ASS 格式且标签包含「简/chs/hans/sc」的字幕为默认轨；
  /// 保证有且仅有一个 default 轨，无特殊匹配时回退首条。
  List<SourceSubtitleTrack> _optimizeSubtitlePriorities(List<SourceSubtitleTrack> list) {
    if (list.isEmpty) return list;

    int defaultIndex = -1;

    // 1. 优先找 ASS 简中
    defaultIndex = list.indexWhere((s) {
      final label = s.label.toLowerCase();
      final isHans = label.contains('简') || label.contains('chs') || label.contains('hans') || label.contains('sc');
      return s.format.toLowerCase() == 'ass' && isHans;
    });

    // 2. 次选任意简中
    if (defaultIndex == -1) {
      defaultIndex = list.indexWhere((s) {
        final label = s.label.toLowerCase();
        return label.contains('简') || label.contains('chs') || label.contains('hans') || label.contains('sc');
      });
    }

    // 3. 次选任意标记了 default 的
    if (defaultIndex == -1) {
      defaultIndex = list.indexWhere((s) => s.isDefault);
    }

    // 4. 保底第一条
    if (defaultIndex == -1) {
      defaultIndex = 0;
    }

    final optimized = <SourceSubtitleTrack>[];
    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      optimized.add(SourceSubtitleTrack(
        id: item.id.isNotEmpty ? item.id : 'sub-$i',
        label: item.label,
        url: item.url,
        format: item.format,
        isDefault: i == defaultIndex,
      ));
    }
    return optimized;
  }

  /// 从 Neosek 源站 units items 提取外挂字幕与字体包（用于旧版服务端兼容）
  Future<({List<SourceSubtitleTrack> subtitles, List<String> fonts})> _fetchSubtitlesFromSource(
    String episodeUrl,
  ) async {
    final match = RegExp(r'/anime/\d+/(\d+)').firstMatch(episodeUrl) ??
        RegExp(r'(\d+)$').firstMatch(episodeUrl);
    if (match == null) {
      return (subtitles: <SourceSubtitleTrack>[], fonts: <String>[]);
    }
    final unitId = match.group(1)!;

    final res = await _dio.get<dynamic>(
      '$_baseUrl/api/v1/units/$unitId/items',
      options: Options(
        headers: {
          'User-Agent': _kDefaultUserAgent,
          'Accept': 'application/json, text/plain, */*',
          'Referer': '$_baseUrl/',
        },
        sendTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 4),
      ),
    );

    final resData = res.data is Map ? res.data as Map : null;
    final items = (resData?['data']?['items'] as List?) ?? [];

    final subs = <SourceSubtitleTrack>[];
    final fonts = <String>[];

    for (final item in items.whereType<Map<String, dynamic>>()) {
      // 提取字幕列表 (兼容 subtitles 与 captions 字段)
      final rawSubs = (item['subtitles'] as List?) ?? (item['captions'] as List?) ?? [];
      for (final s in rawSubs.whereType<Map<String, dynamic>>()) {
        final subUrl = s['url']?.toString() ?? s['file']?['url']?.toString();
        if (subUrl != null && subUrl.isNotEmpty) {
          final label = s['label']?.toString() ?? s['name']?.toString() ?? s['language']?.toString() ?? '外挂字幕';
          final format = (s['format']?.toString() ?? (subUrl.endsWith('.ass') ? 'ass' : 'vtt')).toLowerCase();
          final isDef = s['default'] as bool? ?? false;
          subs.add(SourceSubtitleTrack(
            id: s['id']?.toString() ?? 'sub-${subs.length}',
            label: label,
            url: subUrl,
            format: format,
            isDefault: isDef,
          ));
        }
      }

      // 提取字体包列表
      final rawFonts = (item['fonts'] as List?) ?? [];
      for (final f in rawFonts) {
        final fontUrl = f is Map ? f['url']?.toString() : f?.toString();
        if (fontUrl != null && fontUrl.isNotEmpty) {
          fonts.add(fontUrl);
        }
      }
    }

    return (subtitles: subs, fonts: fonts);
  }
}
