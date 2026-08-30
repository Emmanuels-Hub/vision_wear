/// Enum for the different application modes.
///
/// The ordinal order must match the firmware's `AppMode` enum, because the
/// mode index is what travels over `/mode?set=N`.
enum AppMode { objectDetection, ocr, navigation }

extension AppModeExtension on AppMode {
  /// Wire name shared with the firmware.
  String get wireName {
    switch (this) {
      case AppMode.objectDetection:
        return 'object_detection';
      case AppMode.ocr:
        return 'ocr';
      case AppMode.navigation:
        return 'navigation';
    }
  }

  int get deviceIndex => index;

  String get displayName {
    switch (this) {
      case AppMode.objectDetection:
        return 'Object Detection';
      case AppMode.ocr:
        return 'OCR';
      case AppMode.navigation:
        return 'Navigation';
    }
  }

  String get voiceFeedback {
    switch (this) {
      case AppMode.objectDetection:
        return 'Object Detection Mode';
      case AppMode.ocr:
        return 'OCR Mode';
      case AppMode.navigation:
        return 'Navigation Mode';
    }
  }

  String get actionDescription {
    switch (this) {
      case AppMode.objectDetection:
        return 'What is in front of me?';
      case AppMode.ocr:
        return 'Capture and read text';
      case AppMode.navigation:
        return 'Navigation assistance';
    }
  }
}

/// Parses the firmware's wire name. Returns null for anything unrecognised so
/// callers can keep their current mode rather than silently resetting it.
AppMode? appModeFromWireName(String? name) {
  switch (name) {
    case 'object_detection':
      return AppMode.objectDetection;
    case 'ocr':
      return AppMode.ocr;
    case 'navigation':
      return AppMode.navigation;
    default:
      return null;
  }
}

/// Actions the firmware can report.
class ButtonAction {
  static const modeChanged = 'mode_changed';
  static const modeAnnounce = 'mode_announce';
  static const objectDetectionRequest = 'object_detection_request';
  static const ocrRequest = 'ocr_request';
  static const navigationRequest = 'navigation_request';
  static const toggleVision = 'toggle_vision';

  // Retained so boards still running v2 firmware keep working.
  static const scanObstacles = 'scan_obstacles';
  static const describeScene = 'describe_scene';
}

/// A button event from the ESP32.
class ButtonEvent {
  const ButtonEvent({
    required this.id,
    required this.action,
    required this.mode,
    required this.voiceFeedback,
    required this.timestamp,
  });

  final int id;
  final String action;

  /// Device mode at the moment the button was pressed. Empty on v2 firmware.
  final String mode;
  final String voiceFeedback;
  final DateTime timestamp;

  AppMode? get parsedMode => appModeFromWireName(mode);

  /// Tolerant of missing fields: v2 firmware omitted `mode` and
  /// `voice_feedback`, and the strict version of this parser threw on every
  /// event from those boards.
  factory ButtonEvent.fromJson(Map<String, dynamic> json) {
    return ButtonEvent(
      id: (json['id'] as num?)?.toInt() ?? 0,
      action: json['action'] as String? ?? '',
      mode: json['mode'] as String? ?? '',
      voiceFeedback: json['voice_feedback'] as String? ?? '',
      timestamp: DateTime.now(),
    );
  }

  @override
  String toString() =>
      'ButtonEvent(id: $id, action: $action, mode: $mode, voice: $voiceFeedback)';
}

/// Device status reported by `/status`.
class DeviceStatus {
  const DeviceStatus({
    required this.status,
    required this.device,
    required this.version,
    required this.currentMode,
    required this.availableModes,
    required this.cameraReady,
    this.staConnected = false,
    this.staSsid = '',
    this.staIp = '',
    this.apIp = '',
    this.freeHeap = 0,
    this.uptimeMs = 0,
  });

  final String status;
  final String device;
  final String version;
  final String currentMode;
  final List<String> availableModes;
  final bool cameraReady;

  /// True when the board has joined a normal WiFi network in addition to
  /// serving its own AP. When this is true the phone can stay on a network
  /// that has internet and still reach the camera.
  final bool staConnected;
  final String staSsid;
  final String staIp;
  final String apIp;
  final int freeHeap;
  final int uptimeMs;

  AppMode? get parsedMode => appModeFromWireName(currentMode);

  factory DeviceStatus.fromJson(Map<String, dynamic> json) {
    final sta = json['sta'] as Map<String, dynamic>?;
    final ap = json['ap'] as Map<String, dynamic>?;

    return DeviceStatus(
      status: json['status'] as String? ?? 'unknown',
      device: json['device'] as String? ?? 'VisionWear-CAM',
      version: json['version'] as String? ?? '0.0.0',
      currentMode: json['current_mode'] as String? ?? 'object_detection',
      availableModes: List<String>.from(
        json['available_modes'] as List? ??
            const ['object_detection', 'ocr', 'navigation'],
      ),
      cameraReady: json['camera_ready'] as bool? ?? true,
      staConnected: sta?['connected'] as bool? ?? false,
      staSsid: sta?['ssid'] as String? ?? '',
      staIp: sta?['ip'] as String? ?? '',
      apIp: ap?['ip'] as String? ?? '',
      freeHeap: (json['free_heap'] as num?)?.toInt() ?? 0,
      uptimeMs: (json['uptime_ms'] as num?)?.toInt() ?? 0,
    );
  }
}
