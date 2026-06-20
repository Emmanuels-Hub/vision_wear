import 'package:vibration/vibration.dart';

class HapticService {
  Future<void> alert({bool critical = false}) async {
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator != true) return;

    if (critical) {
      await Vibration.vibrate(
        pattern: [0, 200, 100, 200, 100, 400],
        intensities: [0, 255, 0, 255, 0, 255],
      );
    } else {
      await Vibration.vibrate(duration: 150);
    }
  }

  Future<void> success() async {
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator != true) return;
    await Vibration.vibrate(duration: 80);
  }
}
