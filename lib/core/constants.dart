class AppConstants {
  static const String appName = 'Vision Wear';
  static const String appTagline = 'Your AI vision companion';

  static const String defaultEsp32Ip = '192.168.4.1';
  static const String defaultCapturePath = '/capture';
  static const String defaultStreamPath = '/stream';
  static const String defaultEventsPath = '/events';
  static const int buttonPollIntervalMs = 300;

  static const int frameCaptureIntervalMs = 500;
  static const int speechCooldownMs = 2500;
  static const int criticalAlertCooldownMs = 1200;

  static const double obstacleProximityThreshold = 0.18;
  static const double criticalProximityThreshold = 0.35;

  static const List<String> hazardLabels = [
    'person',
    'car',
    'truck',
    'bus',
    'bicycle',
    'motorcycle',
    'stairs',
    'chair',
    'bench',
    'pole',
    'fire hydrant',
    'stop sign',
    'traffic light',
    'dog',
    'cat',
  ];

  static const List<String> voiceCommands = [
    'start vision',
    'stop vision',
    'describe scene',
    'scan obstacles',
    'go home',
    'open settings',
    'repeat',
    'help',
  ];
}
