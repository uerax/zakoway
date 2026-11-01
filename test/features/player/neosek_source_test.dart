import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/controller/playback_controller.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';
import 'package:zakoway/features/player/source/native_source_runtime.dart';
import 'package:zakoway/features/player/source/server/adapters/neosek_animaku_adapter.dart';
import 'package:zakoway/features/player/source/sources/neosek_source.dart';
import 'package:zakoway/features/player/widgets/video_source_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('测试 NeosekSource 属性、直连组与 NativeSourceRuntime 注册', () {
    final source = NeosekSource();
    expect(source.id, 'neosekai');
    expect(source.name, 'neosek');
    expect(source.isDirect, isFalse);
    expect(source.description, contains('香港 CDN'));

    final runtime = NativeSourceRuntime();
    expect(runtime.isLocalSource('neosekai'), isTrue);

    final defaultItems = getDefaultSourceItems();
    final neosekItem = defaultItems.firstWhere((i) => i.id == 'neosekai');
    expect(neosekItem.name, 'neosek');
    expect(neosekItem.isDirect, isFalse);
  });

  test('测试 NeosekSource 搜索、分集与直链解析 (优先 original 原画)', () async {
    final source = NeosekSource();

    // 1. 验证搜索 (芙莉莲)
    final hits = await source.search('芙莉莲');
    expect(hits, isNotEmpty);
    expect(hits.first.name, contains('芙莉莲'));
    expect(hits.first.url, contains('neosek.ai/anime/'));

    // 2. 验证章节列表
    final roads = await source.chapters(hits.first.url);
    expect(roads, isNotEmpty);
    expect(roads.first.name, 'Neosek');
    expect(roads.first.episodes, isNotEmpty);

    final firstEp = roads.first.episodes.first;
    expect(firstEp.name, isNotEmpty);
    expect(firstEp.url, contains('/anime/'));

    // 3. 验证直链解析
    final resolved = await source.resolve(firstEp.url);
    expect(resolved.url, startsWith('https://'));
    expect(resolved.url, anyOf(contains('.m3u8'), contains('.mkv'), contains('.mp4')));
    expect(resolved.format, anyOf('hls', 'mp4'));
    expect(resolved.headers['Referer'], contains('neosek.ai'));

    // 4. 针对用户真实报错单集 (FX战士久留美 1272/1903) 回归测试
    final resolvedKurumi = await source.resolve('https://neosek.ai/anime/1272/1903');
    expect(resolvedKurumi.url, startsWith('https://'));
    expect(resolvedKurumi.url, anyOf(contains('.m3u8'), contains('.mkv'), contains('.mp4')));
    expect(resolvedKurumi.format, anyOf('hls', 'mp4'));
    expect(resolvedKurumi.subtitles, isNotEmpty);
    expect(resolvedKurumi.fonts, isNotEmpty);
  });

  test('测试 Neosek 39228/94412 ASS与VTT外挂字幕解析、字体包以及播放器ASS简中优先决选', () async {
    final source = NeosekSource();

    // 1. 本地直连解析
    final resolved = await source.resolve('https://neosek.ai/anime/39228/94412');
    expect(resolved.url, startsWith('https://'));
    expect(resolved.subtitles, isNotEmpty);
    expect(resolved.fonts, isNotEmpty);

    // 验证包含 ASS 与 VTT 字幕
    final hasAss = resolved.subtitles.any((s) => s.format == 'ass');
    final hasVtt = resolved.subtitles.any((s) => s.format == 'vtt');
    expect(hasAss, isTrue);
    expect(hasVtt, isTrue);

    // 验证播放器自动决选：必须命中 Chinese(Simplified) 且为 ASS 格式
    final bestTrack = ZakowayPlaybackController.selectBestSubtitle(
      externalSubtitles: resolved.subtitles,
    );
    expect(bestTrack, isNotNull);
    expect(bestTrack!.format, 'ass');
    expect(bestTrack.label, contains('Chinese(Simplified)'));

    // 2. 验证 Animaku 适配器模式下的字幕自愈补齐与 ASS 优先排序
    final adapter = NeosekAnimakuAdapter(localSource: source);
    final transformed = await adapter.transformResolve(
      resolved.copyWith(subtitles: const [], fonts: const []),
      episodeUrl: 'https://neosek.ai/anime/39228/94412',
    );
    expect(transformed.subtitles, isNotEmpty);
    expect(transformed.fonts, isNotEmpty);
    // 默认轨为 ASS 简中
    final defaultSub = transformed.subtitles.firstWhere((s) => s.isDefault);
    expect(defaultSub.format, 'ass');
    expect(defaultSub.label, contains('Chinese(Simplified)'));
  });

  test('测试 Neosek 17024/44611 纯VTT、标“中文”字样字幕自动决选与播放器挂载', () async {
    final source = NeosekSource();

    // 1. 直连解析
    final resolved = await source.resolve('https://neosek.ai/anime/17024/44611');
    expect(resolved.url, startsWith('https://'));
    expect(resolved.subtitles, isNotEmpty);
    expect(resolved.subtitles.length, greaterThanOrEqualTo(2));

    // 确认该番剧是纯 VTT、无 ASS、label 标为“中文”
    final allVtt = resolved.subtitles.every((s) => s.format == 'vtt');
    expect(allVtt, isTrue);
    expect(resolved.subtitles.first.label, '中文');

    // 2. 验证播放器自动决选：必须命中并自动挂载默认的“中文”字幕
    final bestTrack = ZakowayPlaybackController.selectBestSubtitle(
      externalSubtitles: resolved.subtitles,
    );
    expect(bestTrack, isNotNull);
    expect(bestTrack!.label, '中文');
    expect(bestTrack.format, 'vtt');
    expect(bestTrack.id, contains('zh'));

    // 3. 验证 Animaku 适配器模式下的字幕自愈补齐与排序
    final adapter = NeosekAnimakuAdapter(localSource: source);
    final transformed = await adapter.transformResolve(
      resolved.copyWith(subtitles: const [], fonts: const []),
      episodeUrl: 'https://neosek.ai/anime/17024/44611',
    );
    expect(transformed.subtitles, isNotEmpty);
    final defaultSub = transformed.subtitles.firstWhere((s) => s.isDefault);
    expect(defaultSub.label, '中文');
    expect(defaultSub.format, 'vtt');
  });

  test('测试 language: zh 兜底与 default: true 终极兜底逻辑', () {
    // 1. label 为空但 language 为 zh 时，自动兜底为“中文”
    final parsed = NeosekSource.parseSubtitlesAndFonts([
      {
        'video': {
          'subtitles': [
            {
              'id': 'zh-unk',
              'language': 'zh',
              'label': null,
              'default': true,
              'vtt': {'url': 'https://example.com/sub.vtt'},
            }
          ]
        }
      }
    ]);
    expect(parsed.subtitles, isNotEmpty);
    expect(parsed.subtitles.first.label, '中文');
    expect(parsed.subtitles.first.isDefault, isTrue);

    // 2. 若字幕完全未匹配到任何简体/通用/繁体规则，优先拿 default: true 做终极兜底
    final weirdSubtitles = [
      const SourceSubtitleTrack(
        id: 'track-1',
        label: 'Unknown Language Track',
        url: 'https://example.com/sub1.vtt',
        format: 'vtt',
        isDefault: false,
      ),
      const SourceSubtitleTrack(
        id: 'track-2',
        label: 'Special Feature Track',
        url: 'https://example.com/sub2.vtt',
        format: 'vtt',
        isDefault: true,
      ),
    ];
    final selected = ZakowayPlaybackController.selectBestSubtitle(
      externalSubtitles: weirdSubtitles,
    );
    expect(selected, isNotNull);
    expect(selected!.id, 'track-2');
    expect(selected.isDefault, isTrue);
  });
}
