/// Enum for the different application modes
enum AppMode { objectDetection, ocr, navigation }

extension AppModeExtension on AppMode {
  String get name {
    switch (this) {
      case AppMode.objectDetection:
        return 'object_detection';
      case AppMode.ocr:
        return 'ocr';
      case AppMode.navigation:
        return 'navigation';
    }
  }

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

/// Represents a button event from the ESP32
class ButtonEvent {
  ButtonEvent({
    required this.id,
    required this.action,
    required this.mode,
    required this.voiceFeedback,
    required this.timestamp,
  });

  final int id;
  final String
  action; // 'mode_changed', 'object_detection_request', 'ocr_request', 'navigation_request'
  final String mode; // 'object_detection', 'ocr', 'navigation'
  final String voiceFeedback;
  final DateTime timestamp;

  factory ButtonEvent.fromJson(Map<String, dynamic> json) {
    return ButtonEvent(
      id: json['id'] as int,
      action: json['action'] as String,
      mode: json['mode'] as String,
      voiceFeedback: json['voice_feedback'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
    );
  }

  @override
  String toString() =>
      'ButtonEvent(id: $id, action: $action, mode: $mode, voice: $voiceFeedback)';
}

/// Represents the device status from ESP32
class DeviceStatus {
  DeviceStatus({
    required this.status,
    required this.device,
    required this.version,
    required this.currentMode,
    required this.availableModes,
  });

  final String status;
  final String device;
  final String version;
  final String currentMode;
  final List<String> availableModes;

  factory DeviceStatus.fromJson(Map<String, dynamic> json) {
    return DeviceStatus(
      status: json['status'] as String,
      device: json['device'] as String,
      version: json['version'] as String,
      currentMode: json['current_mode'] as String? ?? 'object_detection',
      availableModes: List<String>.from(
        json['available_modes'] as List? ??
            ['object_detection', 'ocr', 'navigation'],
      ),
    );
  }
}
