import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/tracked_object.dart';
import 'priority_engine.dart';
import 'scene_understanding.dart';
import 'speech_service.dart';

/// Smart speech gate that converts a prioritised object list into spoken alerts
/// without overwhelming a blind user with constant audio noise.
class SpeechScheduler {
  SpeechScheduler({required SpeechService speechService})
      : _speech = speechService;

  final SpeechService _speech;
  final SceneUnderstanding _scene = SceneUnderstanding();

  // ── Cooldown constants ─────────────────────────────────────────────────────

  /// Minimum milliseconds before repeating the exact same text.
  static const int _sameTextCooldownMs = 8000;

  // ── State ──────────────────────────────────────────────────────────────────

  String? _lastText;
  DateTime? _lastAnnouncedAt;
  DateTime? _lastSummaryAt;

  // ── Accumulators for events between summaries ──────────────────────────────
  final Map<String, TrackedObject> _accumulatedNew = {};
  final Map<String, TrackedObject> _accumulatedDropped = {};

  /// Main entry point. Called every detection frame.
  Future<void> process({
    required List<ScoredObject> ranked,
    required List<TrackedObject> dropped,
    required AppSettings settings,
  }) async {
    final now = DateTime.now();
    _lastSummaryAt ??= now;

    // Accumulate newly appearing and dropped objects
    final newObjects = ranked.map((o) => o.track).where((t) => t.isNew).toList();
    
    // We only care about objects that are actually new to our accumulated list
    for (final t in newObjects) {
      if (!_accumulatedNew.containsKey(t.id)) {
        _accumulatedNew[t.id] = t;
      }
    }
    for (final t in dropped) {
      if (!_accumulatedDropped.containsKey(t.id)) {
        _accumulatedDropped[t.id] = t;
      }
    }

    // Check if it's time to summarize or announce frame changes
    final elapsedSinceSummary = now.difference(_lastSummaryAt!).inMilliseconds;
    
    if (elapsedSinceSummary >= settings.summarizeIntervalMs) {
      String? alertText;

      if (settings.announceFrameChanges) {
        // Remove objects that appeared and disappeared within the same window
        final actuallyNew = _accumulatedNew.values.where((t) => !_accumulatedDropped.containsKey(t.id)).toList();
        final actuallyDropped = _accumulatedDropped.values.where((t) => !_accumulatedNew.containsKey(t.id)).toList();

        alertText = _scene.buildEventAlert(
          newObjects: actuallyNew,
          droppedObjects: actuallyDropped,
        );
      } else {
        // Just summarize the current scene
        alertText = _scene.buildAlert(ranked);
      }

      _accumulatedNew.clear();
      _accumulatedDropped.clear();
      _lastSummaryAt = now;

      if (alertText != null && alertText.isNotEmpty) {
        // Check same-text cooldown
        if (_lastText == alertText &&
            _lastAnnouncedAt != null &&
            now.difference(_lastAnnouncedAt!).inMilliseconds < _sameTextCooldownMs) {
          return;
        }

        _lastText = alertText;
        _lastAnnouncedAt = now;

        debugPrint('[SpeechScheduler] Announcing: "$alertText"');
        await _speech.speak(
          alertText,
          priority: SpeechPriority.normal,
        );
      }
    } else {
      // Urgent Hazards (Critical) should still interrupt the summary wait period
      final top = ranked.where((o) => o.score >= ScoredObject.announceThreshold).toList();
      if (top.isNotEmpty && _isCritical(top.first)) {
        final alertText = _scene.buildAlert([top.first]);
        if (alertText != null) {
          if (_lastText == alertText &&
              _lastAnnouncedAt != null &&
              now.difference(_lastAnnouncedAt!).inMilliseconds < 2000) {
            return; // critical cooldown
          }

          _lastText = alertText;
          _lastAnnouncedAt = now;
          await _speech.speak(alertText, priority: SpeechPriority.critical);
        }
      }
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  bool _isCritical(ScoredObject o) {
    final cx = o.track.boundingBox.center.dx;
    // Critical = large box (close) AND roughly in the user's path.
    return o.track.area > 0.18 && cx > 0.22 && cx < 0.78;
  }

  void reset() {
    _lastText = null;
    _lastAnnouncedAt = null;
    _lastSummaryAt = null;
    _accumulatedNew.clear();
    _accumulatedDropped.clear();
  }
}
