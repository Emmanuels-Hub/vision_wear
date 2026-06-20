import '../models/detected_object.dart';
import '../models/obstacle_alert.dart';

class ObstacleAnalyzer {
  List<ObstacleAlert> analyze(List<DetectedObject> objects) {
    if (objects.isEmpty) {
      return [
        ObstacleAlert(
          message: 'Path appears clear',
          severity: AlertSeverity.info,
          timestamp: DateTime.now(),
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

    final pathBlockers = objects.where(
      (o) =>
          (o.zone == SpatialZone.center || o.zone == SpatialZone.near) &&
          o.proximity.index >= ProximityLevel.approaching.index,
    );

    for (final obj in critical) {
      alerts.add(
        ObstacleAlert(
          message: obj.announcement,
          severity: obj.proximity == ProximityLevel.immediate
              ? AlertSeverity.critical
              : AlertSeverity.warning,
          timestamp: DateTime.now(),
          shouldVibrate: obj.proximity == ProximityLevel.immediate,
        ),
      );
    }

    if (pathBlockers.isNotEmpty && critical.isEmpty) {
      final nearest = pathBlockers.first;
      alerts.add(
        ObstacleAlert(
          message: '${nearest.label} ${nearest.zoneDescription}',
          severity: AlertSeverity.warning,
          timestamp: DateTime.now(),
        ),
      );
    }

    if (alerts.isEmpty) {
      final nearest = objects.first;
      alerts.add(
        ObstacleAlert(
          message: '${nearest.label} detected ${nearest.zoneDescription}',
          severity: AlertSeverity.info,
          timestamp: DateTime.now(),
        ),
      );
    }

    return alerts;
  }

  String buildSceneDescription(List<DetectedObject> objects) {
    if (objects.isEmpty) {
      return 'I do not see any notable objects around you. The path appears clear.';
    }

    final hazards = objects.where((o) => o.isHazard).take(3);
    if (hazards.isEmpty) {
      final labels = objects.take(3).map((o) => o.label).join(', ');
      return 'I can see $labels nearby.';
    }

    final descriptions = hazards.map((o) => o.announcement).join('. ');
    return descriptions;
  }

  String? getPriorityAnnouncement(List<DetectedObject> objects) {
    final immediate = objects.where(
      (o) =>
          o.isHazard && o.proximity == ProximityLevel.immediate,
    );
    if (immediate.isNotEmpty) {
      return immediate.first.announcement;
    }

    final close = objects.where(
      (o) => o.isHazard && o.proximity == ProximityLevel.close,
    );
    if (close.isNotEmpty) {
      return close.first.announcement;
    }

    final centerObjects = objects.where(
      (o) => o.zone == SpatialZone.center || o.zone == SpatialZone.near,
    );
    if (centerObjects.isNotEmpty) {
      return centerObjects.first.announcement;
    }

    if (objects.isNotEmpty) {
      return objects.first.announcement;
    }

    return null;
  }

  bool isCriticalHazard(List<DetectedObject> objects) {
    return objects.any(
      (o) =>
          o.isHazard &&
          o.proximity == ProximityLevel.immediate &&
          (o.zone == SpatialZone.center || o.zone == SpatialZone.near),
    );
  }
}
