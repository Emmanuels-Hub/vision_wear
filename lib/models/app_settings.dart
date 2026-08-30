import '../core/constants.dart';

class AppSettings {
  const AppSettings({
    this.esp32Ip = AppConstants.defaultEsp32Ip,
    this.capturePath = AppConstants.defaultCapturePath,
    this.eventsPath = AppConstants.defaultEventsPath,
    this.streamPath = AppConstants.defaultStreamPath,
    this.controlPort = AppConstants.controlPort,
    this.streamPort = AppConstants.streamPort,
    this.eventsPort = AppConstants.eventsPort,
    this.usePhoneCamera = false,
    this.autoDiscover = true,
    this.autoReconnect = true,
    this.preferMjpegStream = true,
    this.speechRate = 0.5,
    this.speechPitch = 1.0,
    this.speechVolume = 1.0,
    this.enableHaptics = true,
    this.enableVoiceCommands = true,
    this.detectionConfidence = 0.55,
    this.frameIntervalMs = AppConstants.frameCaptureIntervalMs,
    this.detectionIntervalMs = 350,
    this.hasCompletedOnboarding = false,
    this.announceAllObjects = false,
    this.languageCode = 'en-US',
  });

  final String esp32Ip;
  final String capturePath;
  final String eventsPath;
  final String streamPath;
  final int controlPort;
  final int streamPort;
  final int eventsPort;
  final bool usePhoneCamera;

  /// Listen for the device's UDP beacon and adopt whatever address it reports,
  /// so the user never has to type an IP after switching networks.
  final bool autoDiscover;

  /// Keep retrying forever in the background when the link drops.
  final bool autoReconnect;

  /// Use the single long-lived MJPEG connection instead of polling /capture.
  final bool preferMjpegStream;

  final double speechRate;
  final double speechPitch;
  final double speechVolume;
  final bool enableHaptics;
  final bool enableVoiceCommands;
  final double detectionConfidence;

  /// Only used by the /capture polling fallback and the phone camera.
  final int frameIntervalMs;

  /// Minimum gap between inference runs. Frames still render at full rate;
  /// this only throttles the expensive YOLO pass so the preview stays smooth.
  final int detectionIntervalMs;

  final bool hasCompletedOnboarding;
  final bool announceAllObjects;
  final String languageCode;

  String get baseUrl => 'http://$esp32Ip:$controlPort';
  String get captureUrl => 'http://$esp32Ip:$controlPort$capturePath';
  String get statusUrl =>
      'http://$esp32Ip:$controlPort${AppConstants.defaultStatusPath}';
  String get healthUrl =>
      'http://$esp32Ip:$controlPort${AppConstants.defaultHealthPath}';
  String get streamUrl => 'http://$esp32Ip:$streamPort$streamPath';
  String get eventsUrl => 'http://$esp32Ip:$eventsPort$eventsPath';

  String modeUrl(int modeIndex) =>
      'http://$esp32Ip:$controlPort/mode?set=$modeIndex';

  AppSettings copyWith({
    String? esp32Ip,
    String? capturePath,
    String? eventsPath,
    String? streamPath,
    int? controlPort,
    int? streamPort,
    int? eventsPort,
    bool? usePhoneCamera,
    bool? autoDiscover,
    bool? autoReconnect,
    bool? preferMjpegStream,
    double? speechRate,
    double? speechPitch,
    double? speechVolume,
    bool? enableHaptics,
    bool? enableVoiceCommands,
    double? detectionConfidence,
    int? frameIntervalMs,
    int? detectionIntervalMs,
    bool? hasCompletedOnboarding,
    bool? announceAllObjects,
    String? languageCode,
  }) {
    return AppSettings(
      esp32Ip: esp32Ip ?? this.esp32Ip,
      capturePath: capturePath ?? this.capturePath,
      eventsPath: eventsPath ?? this.eventsPath,
      streamPath: streamPath ?? this.streamPath,
      controlPort: controlPort ?? this.controlPort,
      streamPort: streamPort ?? this.streamPort,
      eventsPort: eventsPort ?? this.eventsPort,
      usePhoneCamera: usePhoneCamera ?? this.usePhoneCamera,
      autoDiscover: autoDiscover ?? this.autoDiscover,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      preferMjpegStream: preferMjpegStream ?? this.preferMjpegStream,
      speechRate: speechRate ?? this.speechRate,
      speechPitch: speechPitch ?? this.speechPitch,
      speechVolume: speechVolume ?? this.speechVolume,
      enableHaptics: enableHaptics ?? this.enableHaptics,
      enableVoiceCommands: enableVoiceCommands ?? this.enableVoiceCommands,
      detectionConfidence: detectionConfidence ?? this.detectionConfidence,
      frameIntervalMs: frameIntervalMs ?? this.frameIntervalMs,
      detectionIntervalMs: detectionIntervalMs ?? this.detectionIntervalMs,
      hasCompletedOnboarding:
          hasCompletedOnboarding ?? this.hasCompletedOnboarding,
      announceAllObjects: announceAllObjects ?? this.announceAllObjects,
      languageCode: languageCode ?? this.languageCode,
    );
  }

