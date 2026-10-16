import 'package:flutter/material.dart';
import '../../../core/network/bangumi_client.dart';
import '../../../core/utils/appearance_manager.dart';
import '../../../core/utils/font_manager.dart';
import '../../../core/utils/responsive.dart';
import '../widgets/about_settings_card.dart';
import '../widgets/animaku_server_settings_card.dart';
import '../widgets/appearance_settings_card.dart';
import '../widgets/cache_settings_card.dart';
import '../widgets/danmaku_settings_card.dart';
import '../widgets/font_settings_card.dart';
import '../widgets/network_settings_card.dart';
import '../widgets/user_action_control_bar.dart';
import '../widgets/user_profile_header_card.dart';

/// 个人中心与设置页面（融合自 [Image #1] 视觉规范）：
/// 1. 顶部：大圆形头像 + “游客，你好” + “你还未登录哦 〒 ▽ 〒” + 右上角悬浮设置小圆钮；
/// 2. 中部：核心快捷控制栏（观看历史、我的追番、离线缓存、交流吹水）；
/// 3. 下部：网络线路、弹幕、外观、字体、缓存与关于等系统偏好设置卡片；
/// 4. 底部预留 96px 间距，适配悬浮毛玻璃胶囊底栏穿透。
class SettingsPage extends StatefulWidget {
  final BangumiClient client;
  final VoidCallback? onSettingsChanged;
  final bool isVisible;

  const SettingsPage({
    super.key,
    required this.client,
    this.onSettingsChanged,
    this.isVisible = false,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with AutomaticKeepAliveClientMixin {
  late BangumiSourcePreset _currentPreset;
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _currentPreset = widget.client.sourcePreset;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onPresetChanged(BangumiSourcePreset preset) {
    setState(() {
      _currentPreset = preset;
    });
    widget.onSettingsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final fontMgr = FontManager.instance;
    final appMgr = AppearanceManager.instance;
    final safeTop = MediaQuery.paddingOf(context).top;

    return ListenableBuilder(
      listenable: Listenable.merge([appMgr, fontMgr]),
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxSettingsWidth),
              child: ListView(
                controller: _scrollController,
                // 顶部自安全区下方自然下延，底部预留 96px 间距适配悬浮毛玻璃底栏
                padding: EdgeInsets.fromLTRB(16, safeTop + 14, 16, 96),
                children: [
                  // 1. 用户身份卡片 (大头像 + 游客你好 + 状态)
                  const UserProfileHeaderCard(),
                  const SizedBox(height: 16),

                  // 2. 核心功能控制栏 (观看历史、我的追番、数据分析、离线缓存 4 胶囊按钮)
                  const UserActionControlBar(),
                  const SizedBox(height: 10),

                  // 3. 网络线路
                  NetworkSettingsCard(
                    client: widget.client,
                    currentPreset: _currentPreset,
                    onPresetChanged: _onPresetChanged,
                    onRouteChanged: () => widget.onSettingsChanged?.call(),
                  ),

                  // 3.1 Animaku 服务端代理与解析服务
                  const AnimakuServerSettingsCard(),

                  // 4. 缓存管理
                  CacheSettingsCard(client: widget.client),

                  // 5. 弹幕服务
                  const DanmakuSettingsCard(),

                  // 6. 字体设置
                  const FontSettingsCard(),

                  // 7. 个性化外观 (图标与壁纸)
                  const AppearanceSettingsCard(),

                  // 8. 关于应用
                  const AboutSettingsCard(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
