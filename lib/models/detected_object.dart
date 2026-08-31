import 'dart:ui';

enum SpatialZone { left, center, right }

enum ProximityLevel { distant, approaching, close, immediate }

class DetectedObject {
  const DetectedObject({
    required this.label,
    required this.confidence,
    required this.boundingBox,
    required this.zone,
    required this.proximity,
    required this.isHazard,
    this.estimatedDistance,
  });

  final String label;
  final double confidence;
  final Rect boundingBox;
  final SpatialZone zone;
  final ProximityLevel proximity;
  final bool isHazard;

  /// Estimated distance in metres, derived from bounding-box size heuristic.
  /// `null` when the box is too ambiguous to estimate.
  final double? estimatedDistance;

  /// Human-readable distance string, e.g. "~1.2 m" or "very close".
  String get distanceDescription {
    if (estimatedDistance == null) return '';
    if (estimatedDistance! < 0.8) return 'very close';
    return '~${estimatedDistance!.toStringAsFixed(1)} m';
  }

  String get zoneDescription {
    switch (zone) {
      case SpatialZone.left:
        return 'to your left';
      case SpatialZone.center:
        return 'ahead';
      case SpatialZone.right:
        return 'to your right';
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
    final dist = estimatedDistance != null ? ', $distanceDescription' : '';
    if (isHazard && proximity == ProximityLevel.immediate) {
      return 'Warning! $label $zoneDescription$dist, very close!';
    }
    if (isHazard) {
      return '$label $zoneDescription$dist, $proximityDescription';
    }
    return '$label $zoneDescription$dist';
  }
}
