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
  })  : _cameraService = cameraService,
        _detectionService = detectionService,
        _obstacleAnalyzer = obstacleAnalyzer,
        _speechService = speechService,
        _hapticService = hapticService,
        _voiceCommandService = voiceCommandService {
    _connectionSub = _cameraService.connectionStream.listen((info) {
      _connection = info;
      notifyListeners();
    });
    _frameSub = _cameraService.frameStream.listen(_onFrame);
    _buttonEventSub =
        _cameraService.buttonEventStream.listen(_handleButtonEvent);
    _voiceCommandService.onCommand = _handleVoiceCommand;
  }

  final Esp32CameraService _cameraService;
  final ObjectDetectionService _detectionService;
  final ObstacleAnalyzer _obstacleAnalyzer;
  final SpeechService _speechService;
  final HapticService _hapticService;
  final VoiceCommandService _voiceCommandService;

  late StreamSubscription<CameraConnectionInfo> _connectionSub;
  late StreamSubscription<Uint8List> _frameSub;
  late StreamSubscription<String> _buttonEventSub;

  AppSettings _settings = const AppSettings();
  CameraConnectionInfo _connection = const CameraConnectionInfo();
  List<DetectedObject> _detections = [];
  List<ObstacleAlert> _alerts = [];
  Uint8List? _currentFrame;
  bool _isVisionActive = false;
  bool _isProcessing = false;
  String _statusMessage = 'Ready';
  DateTime? _lastSpeechTime;
  String? _lastAnnouncedText;
  AppMode _currentMode = AppMode.objectDetection;

  AppSettings get settings => _settings;
  CameraConnectionInfo get connection => _connection;
  List<DetectedObject> get detections => _detections;
  List<ObstacleAlert> get alerts => _alerts;
  Uint8List? get currentFrame => _currentFrame;
  bool get isVisionActive => _isVisionActive;
  bool get isProcessing => _isProcessing;
  String get statusMessage => _statusMessage;
  bool get isVoiceListening => _voiceCommandService.isListening;
  AppMode get currentMode => _currentMode;

  void updateSettings(AppSettings settings) {
    _settings = settings;
    _cameraService.updateSettings(settings);
    _speechService.updateSettings(settings);
    notifyListeners();
  }

  Future<void> connectCamera() async {
    _statusMessage = 'Connecting...';
    notifyListeners();
    await _cameraService.connect();
    if (_cameraService.connection.isConnected) {
      _statusMessage = 'Camera connected';
      await _speechService.speak('Camera connected');
      await _hapticService.success();
    } else {
      _statusMessage = _cameraService.connection.message;
    }
    notifyListeners();
  }

  Future<void> disconnectCamera() async {
    await stopVision();
    await _cameraService.disconnect();
    _currentFrame = null;
    _detections = [];
    _alerts = [];
    _statusMessage = 'Disconnected';
    notifyListeners();
  }

  Future<void> testConnection(String ip, String path) async {
    _statusMessage = 'Testing connection...';
    notifyListeners();

    final success = await _cameraService.testConnection(ip, path);
    _statusMessage = success ? 'Connection successful' : 'Connection failed';
    if (success) {
      await _speechService.speak('Connection successful');
      await _hapticService.success();
    } else {
      await _speechService.speak('Could not connect to camera');
    }
    notifyListeners();
  }

  Future<void> startVision() async {
    if (!_connection.isConnected) {
      await connectCamera();
      if (!_connection.isConnected) return;
    }

    _isVisionActive = true;
    _statusMessage = 'Vision active';
    await _speechService.speak(
      'Vision assistance started. I will alert you to obstacles.',
      priority: SpeechPriority.high,
    );
    notifyListeners();
  }

  Future<void> stopVision() async {
    _isVisionActive = false;
    _statusMessage = 'Vision stopped';
    await _speechService.stop();
    notifyListeners();
  }

  Future<void> describeScene() async {
    final description = _obstacleAnalyzer.buildSceneDescription(_detections);
    await _speechService.speak(description, priority: SpeechPriority.high);
  }

  Future<void> scanObstacles() async {
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
      }
    }
    notifyListeners();
  }

  void _handleVoiceCommand(String command) {
    if (command.contains('start vision') || command.contains('start')) {
      startVision();
    } else if (command.contains('stop vision') || command.contains('stop')) {
      stopVision();
    } else if (command.contains('describe')) {
      describeScene();
    } else if (command.contains('scan') || command.contains('obstacle')) {
      scanObstacles();
    } else if (command.contains('repeat')) {
      repeatLast();
    } else if (command.contains('settings')) {
      _statusMessage = 'navigate:settings';
    } else if (command.contains('help')) {
      _statusMessage = 'navigate:help';
    }
    notifyListeners();
  }

  void _handleButtonEvent(String action) {
    switch (action) {
      case 'toggle_vision':
        if (_isVisionActive) {
          stopVision();
        } else {
          startVision();
        }
      case 'scan_obstacles':
        scanObstacles();
      case 'describe_scene':
        describeScene();
      // New mode-based button events
      case 'mode_changed':
        // Mode was changed on ESP32, we'll track it
        _statusMessage = 'Mode: ${_currentMode.displayName}';
        _speechService.speak(_currentMode.voiceFeedback, priority: SpeechPriority.high);
        break;
      case 'object_detection_request':
        _handleObjectDetectionAction();
        break;
      case 'ocr_request':
        _handleOcrAction();
        break;
      case 'navigation_request':
        _handleNavigationAction();
        break;
    }
    notifyListeners();
  }

  void _handleObjectDetectionAction() {
    if (!_isVisionActive) {
      startVision();
    }
    _statusMessage = 'Analyzing objects in front of you';
    _speechService.speak('What is in front of me?', priority: SpeechPriority.high);
  }

  void _handleOcrAction() {
    _statusMessage = 'Capturing and reading text';
    _speechService.speak('Capturing and reading text', priority: SpeechPriority.high);
  }

  void _handleNavigationAction() {
    _statusMessage = 'Navigation mode activated';
    _speechService.speak('Navigation assistance activated', priority: SpeechPriority.high);
  }

  void updateModeFromDevice(String modeName) {
    // Parse the mode name from the device and update local state
    switch (modeName) {
      case 'object_detection':
        _currentMode = AppMode.objectDetection;
      case 'ocr':
        _currentMode = AppMode.ocr;
      case 'navigation':
        _currentMode = AppMode.navigation;
    }
    notifyListeners();
  }

  Future<void> _onFrame(Uint8List frame) async {
    _currentFrame = frame;
    if (!_isVisionActive || _isProcessing) {
      notifyListeners();
      return;
    }

    _isProcessing = true;
    try {
      final objects = await _detectionService.detectObjects(
        frame,
        minConfidence: _settings.detectionConfidence,
        announceAllObjects: _settings.announceAllObjects,
      );

      _detections = objects;
      _alerts = _obstacleAnalyzer.analyze(objects);
      await _announceIfNeeded(objects);
    } finally {
      _isProcessing = false;
      notifyListeners();
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
    _connectionSub.cancel();
    _frameSub.cancel();
    _buttonEventSub.cancel();
    super.dispose();
  }
}
