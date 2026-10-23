import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'playback_state.dart';

/// 播放器控制器统一接口契约
///
/// 从 ZakowayPlaybackController 公开 API 抽离，保持对外签名 100% 稳定，
/// 允许旧版引擎与重写核心无缝替换。
abstract interface class PlaybackController {
  /// 低频宏观控制状态通知器
  ValueNotifier<PlaybackCoreState> get core;

  /// 高频时间线状态通知器（250ms 节流）
  ValueNotifier<PlaybackTimelineState> get timeline;

  /// 视频渲染控制器通知器（提供给 Video 组件）
  ValueNotifier<VideoController?> get videoControllerNotifier;

  /// 底层 media_kit Player 实例句柄（用于平台特定或调试检查）
  Player? get rawPlayer;

  /// 控制器是否已释放销毁
  bool get isDisposed;

  /// 当前播放媒体直链 URI
  String? get currentUri;

  /// 把最近一次位置采样按到达时刻外推到当前时刻，供弹幕时钟对时使用
  Duration get extrapolatedPosition;

  /// 初始化底层播放器实例与配置
  Future<void> initialize();

  /// 起播或切集打开视频媒体
  Future<void> open(
    String uri, {
    Map<String, String>? httpHeaders,
    Duration? start,
    bool autoplay = true,
  });

  /// 播放 / 暂停切换
  Future<void> togglePlay();

  /// 播放
  Future<void> play();

  /// 暂停
  Future<void> pause();

  /// 停止当前媒体会话，终止解码与音频输出，并将渲染管线与状态重置回未出画的空闲等待态
  Future<void> stop();

  /// 跳转至指定播放进度（内置末尾 500ms 截断保护）
  Future<void> seek(Duration target);

  /// 进度条拖拽中实时更新预览位置
  void updateSeekPreview(Duration previewTarget);

  /// 结束进度拖拽，真正落地 seek
  Future<void> endSeekPreview();

  /// 相对步进跳转（快进 / 快退）
  Future<void> seekBy(Duration offset);

  /// 设置播放倍速 (0.25x ~ 3.0x)
  Future<void> setPlaybackRate(double rate);

  /// 设置音量 (0.0 ~ 1.0)
  Future<void> setVolume(double vol);

  /// 退出页面前瞬态静音底层播放器：不改写 UI 音量状态，也不落盘用户音量偏好
  Future<void> muteForExit();

  /// 切换静音
  Future<void> toggleMute();

  /// 切换画面缩放模式
  void setVideoFit(BoxFit fit);

  /// 切换 Anime4K 超分辨率画质增强模式
  Future<void> setSuperResolution(
    SuperResolutionMode mode, {
    bool persist = true,
  });

  /// 视频高清截图
  Future<Uint8List?> screenshot({String format = 'image/png'});

  /// 资源销毁与释放
  Future<void> dispose();
}
