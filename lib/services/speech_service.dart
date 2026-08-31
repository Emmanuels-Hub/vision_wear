import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/app_settings.dart';

/// How urgent an utterance is. Higher index wins.
enum SpeechPriority {
  /// Routine scene summaries. Dropped freely when something better arrives.
  normal,

  /// User-initiated: they pressed a button and are waiting for an answer.
  high,

  /// An obstacle is about to be walked into. Interrupts whatever is speaking.
  critical,
}

/// A voice offered by the platform TTS engine.
class SpeechVoice {
  const SpeechVoice({
    required this.name,
    required this.locale,
    required this.quality,
  });

  final String name;
  final String locale;

  /// Higher is better. Derived from engine metadata, used to pick a default
  /// that does not sound like a 1990s screen reader.
  final int quality;

  /// What the settings list shows. Engine names like `en-us-x-tpf-local` are
  /// unreadable, so they are cleaned up into something a person can choose
  /// from.
  String get displayName {
    final cleaned = name
        .replaceAll(RegExp(r'^[a-z]{2}[-_][A-Za-z]{2,3}[-_]?'), '')
        .replaceAll(RegExp(r'[-_](local|network|language)$'), '')
        .replaceAll(RegExp(r'^x[-_]'), '')
        .replaceAll(RegExp(r'[-_]+'), ' ')
        .trim();
    return cleaned.isEmpty ? name : cleaned;
  }

  Map<String, String> toTtsMap() => {'name': name, 'locale': locale};

  @override
  bool operator ==(Object other) =>
      other is SpeechVoice && other.name == name && other.locale == locale;

  @override
  int get hashCode => Object.hash(name, locale);
}

/// Speaks to the user, and — just as importantly — decides what *not* to say.
///
/// The previous implementation appended every request to an unbounded queue
/// and drained it in order. Speech is roughly an order of magnitude slower
/// than detection, so the queue grew without limit and the user ended up
/// hearing descriptions of a scene they had already walked past. For someone
/// relying on this to cross a road, stale audio is worse than silence.
///
/// This version keeps at most one pending utterance. A newer request of equal
/// or higher priority replaces the pending one rather than queueing behind it,
/// and a [SpeechPriority.critical] request stops whatever is currently
/// speaking. The user always hears the most recent relevant thing.
class SpeechService {
  SpeechService();

  final FlutterTts _tts = FlutterTts();

  AppSettings _settings = const AppSettings();
  bool _isInitialized = false;
  bool _isSpeaking = false;

  /// The single pending utterance. Replaced, never appended to.
  _Utterance? _pending;

  String _lastSpoken = '';
  List<SpeechVoice> _voices = const [];

  String get lastSpoken => _lastSpoken;

  /// Voices the engine offers, best first. Empty until [initialize] completes.
  List<SpeechVoice> get availableVoices => _voices;

  bool get isInitialized => _isInitialized;

  /// Must be awaited before the first [speak]. The old code kicked
  /// initialisation off from the constructor and dropped every utterance that
  /// arrived before it finished, which silently swallowed the first alerts
  /// after launch.
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await _tts.awaitSpeakCompletion(true);

