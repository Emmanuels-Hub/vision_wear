import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

typedef VoiceCommandCallback = void Function(String command);

class VoiceCommandService {
  VoiceCommandService();

  final SpeechToText _speech = SpeechToText();
  bool _isListening = false;
  bool _isAvailable = false;
  VoiceCommandCallback? onCommand;

  bool get isListening => _isListening;
  bool get isAvailable => _isAvailable;

  Future<bool> initialize() async {
    _isAvailable = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          _isListening = false;
        }
      },
      onError: (_) {
        _isListening = false;
      },
    );
    return _isAvailable;
  }

  Future<void> startListening() async {
    if (!_isAvailable || _isListening) return;

    _isListening = true;
    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          final text = result.recognizedWords.toLowerCase().trim();
          if (text.isNotEmpty) {
            onCommand?.call(text);
          }
          _isListening = false;
        }
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 5),
        pauseFor: const Duration(seconds: 2),
        partialResults: false,
        cancelOnError: true,
      ),
    );
  }

  Future<void> stopListening() async {
    if (_isListening) {
      await _speech.stop();
      _isListening = false;
    }
  }

  void dispose() {
    _speech.stop();
  }
}
