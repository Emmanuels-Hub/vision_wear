import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/obstacle_alert.dart';

class ObstacleAlertCard extends StatelessWidget {
  const ObstacleAlertCard({super.key, required this.alert});

  final ObstacleAlert alert;

  @override
  Widget build(BuildContext context) {
    final color = switch (alert.severity) {
      AlertSeverity.critical => AppTheme.danger,
      AlertSeverity.warning => AppTheme.warning,
      AlertSeverity.info => AppTheme.accent,
    };

    final icon = switch (alert.severity) {
      AlertSeverity.critical => Icons.warning_amber_rounded,
      AlertSeverity.warning => Icons.info_outline,
      AlertSeverity.info => Icons.check_circle_outline,
    };

    return Semantics(
      label: alert.message,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                alert.message,
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
