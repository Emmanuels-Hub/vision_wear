import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../models/app_mode.dart';
import '../models/app_settings.dart';
import '../models/connection_state.dart';
import '../models/detected_object.dart';
import '../models/obstacle_alert.dart';
import '../services/esp32_camera_service.dart';
import '../services/haptic_service.dart';
import '../services/object_detection_service.dart';
import '../services/obstacle_analyzer.dart';
import '../services/speech_service.dart';
import '../services/voice_command_service.dart';

class VisionProvider extends ChangeNotifier {
  VisionProvider({
    required Esp32CameraService cameraService,
    required ObjectDetectionService detectionService,
    required ObstacleAnalyzer obstacleAnalyzer,
    required SpeechService speechService,
    required HapticService hapticService,
    required VoiceCommandService voiceCommandService,
  }) : _cameraService = cameraService,
       _detectionService = detectionService,
       _obstacleAnalyzer = obstacleAnalyzer,
       _speechService = speechService,
       _hapticService = hapticService,
       _voiceCommandService = voiceCommandService {
    _connectionSub = _cameraService.connectionStream.listen(_onConnectionChange);
    _frameSub = _cameraService.frameStream.listen(_onFrame);
    _buttonEventSub = _cameraService.buttonEventStream.listen(
      _handleButtonEvent,
    );
    _voiceCommandService.onCommand = _handleVoiceCommand;
  }

  final Esp32CameraService _cameraService;
  final ObjectDetectionService _detectionService;
  final ObstacleAnalyzer _obstacleAnalyzer;
  final SpeechService _speechService;
  final HapticService _hapticService;
  final VoiceCommandService _voiceCommandService;

  late final StreamSubscription<CameraConnectionInfo> _connectionSub;
  late final StreamSubscription<Uint8List> _frameSub;
  late final StreamSubscription<ButtonEvent> _buttonEventSub;

  AppSettings _settings = const AppSettings();
  CameraConnectionInfo _connection = const CameraConnectionInfo();
  List<DetectedObject> _detections = [];
  List<ObstacleAlert> _alerts = [];
  bool _isVisionActive = false;
  bool _isProcessing = false;
  String _statusMessage = 'Ready';
  DateTime? _lastSpeechTime;
  DateTime? _lastDetectionRun;
  String? _lastAnnouncedText;
  AppMode _currentMode = AppMode.objectDetection;
  bool _disposed = false;

  /// Frames update far faster than anything else in the UI. Publishing them
  /// through a separate listenable keeps `notifyListeners()` for real state
  /// changes, so only the preview widget rebuilds at frame rate instead of the
  /// whole screen.
  final ValueNotifier<Uint8List?> frameNotifier = ValueNotifier<Uint8List?>(
    null,
  );

  /// Tracks whether the user has been told the link dropped, so a flapping
  /// connection does not produce a stream of spoken warnings.
  bool _announcedDisconnect = false;

  AppSettings get settings => _settings;
  CameraConnectionInfo get connection => _connection;
  List<DetectedObject> get detections => _detections;
  List<ObstacleAlert> get alerts => _alerts;
  Uint8List? get currentFrame => frameNotifier.value;
  bool get isVisionActive => _isVisionActive;
  bool get isProcessing => _isProcessing;
  String get statusMessage => _statusMessage;
  bool get isVoiceListening => _voiceCommandService.isListening;
  AppMode get currentMode => _currentMode;
  bool get isDetectionReady => _detectionService.isReady;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// Loads the detection model. Must be awaited before vision can produce any
  /// results — without it `detectObjects` returns an empty list for every
  /// frame and the app looks connected but detects nothing.
  Future<void> initializeDetection() async {
    await _detectionService.initialize();
    _safeNotify();
  }

  void updateSettings(AppSettings settings) {
    _settings = settings;
    _cameraService.updateSettings(settings);
    _speechService.updateSettings(settings);
    _safeNotify();
  }

  // ===================== Connection =====================

  Future<void> connectCamera() async {
    _statusMessage = 'Connecting...';
    _safeNotify();
    await _cameraService.connect();
  }

  Future<void> disconnectCamera() async {
    await stopVision();
    await _cameraService.disconnect();
    frameNotifier.value = null;
    _detections = [];
    _alerts = [];
    _statusMessage = 'Disconnected';
    _safeNotify();
  }

  Future<void> testConnection(String ip, String path) async {
    _statusMessage = 'Testing connection...';
    _safeNotify();

    final success = await _cameraService.testConnection(ip, path);
    _statusMessage = success ? 'Connection successful' : 'Connection failed';
    if (success) {
      await _speechService.speak('Connection successful');
      await _hapticService.success();
    } else {
      await _speechService.speak('Could not connect to camera');
    }
    _safeNotify();
  }

  Future<bool> provisionDeviceWifi(String ssid, String password) {
    return _cameraService.provisionDeviceWifi(ssid, password);
  }