  Map<String, dynamic> toJson() => {
    'esp32Ip': esp32Ip,
    'capturePath': capturePath,
    'eventsPath': eventsPath,
    'streamPath': streamPath,
    'controlPort': controlPort,
    'streamPort': streamPort,
    'eventsPort': eventsPort,
    'usePhoneCamera': usePhoneCamera,
    'autoDiscover': autoDiscover,
    'autoReconnect': autoReconnect,
    'preferMjpegStream': preferMjpegStream,
    'speechRate': speechRate,
    'speechPitch': speechPitch,
    'speechVolume': speechVolume,
    'enableHaptics': enableHaptics,
    'enableVoiceCommands': enableVoiceCommands,
    'detectionConfidence': detectionConfidence,
    'frameIntervalMs': frameIntervalMs,
    'detectionIntervalMs': detectionIntervalMs,
    'hasCompletedOnboarding': hasCompletedOnboarding,
    'announceAllObjects': announceAllObjects,
    'languageCode': languageCode,
  };

  factory AppSettings.fromJson(Map<String, dynamic> map) {
    const defaults = AppSettings();
    return AppSettings(
      esp32Ip: map['esp32Ip'] as String? ?? defaults.esp32Ip,
      capturePath: map['capturePath'] as String? ?? defaults.capturePath,
      eventsPath: map['eventsPath'] as String? ?? defaults.eventsPath,
      streamPath: map['streamPath'] as String? ?? defaults.streamPath,
      controlPort: map['controlPort'] as int? ?? defaults.controlPort,
      streamPort: map['streamPort'] as int? ?? defaults.streamPort,
      eventsPort: map['eventsPort'] as int? ?? defaults.eventsPort,
      usePhoneCamera: map['usePhoneCamera'] as bool? ?? defaults.usePhoneCamera,
      autoDiscover: map['autoDiscover'] as bool? ?? defaults.autoDiscover,
      autoReconnect: map['autoReconnect'] as bool? ?? defaults.autoReconnect,
      preferMjpegStream:
          map['preferMjpegStream'] as bool? ?? defaults.preferMjpegStream,
      speechRate: (map['speechRate'] as num?)?.toDouble() ?? defaults.speechRate,
      speechPitch:
          (map['speechPitch'] as num?)?.toDouble() ?? defaults.speechPitch,
      speechVolume:
          (map['speechVolume'] as num?)?.toDouble() ?? defaults.speechVolume,
      enableHaptics: map['enableHaptics'] as bool? ?? defaults.enableHaptics,
      enableVoiceCommands:
          map['enableVoiceCommands'] as bool? ?? defaults.enableVoiceCommands,
      detectionConfidence: (map['detectionConfidence'] as num?)?.toDouble() ??
          defaults.detectionConfidence,
      frameIntervalMs:
          (map['frameIntervalMs'] as num?)?.toInt() ?? defaults.frameIntervalMs,
      detectionIntervalMs: (map['detectionIntervalMs'] as num?)?.toInt() ??
          defaults.detectionIntervalMs,
      hasCompletedOnboarding: map['hasCompletedOnboarding'] as bool? ??
          defaults.hasCompletedOnboarding,
      announceAllObjects:
          map['announceAllObjects'] as bool? ?? defaults.announceAllObjects,
      languageCode: map['languageCode'] as String? ?? defaults.languageCode,
    );
  }
}
