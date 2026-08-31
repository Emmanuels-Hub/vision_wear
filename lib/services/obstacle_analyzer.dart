import '../models/detected_object.dart';
import '../models/obstacle_alert.dart';

/// Turns the current detection list into the alert cards shown on the vision
/// screen. This is display only — what the user *hears* is decided by
/// [SpeechScheduler], which is deliberately far more conservative.
class ObstacleAnalyzer {
  List<ObstacleAlert> analyze(List<DetectedObject> objects) {
    final now = DateTime.now();

    if (objects.isEmpty) {
      return [
        ObstacleAlert(
          message: 'Path appears clear',
          severity: AlertSeverity.info,
          timestamp: now,
        ),
      ];
    }

    final alerts = <ObstacleAlert>[];

    final critical = objects.where(
      (o) =>
          o.isHazard &&
          (o.proximity == ProximityLevel.immediate ||
              o.proximity == ProximityLevel.close),
    );

    for (final obj in critical) {
      alerts.add(
        ObstacleAlert(
          message: obj.announcement,
          severity: obj.proximity == ProximityLevel.immediate
              ? AlertSeverity.critical
              : AlertSeverity.warning,
          timestamp: now,
          shouldVibrate: obj.proximity == ProximityLevel.immediate,
        ),
      );
    }

    if (alerts.isEmpty) {
      final pathBlockers = objects.where(
        (o) =>
            o.zone == SpatialZone.center &&
            o.proximity.index >= ProximityLevel.approaching.index,
      );

      final nearest = pathBlockers.isNotEmpty ? pathBlockers.first : objects.first;
      alerts.add(
        ObstacleAlert(
          message: '${nearest.label} ${nearest.zoneDescription}',
          severity: pathBlockers.isNotEmpty
              ? AlertSeverity.warning
              : AlertSeverity.info,
          timestamp: now,
        ),
      );
    }

    return alerts;
  }
}
