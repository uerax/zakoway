import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';
import 'package:zakoway/features/player/source/native_source_runtime.dart';

/// 视频源全局生命周期与调度中心
/// 运行于高性能 100% 纯原生 Dart 视频源内核
class SourceBundleManager extends ChangeNotifier {
  SourceBundleManager({
    NativeSourceRuntime? runtime,
    Dio? dio,
  }) : _runtime = runtime ?? NativeSourceRuntime(dio: dio);

  static SourceBundleManager? _instance;
  static SourceBundleManager get instance => _instance ??= SourceBundleManager();

  final NativeSourceRuntime _runtime;

  NativeSourceRuntime get runtime => _runtime;
  bool get isReady => _runtime.isInitialized;
  SourceBundleMeta? get meta => _runtime.bundleMeta;
  List<SourceMeta> get sources => _runtime.availableSources;

  bool _initialized = false;

  /// 原生初始化 (瞬时就绪)
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
  }

  /// 通知外部监听者（如播放页、选源抽屉）视频源列表发生了动态伸缩
  void notifySourceChanges() {
    notifyListeners();
  }
}
