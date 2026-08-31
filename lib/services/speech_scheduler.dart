import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/tracked_object.dart';
import 'priority_engine.dart';
import 'scene_understanding.dart';
import 'speech_service.dart';

/// Decides when the app is allowed to speak during live detection.
///
/// This is the component that keeps the app usable. YOLO produces detections
/// tens of times a second; a blind user walking down a street can absorb an
/// announcement roughly every five seconds. Everything in between has to be
/// thrown away, and thrown away in a way that keeps the *useful* announcement
/// rather than the first or the loudest one.
///
/// Three gates, in order:
///   1. **Hard floor.** Never speak twice inside [_minGapMs], whatever happens,
///      except for a critical hazard.
///   2. **Novelty.** Only speak when the scene has actually changed — a new
///      object worth mentioning, or the nearest hazard becoming more urgent.
///      A static scene produces silence, not a repeated description.
///   3. **Repetition.** Never repeat identical wording inside
///      [_sameTextCooldownMs], even if the scene technically "changed".
///
/// Objects *leaving* the frame are deliberately never announced. The old
/// implementation said "chair left" every time something walked out of view,
/// which is noise: the user cares about what is in their way, not what is not.
class SpeechScheduler {
  SpeechScheduler({required SpeechService speechService})
      : _speech = speechService;

  final SpeechService _speech;
  final SceneUnderstanding _scene = SceneUnderstanding();

  // ── Cooldowns ──────────────────────────────────────────────────────────────

  /// Absolute minimum between two ordinary announcements.
  static const int _minGapMs = 4000;

  /// Minimum before repeating the exact same sentence.
  static const int _sameTextCooldownMs = 12000;

  /// Critical hazards bypass [_minGapMs] but not this.
  static const int _criticalCooldownMs = 2500;

  // ── State ──────────────────────────────────────────────────────────────────

  String? _lastText;
  DateTime? _lastAnnouncedAt;
  DateTime? _lastCriticalAt;

  /// Track IDs already mentioned, so an object that stays in view is described
  /// once rather than on every summary tick.
  final Set<String> _announcedIds = <String>{};

  /// Called on every detection frame.
  Future<void> process({
    required List<ScoredObject> ranked,
    required List<TrackedObject> dropped,
    required AppSettings settings,
  }) async {
    final now = DateTime.now();

    // Forget objects that have left, so the same chair encountered again later
    // is announced again rather than being suppressed forever.
    for (final t in dropped) {
      _announcedIds.remove(t.id);
    }

    final worthSaying =
        ranked.where((o) => o.score >= ScoredObject.announceThreshold).toList();
    if (worthSaying.isEmpty) return;

    // ── Gate 1a: critical hazard, allowed to interrupt ───────────────────────
    final top = worthSaying.first;
    if (_isCritical(top)) {
      if (_lastCriticalAt == null ||
          now.difference(_lastCriticalAt!).inMilliseconds >=
              _criticalCooldownMs) {
        final text = _scene.buildUrgentAlert(top.track);
        _lastCriticalAt = now;
        _lastAnnouncedAt = now;
        _lastText = text;
        _announcedIds.add(top.track.id);
        debugPrint('[Speech] critical: "$text"');
        await _speech.speak(text, priority: SpeechPriority.critical);
      }
      return;
    }

    // ── Gate 1b: hard floor between ordinary announcements ───────────────────
    if (_lastAnnouncedAt != null &&
        now.difference(_lastAnnouncedAt!).inMilliseconds <
            _effectiveGapMs(settings)) {
      return;
    }

    // ── Gate 2: novelty ──────────────────────────────────────────────────────
    // Only objects the user has not already been told about.
    final unannounced = worthSaying
        .where((o) => !_announcedIds.contains(o.track.id))
        .toList();
    if (unannounced.isEmpty) return;

    final text = _scene.buildAlert(unannounced);
    if (text == null || text.isEmpty) return;

    // ── Gate 3: repetition ───────────────────────────────────────────────────
    if (_lastText == text &&
        _lastAnnouncedAt != null &&
        now.difference(_lastAnnouncedAt!).inMilliseconds <
            _sameTextCooldownMs) {
      return;
    }

    for (final o in unannounced.take(2)) {
      _announcedIds.add(o.track.id);
    }
    _lastText = text;
    _lastAnnouncedAt = now;

    debugPrint('[Speech] announce: "$text"');
    await _speech.speak(text, priority: SpeechPriority.normal);
  }

  /// The user's summarise interval, but never faster than the hard floor.
  int _effectiveGapMs(AppSettings settings) =>
      settings.summarizeIntervalMs > _minGapMs
          ? settings.summarizeIntervalMs
          : _minGapMs;

  bool _isCritical(ScoredObject o) {
    final cx = o.track.boundingBox.center.dx;
    // Large box (so: close) and roughly in the user's walking path.
    return o.track.area > 0.18 && cx > 0.22 && cx < 0.78;
  }

  void reset() {
    _lastText = null;
    _lastAnnouncedAt = null;
    _lastCriticalAt = null;
    _announcedIds.clear();
  }
}
