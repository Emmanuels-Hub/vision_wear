import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

class SettingsService {
  static const _keySettings = 'app_settings';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_keySettings);
    if (json == null) return const AppSettings();

    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return AppSettings(
        esp32Ip: map['esp32Ip'] as String? ?? '192.168.4.1',
        capturePath: map['capturePath'] as String? ?? '/capture',
        usePhoneCamera: map['usePhoneCamera'] as bool? ?? false,
        speechRate: (map['speechRate'] as num?)?.toDouble() ?? 0.5,
        speechPitch: (map['speechPitch'] as num?)?.toDouble() ?? 1.0,
        speechVolume: (map['speechVolume'] as num?)?.toDouble() ?? 1.0,
        enableHaptics: map['enableHaptics'] as bool? ?? true,
        enableVoiceCommands: map['enableVoiceCommands'] as bool? ?? true,
        detectionConfidence:
            (map['detectionConfidence'] as num?)?.toDouble() ?? 0.55,
        frameIntervalMs: map['frameIntervalMs'] as int? ?? 500,
        hasCompletedOnboarding:
            map['hasCompletedOnboarding'] as bool? ?? false,
        announceAllObjects: map['announceAllObjects'] as bool? ?? false,
        languageCode: map['languageCode'] as String? ?? 'en-US',
      );
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final map = {
      'esp32Ip': settings.esp32Ip,
      'capturePath': settings.capturePath,
      'usePhoneCamera': settings.usePhoneCamera,
      'speechRate': settings.speechRate,
      'speechPitch': settings.speechPitch,
      'speechVolume': settings.speechVolume,
      'enableHaptics': settings.enableHaptics,
      'enableVoiceCommands': settings.enableVoiceCommands,
      'detectionConfidence': settings.detectionConfidence,
      'frameIntervalMs': settings.frameIntervalMs,
      'hasCompletedOnboarding': settings.hasCompletedOnboarding,
      'announceAllObjects': settings.announceAllObjects,
      'languageCode': settings.languageCode,
    };
    await prefs.setString(_keySettings, jsonEncode(map));
  }
}
