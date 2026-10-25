import 'package:flutter/material.dart';

/// 面板分节小标题
class PanelSectionHeader extends StatelessWidget {
  const PanelSectionHeader({
    super.key,
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}

/// 面板带副标题的开关行
class PanelSwitchRow extends StatelessWidget {
  const PanelSwitchRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.primaryColor,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final Color primaryColor;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: primaryColor,
              thumbColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return Colors.white70;
              }),
              trackColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return primaryColor;
                }
                return Colors.white.withValues(alpha: 0.16);
              }),
              trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}

/// 面板单选/多选胶囊按钮
class PanelOptionChip extends StatelessWidget {
  const PanelOptionChip({
    super.key,
    required this.label,
    required this.selected,
    required this.primaryColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color primaryColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: selected ? primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: primaryColor.withValues(alpha: 0.35),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    )
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ),
    );
  }
}

/// 面板复选框微芯片
class PanelCheckboxChip extends StatelessWidget {
  const PanelCheckboxChip({
    super.key,
    required this.label,
    required this.checked,
    required this.primaryColor,
    required this.onTap,
  });

  final String label;
  final bool checked;
  final Color primaryColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: checked
              ? primaryColor.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: checked
                ? primaryColor.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.12),
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: checked ? Colors.white : Colors.white60,
            fontSize: 10.5,
            fontWeight: checked ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// 面板滑块调节行
class PanelSliderRow extends StatelessWidget {
  const PanelSliderRow({
    super.key,
    required this.title,
    required this.valText,
    required this.value,
    required this.min,
    required this.max,
    required this.primaryColor,
    required this.onChanged,
  });

  final String title;
  final String valText;
  final double value;
  final double min;
  final double max;
  final Color primaryColor;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 11.5),
              ),
              Text(
                valText,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.5),
              activeTrackColor: primaryColor,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
