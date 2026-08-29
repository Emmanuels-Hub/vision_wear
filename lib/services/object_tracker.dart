import 'dart:ui';

import '../models/tracked_object.dart';

/// Input record: raw output from YOLO for one detected object.
typedef Detection = ({String label, Rect box, double confidence});

class TrackerResult {
  const TrackerResult(this.active, this.dropped);
  final List<TrackedObject> active;
  final List<TrackedObject> dropped;
}

/// Maintains object identity across video frames using IoU-based matching.
///
/// Prevents the speech pipeline from treating the same person / chair / car
/// as a brand-new detection every frame. Without a tracker, each frame fires
/// a speech event for every visible object — creating an unbearable noise flood
/// for the blind user.
///
/// Algorithm (simple Hungarian-style greedy matching):
///   1. For each existing track, find the detection with the highest IoU.
///   2. If IoU ≥ threshold, update the track with the new bounding box.
///   3. Unmatched detections → new tracks.
///   4. Tracks missing for > [_maxMissingFrames] frames are removed.
class ObjectTracker {
  final List<TrackedObject> _tracks = [];
  int _nextId = 0;

  /// Minimum IoU to consider a detection and a track the same object.
  static const double _minIou = 0.25;

  /// Frames without a match before a track is dropped.
  static const int _maxMissingFrames = 8;

  /// Update the tracker with the current frame's detections.
  ///
  /// Returns a TrackerResult with currently visible tracks and tracks dropped this frame.
  TrackerResult update(List<Detection> detections) {
    final matched = <int>{}; // detection indices already assigned to a track
    final dropped = <TrackedObject>[];

    // ── Phase 1: match existing tracks to detections ──────────────────────
    for (final track in _tracks) {
      int bestIndex = -1;
      double bestIou = _minIou;

      for (var di = 0; di < detections.length; di++) {
        if (matched.contains(di)) continue;
        // Only match detections of the same class.
        if (detections[di].label != track.label) continue;

        final iou = _iou(track.boundingBox, detections[di].box);
        if (iou > bestIou) {
          bestIou = iou;
          bestIndex = di;
        }
      }

      if (bestIndex >= 0) {
        track.update(detections[bestIndex].box, detections[bestIndex].confidence);
        matched.add(bestIndex);
      } else {
        track.markMissing();
      }
    }

    // ── Phase 2: remove stale tracks ─────────────────────────────────────
    _tracks.removeWhere((t) {
      final isStale = t.framesMissing > _maxMissingFrames;
      if (isStale) dropped.add(t);
      return isStale;
    });

    // ── Phase 3: create tracks for unmatched detections ───────────────────
    for (var di = 0; di < detections.length; di++) {
      if (matched.contains(di)) continue;
      final det = detections[di];
      _tracks.add(TrackedObject(
        id: 'obj_${_nextId++}',
        label: det.label,
        boundingBox: det.box,
        confidence: det.confidence,
      ));
    }

    return TrackerResult(
      _tracks.where((t) => t.framesMissing == 0).toList(),
      dropped,
    );
  }

  void reset() {
    _tracks.clear();
    _nextId = 0;
  }

  // ── IoU helper ────────────────────────────────────────────────────────────

  static double _iou(Rect a, Rect b) {
    final ix1 = a.left > b.left ? a.left : b.left;
    final iy1 = a.top > b.top ? a.top : b.top;
    final ix2 = a.right < b.right ? a.right : b.right;
    final iy2 = a.bottom < b.bottom ? a.bottom : b.bottom;

    final iw = ix2 - ix1;
    final ih = iy2 - iy1;
    if (iw <= 0 || ih <= 0) return 0;

    final intersect = iw * ih;
    final union =
        a.width * a.height + b.width * b.height - intersect;
    return union > 0 ? intersect / union : 0;
  }
}
