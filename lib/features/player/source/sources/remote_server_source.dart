import 'package:zakoway/features/player/source/models/source_models.dart';
import 'package:zakoway/features/player/source/server/animaku_server_client.dart';
import 'package:zakoway/features/player/source/sources/video_source.dart';

/// 动态服务端代理视频源
/// 专门代理在 Animaku 服务端存在但本地客户端未内置 Dart 爬虫的新源，
/// 仅在开启「Animaku 服务端模式」时动态挂载，关闭时自动卸载，实现 0 发版热上架。
class RemoteServerSource extends VideoSource {
  RemoteServerSource({
    required this.id,
    required this.name,
    this.version = '1.0.0-remote',
    this.description = '来自 Animaku 服务端的动态扩展源',
  });

  @override
  final String id;

  @override
  final String name;

  @override
  final String version;

  @override
  final String description;

  @override
  bool get isDirect => false;

  @override
  Future<List<SourceSearchResult>> search(String keyword) {
    return AnimakuServerClient.instance.search(id, keyword);
  }

  @override
  Future<List<SourceChapterRoad>> chapters(String animeUrl) {
    return AnimakuServerClient.instance.chapters(id, animeUrl);
  }

  @override
  Future<SourceResolveResult> resolve(String episodeUrl) {
    return AnimakuServerClient.instance.resolve(id, episodeUrl);
  }
}
