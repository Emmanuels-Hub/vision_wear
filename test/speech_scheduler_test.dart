import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vision_wear/models/app_settings.dart';
import 'package:vision_wear/models/tracked_object.dart';
import 'package:vision_wear/services/priority_engine.dart';
import 'package:vision_wear/services/speech_scheduler.dart';
import 'package:vision_wear/services/speech_service.dart';

/// Captures what would have been spoken instead of talking to the platform.
///
/// [SpeechService]'s constructor only builds a `FlutterTts` (which is just a
/// MethodChannel handle), so subclassing it in a unit test is safe as long as
/// every method that would cross the channel is overridden.
class _RecordingSpeech extends SpeechService {
  final List<(String, SpeechPriority)> spoken = [];

  @override
  Future<void> speak(
    String text, {
    SpeechPriority priority = SpeechPriority.normal,
  }) async {
    spoken.add((text, priority));
  }

  @override
  Future<void> stop() async {}

  List<String> get texts => spoken.map((e) => e.$1).toList();
}

/// A track positioned and sized to land in a specific danger band.
TrackedObject _track({
  required String id,
  String label = 'person',
  double centerX = 0.5,
  double area = 0.05,
}) {
  final side = area <= 0 ? 0.01 : _sqrt(area);
  return TrackedObject(
    id: id,
    label: label,
    boundingBox: Rect.fromCenter(
      center: Offset(centerX, 0.5),
      width: side,
      height: side,
    ),
    confidence: 0.9,
  );
}

double _sqrt(double v) {
  var x = v;
  for (var i = 0; i < 40; i++) {
    x = (x + v / x) / 2;
  }
  return x;
}

List<ScoredObject> _rank(List<TrackedObject> tracks) =>
    PriorityEngine().rank(tracks);

void main() {
  // FlutterTts wires up a MethodChannel in its constructor, so the superclass
  // cannot be instantiated without a binding — even though no call ever
  // crosses it here.
  TestWidgetsFlutterBinding.ensureInitialized();

  const settings = AppSettings();

  group('SpeechScheduler pacing', () {
    late _RecordingSpeech speech;
    late SpeechScheduler scheduler;

    setUp(() {
      speech = _RecordingSpeech();
      scheduler = SpeechScheduler(speechService: speech);
    });

    test('announces a newly relevant object', () async {
      await scheduler.process(
        ranked: _rank([_track(id: 'a')]),
        dropped: const [],
        settings: settings,
      );

      expect(speech.texts, hasLength(1));
      expect(speech.texts.first, contains('person'));
    });

    test('does not repeat an object it has already announced', () async {
      final track = _track(id: 'a');

      for (var i = 0; i < 20; i++) {
        await scheduler.process(
          ranked: _rank([track]),
          dropped: const [],
          settings: settings,
        );
      }

      // This is the flood the old scheduler produced: the same person, still
      // standing there, described on every summary tick.
      expect(speech.texts, hasLength(1));
    });

    test('stays silent for a second object inside the minimum gap', () async {
      await scheduler.process(
        ranked: _rank([_track(id: 'a')]),
        dropped: const [],
        settings: settings,
      );
      await scheduler.process(
        ranked: _rank([_track(id: 'a'), _track(id: 'b', label: 'chair')]),
        dropped: const [],
        settings: settings,
      );

      expect(speech.texts, hasLength(1));
    });

    test('a close object in the path interrupts immediately', () async {
      // Large box, dead centre: the user is about to walk into it.
      await scheduler.process(
        ranked: _rank([_track(id: 'a', area: 0.30)]),
        dropped: const [],
        settings: settings,
      );

      expect(speech.spoken, hasLength(1));
      expect(speech.spoken.first.$2, SpeechPriority.critical);
      expect(speech.spoken.first.$1, contains('Stop'));
    });

    test('a critical hazard is not repeated on every frame', () async {
      final track = _track(id: 'a', area: 0.30);

      for (var i = 0; i < 10; i++) {
        await scheduler.process(
          ranked: _rank([track]),
          dropped: const [],
          settings: settings,
        );
      }

      expect(speech.texts, hasLength(1));
    });

    test('says nothing when everything scores below the threshold', () async {
      // Tiny, far to the side, and a low-danger class.
      await scheduler.process(
        ranked: _rank([
          _track(id: 'a', label: 'cup', centerX: 0.02, area: 0.001),
        ]),
        dropped: const [],
        settings: settings,
      );

      expect(speech.texts, isEmpty);
    });

    test('an object that leaves and returns is announced again', () async {
      final track = _track(id: 'a');

      await scheduler.process(
        ranked: _rank([track]),
        dropped: const [],
        settings: settings,
      );
      expect(speech.texts, hasLength(1));

      // Dropping the track clears its "already announced" mark; without the
      // reset the user would never be warned about it a second time.
      await scheduler.process(
        ranked: const [],
        dropped: [track],
        settings: settings,
      );

      scheduler.reset(); // clears the inter-announcement cooldown too
      await scheduler.process(
        ranked: _rank([track]),
        dropped: const [],
        settings: settings,
      );

      expect(speech.texts, hasLength(2));
    });

    test('reset clears all state', () async {
      final track = _track(id: 'a');
      await scheduler.process(
        ranked: _rank([track]),
        dropped: const [],
        settings: settings,
      );
      scheduler.reset();
      await scheduler.process(
        ranked: _rank([track]),
        dropped: const [],
        settings: settings,
      );

      expect(speech.texts, hasLength(2));
    });
  });
}
