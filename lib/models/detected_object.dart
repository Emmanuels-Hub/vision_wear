import 'dart:ui';

enum SpatialZone { left, center, right, far, near }

enum ProximityLevel { distant, approaching, close, immediate }

class DetectedObject {
  const DetectedObject({
    required this.label,
    required this.confidence,
    required this.boundingBox,
    required this.zone,
    required this.proximity,
    required this.isHazard,
  });

  final String label;
  final double confidence;
  final Rect boundingBox;
  final SpatialZone zone;
  final ProximityLevel proximity;
  final bool isHazard;

  String get zoneDescription {
    switch (zone) {
      case SpatialZone.left:
        return 'to your left';
      case SpatialZone.center:
        return 'ahead';
      case SpatialZone.right:
        return 'to your right';
      case SpatialZone.far:
        return 'in the distance';
      case SpatialZone.near:
        return 'very close';
    }
  }

  String get proximityDescription {
    switch (proximity) {
      case ProximityLevel.distant:
        return 'far away';
      case ProximityLevel.approaching:
        return 'approaching';
      case ProximityLevel.close:
        return 'close';
      case ProximityLevel.immediate:
        return 'immediately ahead';
    }
  }

  String get announcement {
    if (isHazard && proximity == ProximityLevel.immediate) {
      return 'Warning! $label $zoneDescription, very close!';
    }
    if (isHazard) {
      return '$label $zoneDescription, $proximityDescription';
    }
    return '$label $zoneDescription';
  }
}