  Future<DeviceStatus?> fetchDeviceStatus() => _cameraService.fetchStatus();

  void _onConnectionChange(CameraConnectionInfo info) {
    final wasConnected = _connection.isConnected;
    _connection = info;

    // The device reports its own mode on every event response. Trust it over
    // local state so the phone can never disagree with the physical button.
    final reported = appModeFromWireName(info.deviceMode);
    if (reported != null && reported != _currentMode) {
      _currentMode = reported;
    }

    if (info.isConnected && !wasConnected) {
      _statusMessage = 'Camera connected';
      if (_announcedDisconnect) {
        _announcedDisconnect = false;
        // Only speak on recovery, not on the very first connect, where
        // startVision already announces.
        unawaited(
          _speechService.speak(
            'Camera reconnected',
            priority: SpeechPriority.high,
          ),
        );
        unawaited(_hapticService.success());
      }
    } else if (!info.isConnected && wasConnected) {
      _statusMessage = info.message;
      // A blind user needs to know the feed is gone; silence would read as
      // "the path is clear".
      if (!_announcedDisconnect) {
        _announcedDisconnect = true;
        unawaited(
          _speechService.speak(
            'Camera disconnected. Reconnecting.',
            priority: SpeechPriority.critical,
          ),
        );
        unawaited(_hapticService.alert(critical: true));
      }
    } else if (!info.isConnected) {
      _statusMessage = info.message;
    }

    _safeNotify();
  }

  // ===================== Vision lifecycle =====================

  Future<void> startVision() async {
    if (!_connection.isConnected) {
      await connectCamera();
    }

    if (!_detectionService.isReady) {
      await _detectionService.initialize();
    }

    _isVisionActive = true;
    _statusMessage = 'Vision active';
    _safeNotify();

    await _speechService.speak(
      'Vision assistance started. I will alert you to obstacles.',
      priority: SpeechPriority.high,
    );
  }

  Future<void> stopVision() async {
    _isVisionActive = false;
    _statusMessage = 'Vision stopped';
    await _speechService.stop();
    _safeNotify();
  }

  Future<void> describeScene() async {
    final description = _obstacleAnalyzer.buildSceneDescription(_detections);
    await _speechService.speak(description, priority: SpeechPriority.high);
  }

  Future<void> scanObstacles() async {
    if (!_connection.isConnected) {
      await _speechService.speak(
        'Camera is not connected. Reconnecting now.',
        priority: SpeechPriority.high,
      );
      return;
    }

    if (_detections.isEmpty) {
      await _speechService.speak(
        'No obstacles detected. Path appears clear.',
        priority: SpeechPriority.high,
      );
      return;
    }

    final hazards = _detections.where((d) => d.isHazard).toList();
    if (hazards.isEmpty) {
      await _speechService.speak(
        'No immediate hazards. ${_detections.length} objects detected.',
        priority: SpeechPriority.high,
      );
      return;
    }

    final text = hazards.map((h) => h.announcement).take(3).join('. ');
    await _speechService.speak(text, priority: SpeechPriority.high);
  }

  Future<void> repeatLast() async {
    await _speechService.repeatLast();
  }

  Future<void> toggleVoiceListening() async {
    if (!_settings.enableVoiceCommands) return;

    if (_voiceCommandService.isListening) {
      await _voiceCommandService.stopListening();
    } else {
      final available = await _voiceCommandService.initialize();
      if (available) {
        await _speechService.speak('Listening for command');
        await _voiceCommandService.startListening();
      } else {
        await _speechService.speak('Voice commands are not available');
      }
    }
    _safeNotify();
  }

  // ===================== Modes =====================

  /// Cycles the mode from the phone and pushes it to the device so both stay
  /// in agreement.
  Future<void> cycleMode() async {
    final next = AppMode.values[(_currentMode.index + 1) % AppMode.values.length];
    await setMode(next);
  }

  Future<void> setMode(AppMode mode) async {
    _currentMode = mode;
    _statusMessage = 'Mode: ${mode.displayName}';
    _safeNotify();

    await _speechService.speak(
      mode.voiceFeedback,
      priority: SpeechPriority.high,
    );
    // Best-effort: if the device is unreachable the next /events response will
    // resynchronise us anyway.
    await _cameraService.setDeviceMode(mode);
  }

  void _handleVoiceCommand(String command) {
    if (command.contains('start vision') || command.contains('start')) {
      unawaited(startVision());
    } else if (command.contains('stop vision') || command.contains('stop')) {
      unawaited(stopVision());
    } else if (command.contains('describe')) {
      unawaited(describeScene());
    } else if (command.contains('scan') || command.contains('obstacle')) {
      unawaited(scanObstacles());
    } else if (command.contains('repeat')) {
      unawaited(repeatLast());
    } else if (command.contains('mode')) {
      unawaited(cycleMode());
    } else if (command.contains('settings')) {
      _statusMessage = 'navigate:settings';
    } else if (command.contains('help')) {
      _statusMessage = 'navigate:help';
    }
    _safeNotify();
  }

