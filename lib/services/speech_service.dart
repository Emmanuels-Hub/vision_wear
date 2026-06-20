import 'dart:async';
import 'dart:collection';

import 'package:flutter_tts/flutter_tts.dart';

import '../models/app_settings.dart';

enum SpeechPriority { low, normal, high, critical }

class SpeechRequest {
  SpeechRequest(this.text, {this.priority = SpeechPriority.normal});

  final String text;
  final SpeechPriority priority;
}

class SpeechService {
  SpeechService() {
    _init();
  }

  final FlutterTts _tts = FlutterTts();
  final Queue<SpeechRequest> _queue = Queue();
  bool _isSpeaking = false;
  bool _isInitialized = false;
  AppSettings _settings = const AppSettings();
  String _lastSpoken = '';

  void updateSettings(AppSettings settings) {
    _settings = settings;
    _applySettings();
  }

  Future<void> _init() async {
    await _tts.awaitSpeakCompletion(true);
    await _applySettings();
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
      _processQueue();
    });
    _isInitialized = true;
  }

  Future<void> _applySettings() async {
    await _tts.setLanguage(_settings.languageCode);
    await _tts.setSpeechRate(_settings.speechRate);
    await _tts.setPitch(_settings.speechPitch);
    await _tts.setVolume(_settings.speechVolume);
  }

  Future<void> speak(
    String text, {
    SpeechPriority priority = SpeechPriority.normal,
    bool force = false,
  }) async {
    if (!_isInitialized || text.trim().isEmpty) return;

    if (priority == SpeechPriority.critical || force) {
      await stop();
      await _speakNow(text);
      return;
    }

    if (priority == SpeechPriority.high && _isSpeaking) {
      await stop();
    }

    _queue.add(SpeechRequest(text, priority: priority));
    if (!_isSpeaking) {
      await _processQueue();
    }
  }

  Future<void> _processQueue() async {
    if (_isSpeaking || _queue.isEmpty) return;

    final sorted = _queue.toList()
      ..sort((a, b) => b.priority.index.compareTo(a.priority.index));
    _queue.clear();

    for (final request in sorted) {
      await _speakNow(request.text);
      if (_queue.isNotEmpty) break;
    }
  }

  Future<void> _speakNow(String text) async {
    _isSpeaking = true;
    _lastSpoken = text;
    await _tts.speak(text);
  }

  Future<void> repeatLast() async {
    if (_lastSpoken.isNotEmpty) {
      await speak(_lastSpoken, priority: SpeechPriority.high, force: true);
    }
  }

  String get lastSpoken => _lastSpoken;

  Future<void> stop() async {
    _queue.clear();
    await _tts.stop();
    _isSpeaking = false;
  }

  void dispose() {
    stop();
  }
}
