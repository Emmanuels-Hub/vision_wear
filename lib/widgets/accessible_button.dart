import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class AccessibleButton extends StatelessWidget {
  const AccessibleButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.subtitle,
    this.color,
    this.semanticHint,
    this.isPrimary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final String? subtitle;
  final Color? color;
  final String? semanticHint;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final buttonColor = color ??
        (isPrimary
            ? context.colors.primary
            : context.colors.surfaceContainerHighest);

    // Derive the foreground from the actual fill so the label stays legible in
    // both themes and against a caller-supplied colour. The two candidates come
    // from the scheme rather than being literal black and white, so a themed
    // surface still gets a themed label.
    final foreground =
        ThemeData.estimateBrightnessForColor(buttonColor) == Brightness.dark
            ? context.colors.onInverseSurface
            : context.colors.onSurface;

    return Semantics(
      button: true,
      label: label,
      hint: semanticHint ?? subtitle,
      child: Material(
        color: buttonColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 32, color: foreground),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: foreground,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 14,
                            color: foreground.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: foreground.withValues(alpha: 0.7)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
