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

  /// An optional accent for a button that needs to stand out from its
  /// neighbours (e.g. the obstacle scan). Used to tint the icon and a left
  /// edge, not to flood the whole fill — a wall of differently-coloured
  /// blocks is harder to scan than a uniform list with one marked item.
  final Color? color;
  final String? semanticHint;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;

    final Color fill;
    final Color foreground;
    final Color iconColor;
    if (isPrimary) {
      fill = cs.primary;
      foreground = cs.onPrimary;
      iconColor = cs.onPrimary;
    } else {
      fill = cs.surfaceContainerHighest;
      foreground = cs.onSurface;
      iconColor = color ?? context.appColors.accent;
    }

    final borderColor = isPrimary
        ? Colors.transparent
        : (color?.withValues(alpha: 0.55) ?? cs.outlineVariant);

    return Semantics(
      button: true,
      label: label,
      hint: semanticHint ?? subtitle,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: borderColor,
                width: isPrimary ? 0 : 1.5,
              ),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 32, color: iconColor),
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
                Icon(
                  Icons.chevron_right,
                  color: foreground.withValues(alpha: 0.55),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