  void _handleButtonEvent(ButtonEvent event) {
    // Adopt the mode the device reported alongside the press before acting on
    // it. The old code read `_currentMode`, which was never updated from the
    // device, so every mode announcement spoke the wrong mode.
    final reported = event.parsedMode;
    if (reported != null) _currentMode = reported;

    switch (event.action) {
      case ButtonAction.modeChanged:
      case ButtonAction.modeAnnounce:
        _statusMessage = 'Mode: ${_currentMode.displayName}';
        unawaited(
          _speechService.speak(
            event.voiceFeedback.isNotEmpty
                ? event.voiceFeedback
                : _currentMode.voiceFeedback,
            priority: SpeechPriority.high,
          ),
        );
        unawaited(_hapticService.success());

      case ButtonAction.objectDetectionRequest:
        _handleObjectDetectionAction();

      case ButtonAction.ocrRequest:
        _handleOcrAction();

      case ButtonAction.navigationRequest:
        _handleNavigationAction();

      case ButtonAction.toggleVision:
        if (_isVisionActive) {
          unawaited(stopVision());
        } else {
          unawaited(startVision());
        }

      // v2 firmware compatibility.
      case ButtonAction.scanObstacles:
        unawaited(scanObstacles());

      case ButtonAction.describeScene:
        unawaited(describeScene());
    }

    _safeNotify();
  }

  void _handleObjectDetectionAction() {
    if (!_isVisionActive) {
      unawaited(startVision());
    }
    _statusMessage = 'Analyzing objects in front of you';
    // Answer the question rather than repeating it back to the user.
    unawaited(describeScene());
  }

  void _handleOcrAction() {
    _statusMessage = 'Text reading is not available yet';
    unawaited(
      _speechService.speak(
        'Text reading is not available in this version.',
        priority: SpeechPriority.high,
      ),
    );
  }

  void _handleNavigationAction() {
    _statusMessage = 'Navigation is not available yet';
    unawaited(
      _speechService.speak(
        'Navigation assistance is not available in this version.',
        priority: SpeechPriority.high,
      ),
    );
  }

  // ===================== Frame pipeline =====================

  Future<void> _onFrame(Uint8List frame) async {
    // Render immediately; this does not go through notifyListeners().
    frameNotifier.value = frame;

    if (!_isVisionActive || _isProcessing) return;
    if (!_detectionService.isReady) return;

    // Throttle inference independently of the frame rate. The MJPEG stream can
    // deliver 20+ fps, which is far more than the model can consume, and
    // running flat out both drains the battery and backs up the frame queue.
    final now = DateTime.now();
    final last = _lastDetectionRun;
    if (last != null &&
        now.difference(last).inMilliseconds < _settings.detectionIntervalMs) {
      return;
    }
    _lastDetectionRun = now;

    _isProcessing = true;
    _safeNotify();

    try {
      final objects = await _detectionService.detectObjects(
        frame,
        minConfidence: _settings.detectionConfidence,
        announceAllObjects: _settings.announceAllObjects,
        imageWidth: AppConstants.frameWidth,
        imageHeight: AppConstants.frameHeight,
      );

      _detections = objects;
      _alerts = _obstacleAnalyzer.analyze(objects);
      await _announceIfNeeded(objects);
    } catch (e) {
      debugPrint('Detection failed: $e');
    } finally {
      _isProcessing = false;
      _safeNotify();
    }
  }

  Future<void> _announceIfNeeded(List<DetectedObject> objects) async {
    final announcement = _obstacleAnalyzer.getPriorityAnnouncement(objects);
    if (announcement == null) return;

    final now = DateTime.now();
    final isCritical = _obstacleAnalyzer.isCriticalHazard(objects);
    final cooldown = isCritical
        ? AppConstants.criticalAlertCooldownMs
        : AppConstants.speechCooldownMs;

    if (_lastAnnouncedText == announcement &&
        _lastSpeechTime != null &&
        now.difference(_lastSpeechTime!).inMilliseconds < cooldown) {
      return;
    }

    _lastAnnouncedText = announcement;
    _lastSpeechTime = now;

    await _speechService.speak(
      announcement,
      priority: isCritical ? SpeechPriority.critical : SpeechPriority.normal,
    );

    if (_settings.enableHaptics && isCritical) {
      await _hapticService.alert(critical: true);
    } else if (_settings.enableHaptics &&
        objects.any((o) => o.isHazard && o.proximity == ProximityLevel.close)) {
      await _hapticService.alert();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _connectionSub.cancel();
    _frameSub.cancel();
    _buttonEventSub.cancel();
    frameNotifier.dispose();
    super.dispose();
  }
}
