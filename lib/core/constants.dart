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

  /// Minimum normalised bounding-box area (width × height) for a detection
  /// to be considered valid. Rejects shadow / noise ghosts that produce
  /// tiny or paper-thin boxes.
  static const double minDetectionArea = 0.015; // ~1.5 % of the frame

  /// Only these COCO classes are relevant for blind-navigation assistance.
  /// Everything else (laptop, keyboard, mouse, cup, etc.) is silently dropped
  /// to avoid false-positive speech noise.
  static const Set<String> allowedLabels = {
    // Moving / large — high danger
    'person',
    'car',
    'truck',
    'bus',
    'train',
    'bicycle',
    'motorcycle',
    // Animals — unpredictable
    'dog',
    'cat',
    // Street furniture / obstacles
    'chair',
    'bench',
    'fire hydrant',
    'stop sign',
    'traffic light',
    'parking meter',
    // Indoor obstacles useful for navigation
    'dining table',
    'door',
    'stairs',
    // Desk items
    'laptop',
    'bottle',
    'cup',
    'keyboard',
    'mouse',
    'cell phone',
    'book',
  };

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
