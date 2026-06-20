class AppSettings {
  const AppSettings({
    this.esp32Ip = '192.168.4.1',
    this.capturePath = '/capture',
    this.eventsPath = '/events',
    this.usePhoneCamera = false,
    this.speechRate = 0.5,
    this.speechPitch = 1.0,
    this.speechVolume = 1.0,
    this.enableHaptics = true,
    this.enableVoiceCommands = true,
    this.detectionConfidence = 0.55,
    this.frameIntervalMs = 500,
    this.hasCompletedOnboarding = false,
    this.announceAllObjects = false,
    this.languageCode = 'en-US',
  });

  final String esp32Ip;
  final String capturePath;
  final String eventsPath;
  final bool usePhoneCamera;
  final double speechRate;
  final double speechPitch;
  final double speechVolume;
  final bool enableHaptics;
  final bool enableVoiceCommands;
  final double detectionConfidence;
  final int frameIntervalMs;
  final bool hasCompletedOnboarding;
  final bool announceAllObjects;
  final String languageCode;

  String get captureUrl => 'http://$esp32Ip$capturePath';
  String get eventsUrl => 'http://$esp32Ip$eventsPath';

  AppSettings copyWith({
    String? esp32Ip,
    String? capturePath,
    String? eventsPath,
    bool? usePhoneCamera,
    double? speechRate,
    double? speechPitch,
    double? speechVolume,
    bool? enableHaptics,
    bool? enableVoiceCommands,
    double? detectionConfidence,
    int? frameIntervalMs,
    bool? hasCompletedOnboarding,
    bool? announceAllObjects,
    String? languageCode,
  }) {
    return AppSettings(
      esp32Ip: esp32Ip ?? this.esp32Ip,
      capturePath: capturePath ?? this.capturePath,
      eventsPath: eventsPath ?? this.eventsPath,
      usePhoneCamera: usePhoneCamera ?? this.usePhoneCamera,
      speechRate: speechRate ?? this.speechRate,
      speechPitch: speechPitch ?? this.speechPitch,
      speechVolume: speechVolume ?? this.speechVolume,
      enableHaptics: enableHaptics ?? this.enableHaptics,
      enableVoiceCommands: enableVoiceCommands ?? this.enableVoiceCommands,
      detectionConfidence: detectionConfidence ?? this.detectionConfidence,
      frameIntervalMs: frameIntervalMs ?? this.frameIntervalMs,
      hasCompletedOnboarding:
          hasCompletedOnboarding ?? this.hasCompletedOnboarding,
      announceAllObjects: announceAllObjects ?? this.announceAllObjects,
      languageCode: languageCode ?? this.languageCode,
    );
  }
}
