import 'package:vibration/vibration.dart';

/// Vibration feedback, rate-limited.
///
/// Two things the previous version got wrong: it asked the platform whether a
/// vibrator exists on *every* call, and it had no cooldown. The detection
/// pipeline runs about ten times a second, so a close obstacle produced a
/// continuous buzz plus ten platform round-trips per second.
class HapticService {
  bool? _hasVibrator;
  DateTime? _lastAlertAt;

  /// Minimum gap between buzzes. Long enough that a sustained hazard feels
  /// like a repeated pulse rather than one unbroken vibration.
  static const int _cooldownMs = 1500;

  Future<bool> _available() async {
    return _hasVibrator ??= (await Vibration.hasVibrator()) == true;
  }

  /// Buzz for a detected obstacle. Silently ignored while on cooldown.
  Future<void> alert({bool critical = false}) async {
    final now = DateTime.now();
    if (_lastAlertAt != null &&
        now.difference(_lastAlertAt!).inMilliseconds < _cooldownMs) {
      return;
    }
    if (!await _available()) return;
    _lastAlertAt = now;

    if (critical) {
      await Vibration.vibrate(
        pattern: [0, 200, 100, 200, 100, 400],
        intensities: [0, 255, 0, 255, 0, 255],
      );
    } else {
      await Vibration.vibrate(duration: 150);
    }
  }

  /// A short confirmation tap. Not rate-limited: these only fire in response to
  /// a deliberate user action.
  Future<void> success() async {
    if (!await _available()) return;
    await Vibration.vibrate(duration: 80);
  }
}
