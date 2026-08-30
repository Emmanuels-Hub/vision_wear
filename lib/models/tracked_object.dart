import 'dart:ui';

/// A camera object being actively tracked across video frames.
///
/// Unlike [DetectedObject] (which is a snapshot), a [TrackedObject] accumulates
/// temporal information — how long the object has been visible, whether it is
/// approaching, and how stable the detection is.
class TrackedObject {
  TrackedObject({
    required this.id,
    required this.label,
    required this.boundingBox,
    required this.confidence,
  }) : firstSeenAt = DateTime.now(),
       lastSeenAt = DateTime.now();

  final String id;
  final String label;
  final DateTime firstSeenAt;

  Rect boundingBox;
  double confidence;

  DateTime lastSeenAt;
  int framesVisible = 1;
  int framesMissing = 0;
  double _previousArea = 0;

  /// Update this track with a new matched detection from the current frame.
  void update(Rect newBox, double newConfidence) {
    _previousArea = boundingBox.width * boundingBox.height;
    boundingBox = newBox;
    confidence = newConfidence;
    framesVisible++;
    framesMissing = 0;
    lastSeenAt = DateTime.now();
  }

  /// Mark this track as unmatched in the current frame.
  void markMissing() {
    framesMissing++;
  }

  // ── Derived properties ─────────────────────────────────────────────────────

  /// True for the first 3 frames — object just appeared in the scene.
  bool get isNew => framesVisible <= 3;

  /// True once seen for 5+ consecutive frames (stable, not a false positive).
  bool get isStable => framesVisible >= 5;

  /// Bounding-box area in normalised [0,1] space.
  double get area => boundingBox.width * boundingBox.height;

  /// Rate of area change relative to the previous frame.
  /// Positive = object is getting larger = approaching.
  /// Negative = object is receding.
  /// Zero on the first frame.
  double get approachVelocity {
    final currentArea = area;
    if (_previousArea <= 0) return 0.0;
    return (currentArea - _previousArea) / _previousArea;
  }
}
