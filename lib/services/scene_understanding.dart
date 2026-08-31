import '../models/tracked_object.dart';
import 'priority_engine.dart';

/// Turns a prioritised object list into something short enough to say out loud.
///
/// Design constraints (accessibility, not style):
///   - One phrase, as few words as possible. The user is walking.
///   - Direction by zone (left / ahead / right), never coordinates.
///   - Distance only when it changes what the user should do.
///   - Same-type objects grouped, so three pedestrians is "3 people".
class SceneUnderstanding {
  // ── Routine alert ──────────────────────────────────────────────────────────

  /// A short grouped announcement for newly relevant objects.
  /// Returns null when there is nothing worth saying.
  String? buildAlert(List<ScoredObject> ranked) {
    final relevant = ranked
        .where((o) => o.score >= ScoredObject.announceThreshold)
        .toList();

    if (relevant.isEmpty) return null;
    return _describeGrouped(relevant.map((r) => r.track).toList(), limit: 2);
  }

  // ── Urgent alert ───────────────────────────────────────────────────────────

  /// The interrupt-everything phrasing for something the user is about to walk
  /// into. Front-loads the noun so it is understood even if the user reacts
  /// before the sentence finishes.
  String buildUrgentAlert(TrackedObject t) {
    final zone = _zoneWord(t);
    return '${_article(t.label)} $zone. Stop.';
  }

  // ── Full scene description (manual "describe" action) ──────────────────────

  /// A complete summary, spoken only when the user explicitly asks for one, so
  /// it is allowed to be longer than a routine alert.
  String buildFullDescription(List<ScoredObject> ranked) {
    if (ranked.isEmpty) return 'Path is clear.';

    final relevant =
        ranked.where((o) => o.score >= ScoredObject.announceThreshold).toList();
    if (relevant.isEmpty) return 'Path is clear.';

    return _describeGrouped(relevant.map((r) => r.track).toList(), limit: 4);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _describeGrouped(List<TrackedObject> tracks, {int limit = 2}) {
    final groups = <String, List<TrackedObject>>{};
    for (final t in tracks) {
      groups.putIfAbsent(t.label, () => []).add(t);
    }

    final groupStrings = <String>[];
    for (final entry in groups.entries) {
      final count = entry.value.length;
      final nearest = entry.value.first; // ranked closest-first
      final label = count > 1 ? '$count ${_plural(entry.key)}' : entry.key;

      final zone = _zoneWord(nearest);
      final dist = _distanceHint(nearest);
      groupStrings.add('$label $zone$dist'.trim());

      if (groupStrings.length >= limit) break;
    }

    if (groupStrings.isEmpty) return '';
    if (groupStrings.length == 1) return groupStrings.first;

    final last = groupStrings.removeLast();
    return '${groupStrings.join(', ')} and $last';
  }

  /// Enough pluralisation for the COCO labels this app allows. A general
  /// pluraliser would be more code than the twenty nouns here justify.
  String _plural(String label) {
    if (label == 'person') return 'people';
    if (label == 'bus') return 'buses';
    if (label.endsWith('s') || label.endsWith('x') || label.endsWith('ch')) {
      return '${label}es';
    }
    return '${label}s';
  }

  String _article(String label) {
    const vowels = {'a', 'e', 'i', 'o', 'u'};
    if (label.isEmpty) return label;
    final prefix = vowels.contains(label[0].toLowerCase()) ? 'An' : 'A';
    return '$prefix $label';
  }

  String _zoneWord(TrackedObject t) {
    final cx = t.boundingBox.center.dx;
    if (cx < 0.33) return 'on your left';
    if (cx > 0.67) return 'on your right';
    return 'ahead';
  }

  String _distanceHint(TrackedObject t) {
    final area = t.area;
    if (area > 0.25) return ', very close';
    if (area > 0.10) return ', close';
    return '';
  }
}
