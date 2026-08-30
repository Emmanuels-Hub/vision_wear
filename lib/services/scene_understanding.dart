import '../models/tracked_object.dart';
import 'priority_engine.dart';

/// Converts a prioritised list of tracked objects into concise, natural
/// language scene descriptions for the speech pipeline.
///
/// Design constraints (for accessibility / blind users):
///   - Each announcement is ONE short phrase (≤ 10 words).
///   - Objects are described by zone (left / ahead / right) not coordinates.
///   - Distance and approach speed are included when relevant.
///   - A clear-path message is returned when no hazards are present.
///   - Objects of the same type are grouped (e.g. "2 people").
class SceneUnderstanding {
  // ── Real-time alert (called every detection cycle) ─────────────────────────

  /// Build a short grouped announcement from [ranked] objects.
  /// Returns `null` if nothing is worth announcing right now.
  String? buildAlert(List<ScoredObject> ranked) {
    final relevant = ranked
        .where((o) => o.score >= ScoredObject.announceThreshold)
        .toList();

    if (relevant.isEmpty) return null;
    return _describeGrouped(relevant.map((r) => r.track).toList(), limit: 2);
  }

  // ── Enter / Leave Announcements ───────────────────────────────────────────

  String? buildEventAlert({
    required List<TrackedObject> newObjects,
    required List<TrackedObject> droppedObjects,
  }) {
    final parts = <String>[];

    if (newObjects.isNotEmpty) {
      final desc = _describeGrouped(newObjects, limit: 2, includeDetails: false);
      parts.add('$desc entered');
    }

    if (droppedObjects.isNotEmpty) {
      final desc = _describeGrouped(droppedObjects, limit: 2, includeDetails: false);
      parts.add('$desc left');
    }

    if (parts.isEmpty) return null;
    return parts.join(', ');
  }

  // ── Full scene description (manual "describe" button) ─────────────────────

  /// Build a complete scene summary (used by the manual describe button).
  String buildFullDescription(List<ScoredObject> ranked) {
    if (ranked.isEmpty) return 'Path appears clear.';

    final relevant =
        ranked.where((o) => o.score >= ScoredObject.announceThreshold).toList();
    if (relevant.isEmpty) return 'Path appears clear.';

    return _describeGrouped(relevant.map((r) => r.track).toList(), limit: 5);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _describeGrouped(List<TrackedObject> tracks, {int limit = 2, bool includeDetails = true}) {
    // Group by label
    final groups = <String, List<TrackedObject>>{};
    for (final t in tracks) {
      groups.putIfAbsent(t.label, () => []).add(t);
    }

    final groupStrings = <String>[];
    for (final entry in groups.entries) {
      final count = entry.value.length;
      final label = count > 1 ? '${entry.key}s' : entry.key; // simple pluralization
      final mainTrack = entry.value.first; // Use the closest one for hints
      
      var desc = count > 1 ? '$count $label' : label;

      if (includeDetails) {
        final zone = _zoneWord(mainTrack);
        final dist = _distanceHint(mainTrack);
        final speed = _speedHint(mainTrack);
        desc += ' $zone$dist$speed';
      }

      groupStrings.add(desc.trim());
      if (groupStrings.length >= limit) break;
    }

    if (groupStrings.isEmpty) return '';
    if (groupStrings.length == 1) return groupStrings.first;

    final last = groupStrings.removeLast();
    return '${groupStrings.join(', ')} and $last';
  }

  String _zoneWord(TrackedObject t) {
    final cx = t.boundingBox.center.dx;
    if (cx < 0.33) return 'to your left';
    if (cx > 0.67) return 'to your right';
    return 'ahead';
  }

  String _distanceHint(TrackedObject t) {
    final area = t.area;
    if (area > 0.25) return ', very close';
    if (area > 0.10) return ', nearby';
    return '';
  }

  String _speedHint(TrackedObject t) {
    // Only mention approach when the box is growing rapidly.
    if (t.approachVelocity > 0.08) return ', approaching';
    return '';
  }
}
