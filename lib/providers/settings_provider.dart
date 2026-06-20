import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../services/settings_service.dart';

class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._settingsService);

  final SettingsService _settingsService;
  AppSettings _settings = const AppSettings();
  bool _isLoading = true;

  AppSettings get settings => _settings;
  bool get isLoading => _isLoading;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    _settings = await _settingsService.load();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> update(AppSettings settings) async {
    _settings = settings;
    await _settingsService.save(settings);
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    await update(_settings.copyWith(hasCompletedOnboarding: true));
  }

  Future<void> setEsp32Ip(String ip) async {
    await update(_settings.copyWith(esp32Ip: ip));
  }

  Future<void> setUsePhoneCamera(bool value) async {
    await update(_settings.copyWith(usePhoneCamera: value));
  }

  Future<void> setSpeechRate(double rate) async {
    await update(_settings.copyWith(speechRate: rate));
  }

  Future<void> setDetectionConfidence(double value) async {
    await update(_settings.copyWith(detectionConfidence: value));
  }

  Future<void> setEnableHaptics(bool value) async {
    await update(_settings.copyWith(enableHaptics: value));
  }

  Future<void> setEnableVoiceCommands(bool value) async {
    await update(_settings.copyWith(enableVoiceCommands: value));
  }

  Future<void> setAnnounceAllObjects(bool value) async {
    await update(_settings.copyWith(announceAllObjects: value));
  }

  Future<void> setFrameInterval(int ms) async {
    await update(_settings.copyWith(frameIntervalMs: ms));
  }
}
