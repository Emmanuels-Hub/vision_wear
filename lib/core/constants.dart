class AppConstants {
  static const String appName = 'Vision Wear';
  static const String appTagline = 'Your AI vision companion';

  // ---- Device endpoints -------------------------------------------------
  // The firmware serves /stream and /events on their own ports so that a
  // blocking stream or long-poll cannot stall the control endpoints.
  static const String defaultEsp32Ip = '192.168.4.1';
  static const String defaultCapturePath = '/capture';
  static const String defaultStreamPath = '/stream';
  static const String defaultEventsPath = '/events';
  static const String defaultStatusPath = '/status';
  static const String defaultHealthPath = '/health';

  static const int controlPort = 80;
  static const int streamPort = 81;
  static const int eventsPort = 82;

  /// UDP port the firmware broadcasts its discovery beacon on.
  static const int discoveryPort = 4210;
  static const String discoveryDeviceName = 'VisionWear-CAM';

  static const String apSsid = 'VisionWear-CAM';
  static const String apPassword = 'visionwear';

  // ---- Timing -----------------------------------------------------------
  /// How long the device holds an /events request open. Kept below the client
  /// read timeout so a quiet period reads as a normal empty response rather
  /// than a connection failure.
  static const int eventLongPollMs = 20000;
  static const int eventRequestTimeoutMs = 28000;

  /// Fallback interval used only when long-poll is unavailable.
  static const int buttonPollIntervalMs = 300;

  static const int frameCaptureIntervalMs = 500;
  static const int captureTimeoutMs = 4000;
  static const int healthTimeoutMs = 1500;
  static const int discoveryTimeoutMs = 4000;

  /// Reconnect backoff. Deliberately starts fast: a wearable that drops for
  /// three seconds is a safety problem, not an inconvenience.
  static const int reconnectInitialDelayMs = 400;
  static const int reconnectMaxDelayMs = 5000;

  /// If no frame arrives within this window while nominally connected, the
  /// link is treated as dead and rebuilt. Catches the half-open TCP sockets
  /// that a sleeping ESP32 or a WiFi handover leaves behind.
  static const int frameStallTimeoutMs = 4000;

  static const int speechCooldownMs = 2500;
  static const int criticalAlertCooldownMs = 1200;

  // ---- Detection --------------------------------------------------------
  static const double obstacleProximityThreshold = 0.18;
  static const double criticalProximityThreshold = 0.35;

  /// Native resolution of the JPEG the firmware sends (FRAMESIZE_VGA).
  static const int frameWidth = 640;
  static const int frameHeight = 480;

  /// Minimum share of the frame a detection must occupy to be taken seriously.
  /// Rejects shadow/noise ghosts that come back as tiny or paper-thin boxes.
  static const double minDetectionArea = 0.015; // ~1.5 % of the frame

  /// Only these COCO classes are relevant for blind-navigation assistance.
  /// Everything else is silently dropped to avoid false-positive speech noise.
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
