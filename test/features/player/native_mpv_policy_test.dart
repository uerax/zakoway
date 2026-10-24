import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/core/backend/native_mpv_policy.dart';

void main() {
  test('NativeMpvPolicy: 正确输出增强字幕排版与高质感渲染属性', () {
    const policy = NativeMpvPolicy();
    final props = policy.toMpvProperties(
      isMeteredNetwork: false,
      platformOverride: 'windows',
    );

    // 1. 字体保护链，防止 Windows 跌入宋体
    expect(props['sub-font'], contains('Microsoft YaHei UI'));
    expect(props['sub-font'], contains('PingFang SC'));

    // 2. 字号与防遮挡底边距
    expect(props['sub-font-size'], '48');
    expect(props['sub-margin-y'], '38');

    // 3. 高质感柔和描边与微阴影
    expect(props['sub-color'], '#FFFFFFFF');
    expect(props['sub-border-color'], '#D0000000');
    expect(props['sub-border-size'], '2.2');
    expect(props['sub-shadow-offset'], '1.2');
    expect(props['sub-shadow-color'], '#60000000');

    // 4. ASS 等比缩放与边距约束
    expect(props['sub-ass-override'], 'scale');
    expect(props['sub-ass-force-margins'], 'yes');
  });
}
