import '../models/tracked_object.dart';

/// A tracked object with its computed danger score.
class ScoredObject {
  const ScoredObject(this.track, this.score);

  final TrackedObject track;

  /// Danger score in [0, 100]. Higher = more urgent.
  final double score;

  /// Objects below this score are not worth announcing to the user.
  static const double announceThreshold = 25.0;

  bool get shouldAnnounce => score >= announceThreshold;
}

/// Ranks tracked objects by how dangerous / relevant they are to a blind user.
///
/// Score components (total up to 100):
///   1. Proximity (box area)      0 – 35 pts   closer = more urgent
///   2. Zone alignment            0 – 20 pts   directly ahead = most dangerous
///   3. Object type               0 – 25 pts   car/person > cup/phone
///   4. Approach velocity         0 – 15 pts   getting larger = coming closer
///   5. Novelty bonus             0 –  5 pts   first time this object appears
class PriorityEngine {
  /// Known-dangerous object types and their relative weight [0, 1].
  /// Unlisted objects get [_defaultWeight].
  static const Map<String, double> _typeWeights = {
    // High danger — mobile or large
    'car': 1.00,
    'truck': 1.00,
    'bus': 0.95,
    'train': 1.00,
    'motorcycle': 0.85,
    'bicycle': 0.80,
    'person': 0.90,
    // Medium danger — stationary but hazardous
    'stairs': 0.70,
    'traffic light': 0.65,
    'stop sign': 0.55,
    'fire hydrant': 0.50,
    'parking meter': 0.45,
    'door': 0.55,
    'dog': 0.60,
    'cat': 0.30,
    'chair': 0.42,
    'bench': 0.38,
    'dining table': 0.48,
    'bed': 0.38,
    // Low danger — small objects the user rarely trips on
    'bottle': 0.12,
    'cup': 0.10,
    'book': 0.08,
    'cell phone': 0.06,
    'keyboard': 0.06,
    'mouse': 0.06,
    'remote': 0.06,
    'vase': 0.10,
  };

  static const double _defaultWeight = 0.20;

  /// Return [scored] sorted highest priority first.
  List<ScoredObject> rank(List<TrackedObject> tracks) {
    final scored =
        tracks.map((t) => ScoredObject(t, _score(t))).toList()
          ..sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  double _score(TrackedObject t) {
    double s = 0;

    // ── 1. Proximity (area-based) → 0–35 pts ─────────────────────────────
    // A bounding box covering >50% of the frame is treated as maximum danger.
    s += (t.area.clamp(0.0, 0.5) / 0.5) * 35;

    // ── 2. Zone alignment → 0–20 pts ─────────────────────────────────────
    // Objects directly ahead (cx ≈ 0.5) are more dangerous than those to the
    // side, since the user is walking toward them.
    final cx = t.boundingBox.center.dx;
    final centerness = 1 - (cx - 0.5).abs() * 2; // 1 = dead centre
    s += centerness.clamp(0.0, 1.0) * 20;

    // ── 3. Object type weight → 0–25 pts ─────────────────────────────────
    final w = _typeWeights[t.label.toLowerCase()] ?? _defaultWeight;
    s += w * 25;

    // ── 4. Approach velocity → 0–15 pts ──────────────────────────────────
    // Box growing quickly means the object is rapidly approaching.
    final vel = t.approachVelocity.clamp(0.0, 1.0);
    s += vel * 15;

    // ── 5. Novelty → 0–5 pts ─────────────────────────────────────────────
    // Newly appeared objects get a small bump so the user is notified when
    // something enters the scene, even if still distant.
    if (t.isNew) s += 5;

    return s;
  }
}
