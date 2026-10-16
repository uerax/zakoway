import 'package:flutter/material.dart';
import '../../../core/theme/m3_surface.dart';

/// Material 3 Expressive 基础表现力卡片
class M3Card extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double borderRadius;
  final M3ContainerLevel level;
  final String? pageKey;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const M3Card({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius = 20.0,
    this.level = M3ContainerLevel.low,
    this.pageKey,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final containerColor = M3Surface.container(context, level: level, pageKey: pageKey);
    final border = M3Surface.cardBorder(context);
    final shadow = M3Surface.cardShadow(context);
    final radius = BorderRadius.circular(borderRadius);

    Widget content = child;
    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }

    Widget cardWidget = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: radius,
        border: border,
        boxShadow: shadow,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: content,
      ),
    );

    if (onTap != null || onLongPress != null) {
      cardWidget = Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: radius,
          splashColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          highlightColor: theme.colorScheme.primary.withValues(alpha: 0.06),
          child: cardWidget,
        ),
      );
    }

    return cardWidget;
  }
}
