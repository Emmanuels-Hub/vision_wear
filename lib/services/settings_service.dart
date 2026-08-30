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
      return AppSettings.fromJson(map);
    } catch (_) {
      // Corrupt or older-schema payload: fall back to defaults rather than
      // trapping the user on a screen that cannot load.
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySettings, jsonEncode(settings.toJson()));
  }
}