      if (Platform.isAndroid) {
        // QUEUE_FLUSH. We do our own scheduling; letting the engine keep its
        // own backlog would reintroduce exactly the lag we are removing.
        await _tts.setQueueMode(0);
      }
      if (Platform.isIOS) {
        await _tts.setSharedInstance(true);
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
            IosTextToSpeechAudioCategoryOptions.duckOthers,
          ],
        );
      }

      await _loadVoices();
      await _applySettings();
    } catch (e) {
      debugPrint('[Speech] initialisation failed: $e');
    } finally {
      // Mark ready either way: a partially configured engine speaking in its
      // default voice beats an app that never says anything.
      _isInitialized = true;
    }
  }

  Future<void> updateSettings(AppSettings settings) async {
    final languageChanged = settings.languageCode != _settings.languageCode;
    _settings = settings;
    if (!_isInitialized) return;
    if (languageChanged) await _loadVoices();
    await _applySettings();
  }

  // ── Voice selection ────────────────────────────────────────────────────────

  Future<void> _loadVoices() async {
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return;

      final voices = <SpeechVoice>[];
      for (final entry in raw) {
        if (entry is! Map) continue;
        final name = entry['name']?.toString();
        final locale = entry['locale']?.toString();
        if (name == null || locale == null) continue;
        // Only offer voices for the language the app is speaking.
        if (!_localeMatches(locale, _settings.languageCode)) continue;
        voices.add(
          SpeechVoice(
            name: name,
            locale: locale,
            quality: _scoreVoice(name, entry),
          ),
        );
      }

      voices.sort((a, b) {
        final byQuality = b.quality.compareTo(a.quality);
        return byQuality != 0
            ? byQuality
            : a.displayName.compareTo(b.displayName);
      });
      _voices = voices;
    } catch (e) {
      debugPrint('[Speech] could not enumerate voices: $e');
    }
  }

  /// Compares only the language subtag, so `en-GB` voices still show up for an
  /// `en-US` app language rather than leaving the list empty.
  bool _localeMatches(String voiceLocale, String appLocale) {
    String lang(String s) =>
        s.replaceAll('_', '-').split('-').first.toLowerCase();
    return lang(voiceLocale) == lang(appLocale);
  }

  /// Ranks voices so the default is a natural-sounding one.
  ///
  /// The flat, robotic voice users complain about is the engine's built-in
  /// fallback (eSpeak on Android, Compact on iOS). Every platform ships better
  /// ones; they are just never selected unless you ask for them by name.
  int _scoreVoice(String name, Map<dynamic, dynamic> entry) {
    var score = 0;
    final lower = name.toLowerCase();

    // iOS reports quality explicitly.
    final quality = entry['quality']?.toString().toLowerCase();
    if (quality != null &&
        (quality.contains('enhanced') || quality.contains('premium'))) {
      score += 100;
    }

    // Android naming conventions. Network voices are the WaveNet-class ones.
    if (lower.contains('network')) score += 80;
    if (lower.contains('-x-')) score += 40; // Google's extended voice set
    if (lower.contains('local')) score += 10;

    // Known-bad fallbacks — these are the robotic ones.
    if (lower.contains('espeak')) score -= 100;
    if (lower.contains('compact')) score -= 60;
    if (lower.contains('eloquence')) score -= 40;

    return score;
  }

  Future<void> _applySettings() async {
    try {
      await _tts.setLanguage(_settings.languageCode);
      await _tts.setSpeechRate(_settings.speechRate);
      await _tts.setPitch(_settings.speechPitch);
      await _tts.setVolume(_settings.speechVolume);

      final chosen = _resolveVoice();
      if (chosen != null) await _tts.setVoice(chosen.toTtsMap());
    } catch (e) {
      debugPrint('[Speech] could not apply settings: $e');
    }
  }

  /// The user's explicit choice if it is still available, otherwise the
  /// highest-scoring voice the engine offers.
  SpeechVoice? _resolveVoice() {
    if (_voices.isEmpty) return null;

    final wanted = _settings.voiceName;
    if (wanted.isNotEmpty) {
      for (final v in _voices) {
        if (v.name == wanted) return v;
      }
    }
    // Sorted best-first in _loadVoices. Only worth overriding the engine
    // default when we actually found something better than the fallback.
    final best = _voices.first;
    return best.quality > 0 ? best : null;
  }

  /// Speaks one sample sentence so the user can pick a voice by ear.
  Future<void> previewVoice(SpeechVoice voice) async {
    await stop();
    try {
      await _tts.setVoice(voice.toTtsMap());
      await _tts.speak('Person ahead, two metres.');
    } catch (e) {
      debugPrint('[Speech] preview failed: $e');
    } finally {
      // Restore the configured voice so a preview cannot leave the app
      // speaking in a voice the user never saved.
      final chosen = _resolveVoice();
      if (chosen != null) {
        try {
          await _tts.setVoice(chosen.toTtsMap());
        } catch (_) {}
      }
    }
  }

  // ── Speaking ───────────────────────────────────────────────────────────────

  /// Queue [text] to be spoken. At most one utterance is ever pending.
  ///
  /// A request is dropped when something more urgent is already waiting — the
  /// user hears the important thing, not both.
  Future<void> speak(
    String text, {
    SpeechPriority priority = SpeechPriority.normal,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (!_isInitialized) await initialize();

    final utterance = _Utterance(trimmed, priority);

    if (priority == SpeechPriority.critical) {
      // Cut off whatever is being said. A warning that arrives after the user
      // has walked into the obstacle is worthless.
      _pending = utterance;
      if (_isSpeaking) {
        try {
          await _tts.stop();
        } catch (_) {}
        _isSpeaking = false;
      }
    } else {
      final waiting = _pending;
      if (waiting != null && waiting.priority.index > priority.index) return;
      _pending = utterance;
    }

    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_isSpeaking) return;
    _isSpeaking = true;

    try {
      while (_pending != null) {
        final utterance = _pending!;
        _pending = null;
        _lastSpoken = utterance.text;
        try {
          await _tts.speak(utterance.text);
        } catch (e) {
          debugPrint('[Speech] speak failed: $e');
        }
      }
    } finally {
      _isSpeaking = false;
    }
  }

  /// Re-reads the last thing said. Used by the repeat voice command.
  Future<void> repeatLast() async {
    if (_lastSpoken.isEmpty) return;
    await speak(_lastSpoken, priority: SpeechPriority.high);
  }

  Future<void> stop() async {
    _pending = null;
    try {
      await _tts.stop();
    } catch (_) {
      // Stopping an engine that is not speaking throws on some Android builds.
    }
    _isSpeaking = false;
  }

  Future<void> dispose() => stop();
}

class _Utterance {
  const _Utterance(this.text, this.priority);
  final String text;
  final SpeechPriority priority;
}
