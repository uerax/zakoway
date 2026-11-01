// 统一视频源数据模型

class SourceSearchResult {
  final String name;
  final String url;
  final String? cover;

  const SourceSearchResult({
    required this.name,
    required this.url,
    this.cover,
  });

  factory SourceSearchResult.fromJson(Map<String, dynamic> json) {
    return SourceSearchResult(
      name: json['name']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      cover: json['cover']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    if (cover != null) 'cover': cover,
  };
}

class SourceEpisode {
  final String name;
  final String url;

  const SourceEpisode({
    required this.name,
    required this.url,
  });

  factory SourceEpisode.fromJson(Map<String, dynamic> json) {
    return SourceEpisode(
      name: json['name']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
  };
}

class SourceChapterRoad {
  final String name;
  final List<SourceEpisode> episodes;

  const SourceChapterRoad({
    required this.name,
    required this.episodes,
  });

  factory SourceChapterRoad.fromJson(Map<String, dynamic> json) {
    final rawList = json['episodes'] as List? ?? [];
    return SourceChapterRoad(
      name: json['name']?.toString() ?? '默认线路',
      episodes: rawList
          .whereType<Map<String, dynamic>>()
          .map(SourceEpisode.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'episodes': episodes.map((e) => e.toJson()).toList(),
  };
}

/// 外挂字幕轨数据模型
class SourceSubtitleTrack {
  final String id;
  final String label;
  final String url;
  final String format; // 'ass' | 'vtt'
  final bool isDefault;

  const SourceSubtitleTrack({
    required this.id,
    required this.label,
    required this.url,
    this.format = 'ass',
    this.isDefault = false,
  });

  factory SourceSubtitleTrack.fromJson(Map<String, dynamic> json) {
    return SourceSubtitleTrack(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '外挂字幕',
      url: json['url']?.toString() ?? '',
      format: json['format']?.toString().toLowerCase() ?? 'ass',
      isDefault: json['default'] as bool? ?? json['isDefault'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'url': url,
    'format': format,
    'default': isDefault,
  };
}

class SourceResolveResult {
  final String url;
  final Map<String, String> headers;
  final String format; // 'mp4' | 'hls'
  final List<SourceSubtitleTrack> subtitles;
  final List<String> fonts;

  const SourceResolveResult({
    required this.url,
    this.headers = const {},
    this.format = 'hls',
    this.subtitles = const [],
    this.fonts = const [],
  });

  factory SourceResolveResult.fromJson(Map<String, dynamic> json) {
    final rawHeaders = json['headers'] as Map? ?? {};
    final headers = <String, String>{};
    rawHeaders.forEach((k, v) {
      if (k != null && v != null) {
        headers[k.toString()] = v.toString();
      }
    });

    final url = json['url']?.toString() ?? '';
    final rawFormat = json['format']?.toString();
    final format = rawFormat ?? (url.toLowerCase().contains('.mp4') ? 'mp4' : 'hls');

    final rawSubtitles = json['subtitles'] as List? ?? [];
    final subtitles = rawSubtitles
        .whereType<Map<String, dynamic>>()
        .map(SourceSubtitleTrack.fromJson)
        .toList();

    final rawFonts = json['fonts'] as List? ?? [];
    final fonts = rawFonts.map((e) => e.toString()).toList();

    return SourceResolveResult(
      url: url,
      headers: headers,
      format: format,
      subtitles: subtitles,
      fonts: fonts,
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'headers': headers,
    'format': format,
    if (subtitles.isNotEmpty)
      'subtitles': subtitles.map((s) => s.toJson()).toList(),
    if (fonts.isNotEmpty) 'fonts': fonts,
  };

  SourceResolveResult copyWith({
    String? url,
    Map<String, String>? headers,
    String? format,
    List<SourceSubtitleTrack>? subtitles,
    List<String>? fonts,
  }) {
    return SourceResolveResult(
      url: url ?? this.url,
      headers: headers ?? this.headers,
      format: format ?? this.format,
      subtitles: subtitles ?? this.subtitles,
      fonts: fonts ?? this.fonts,
    );
  }
}

class SourceMeta {
  final String id;
  final String name;
  final String version;
  final bool isDirect;
  final int weight;

  const SourceMeta({
    required this.id,
    required this.name,
    required this.version,
    this.isDirect = true,
    this.weight = 50,
  });

  factory SourceMeta.fromJson(Map<String, dynamic> json) {
    return SourceMeta(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      version: json['version']?.toString() ?? '1.0.0',
      isDirect: json['isDirect'] as bool? ?? true,
      weight: (json['weight'] as num?)?.toInt() ?? 50,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'isDirect': isDirect,
        'weight': weight,
      };
}

class SourceBundleMeta {
  final String version;
  final String buildTime;
  final int minApiLevel;
  final Map<String, String> adapters;

  const SourceBundleMeta({
    required this.version,
    required this.buildTime,
    required this.minApiLevel,
    required this.adapters,
  });

  factory SourceBundleMeta.fromJson(Map<String, dynamic> json) {
    final rawAdapters = json['adapters'] as Map? ?? {};
    final adapters = <String, String>{};
    rawAdapters.forEach((k, v) {
      if (k != null && v != null) {
        adapters[k.toString()] = v.toString();
      }
    });

    return SourceBundleMeta(
      version: json['version']?.toString() ?? '1.0.0',
      buildTime: json['buildTime']?.toString() ?? '',
      minApiLevel: json['minApiLevel'] as int? ?? 1,
      adapters: adapters,
    );
  }
}
