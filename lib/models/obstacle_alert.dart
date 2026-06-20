enum AlertSeverity { info, warning, critical }

class ObstacleAlert {
  const ObstacleAlert({
    required this.message,
    required this.severity,
    required this.timestamp,
    this.shouldVibrate = false,
  });

  final String message;
  final AlertSeverity severity;
  final DateTime timestamp;
  final bool shouldVibrate;

  ColorHint get colorHint {
    switch (severity) {
      case AlertSeverity.info:
        return ColorHint.info;
      case AlertSeverity.warning:
        return ColorHint.warning;
      case AlertSeverity.critical:
        return ColorHint.critical;
    }
  }
}

enum ColorHint { info, warning, critical }
