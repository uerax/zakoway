import 'dart:ui';
import 'package:flutter/material.dart';

import '../../../core/services/update_manager.dart';
import '../../../core/utils/font_manager.dart';

/// GitHub Release 下载加速前缀配置弹窗（严格遵循字体安全规范）
class UpdatePrefixDialog extends StatefulWidget {
  const UpdatePrefixDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (context) => const UpdatePrefixDialog(),
    );
  }

  @override
  State<UpdatePrefixDialog> createState() => _UpdatePrefixDialogState();
}

class _UpdatePrefixDialogState extends State<UpdatePrefixDialog> {
  late final TextEditingController _controller;
  final UpdateManager _updateMgr = UpdateManager.instance;

  static const List<(String, String)> _presets = [
    ('直连', ''),
    ('ghproxy.net', 'https://ghproxy.net/'),
    ('gh-proxy.com', 'https://gh-proxy.com/'),
    ('kkgithub.com', 'https://kkgithub.com/'),
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _updateMgr.downloadPrefix);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              width: 440,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xF21C1C24)
                    : Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(24),
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
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 头部标题与图标
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.speed_rounded,
                              color: primaryColor,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '下载加速镜像前缀',
                            style: appTextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // 说明文字
                      Text(
                        '国内直连 GitHub Releases 缓慢或超时时，可配置下载加速代理。下载时将自动拼接在官方 Release 直链前。留空即为官方直连。',
                        style: appTextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.8),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // 输入框
                      TextField(
                        controller: _controller,
                        onChanged: (_) => setState(() {}),
                        style: appTextStyle(
                          fontSize: 13.5,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          hintText: '例如: https://ghproxy.net/',
                          hintStyle: appTextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.5),
                          ),
                          filled: true,
                          fillColor: isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.black.withValues(alpha: 0.04),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.10)
                                  : Colors.black.withValues(alpha: 0.08),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.10)
                                  : Colors.black.withValues(alpha: 0.08),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: primaryColor,
                              width: 1.5,
                            ),
                          ),
                          suffixIcon: _controller.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _controller.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // 快捷预设按钮
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: _presets.map((preset) {
                          final isSelected =
                              _controller.text.trim() == preset.$2;
                          return ChoiceChip(
                            showCheckmark: false,
                            label: Text(
                              preset.$1,
                              style: appTextStyle(
                                fontSize: 11.5,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: isSelected
                                    ? Colors.white
                                    : (isDark
                                        ? Colors.white70
                                        : Colors.black87),
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: primaryColor,
                            onSelected: (selected) {
                              if (selected) {
                                _controller.text = preset.$2;
                                setState(() {});
                              }
                            },
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 14),

                      // 效果预览
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.04)
                              : Colors.black.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '当前生效下载链接预览：\n${_buildPreviewUrl()}',
                          style: appTextStyle(
                            fontSize: 11,
                            height: 1.4,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.7),
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      const SizedBox(height: 20),

                      // 底部保存与取消
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              '取消',
                              style: appTextStyle(
                                fontSize: 14,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () async {
                              await _updateMgr
                                  .setDownloadPrefix(_controller.text.trim());
                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }
                            },
                            child: Text(
                              '保存设置',
                              style: appTextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _buildPreviewUrl() {
    final prefix = _controller.text.trim();
    const sample =
        'https://github.com/uerax/zakoway/releases/download/v1.0.0/Zakoway.zip';
    if (prefix.isEmpty) return sample;
    final normalized = prefix.endsWith('/') ? prefix : '$prefix/';
    return '$normalized$sample';
  }
}
