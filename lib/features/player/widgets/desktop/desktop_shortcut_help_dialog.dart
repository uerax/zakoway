import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../core/utils/font_manager.dart';

/// 桌面端播放器快捷键帮助对话框
class DesktopShortcutHelpDialog extends StatelessWidget {
  const DesktopShortcutHelpDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (context) => const DesktopShortcutHelpDialog(),
    );
  }

  static const List<(String, String)> _shortcuts = [
    ('Space / K', '播放 / 暂停'),
    ('F', '切换全屏'),
    ('T', '切换剧场模式'),
    ('Esc', '关闭面板 / 退出全屏 / 返回'),
    ('← / →', '快退 / 快进 5 秒'),
    ('J / L', '快退 / 快进 10 秒'),
    ('↑ / ↓', '音量增加 / 减小 5%'),
    ('M', '静音 / 取消静音'),
    ('[ / ]', '上一集 / 下一集'),
    ('< / >', '降低 / 提高播放倍速'),
    ('0 ~ 9', '跳转至进度 0% ~ 90%'),
    ('D', '切换弹幕状态（全量/精简/关闭）'),
    ('C', '截取当前画面'),
    ('S', '跳过片头 / 片尾'),
    ('?', '显示本快捷键指南'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: 480,
            constraints: const BoxConstraints(maxHeight: 560),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xF21C1C24) : Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.14)
                    : Colors.black.withValues(alpha: 0.08),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.2),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.keyboard_outlined, color: primaryColor, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        '键盘快捷键指南',
                        style: appTextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        splashRadius: 18,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Table(
                        columnWidths: const {
                          0: IntrinsicColumnWidth(),
                          1: FlexColumnWidth(),
                        },
                        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                        children: [
                          for (final item in _shortcuts)
                            TableRow(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 5.5, horizontal: 4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.10)
                                          : Colors.black.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isDark ? Colors.white12 : Colors.black12,
                                        width: 0.5,
                                      ),
                                    ),
                                    child: Text(
                                      item.$1,
                                      style: appTextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 5.5, horizontal: 12),
                                  child: Text(
                                    item.$2,
                                    style: appTextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                      color: isDark ? Colors.white70 : Colors.black54,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
