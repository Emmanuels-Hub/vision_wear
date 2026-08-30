import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../core/constants.dart';
import '../models/app_mode.dart';
import '../models/app_settings.dart';
import '../models/connection_state.dart';
import '../models/detected_object.dart';
import '../models/obstacle_alert.dart';
import '../models/tracked_object.dart';
import '../services/esp32_camera_service.dart';
import '../services/haptic_service.dart';
import '../services/object_detection_service.dart';
import '../services/object_tracker.dart';
import '../services/obstacle_analyzer.dart';
import '../services/priority_engine.dart';
import '../services/scene_understanding.dart';
import '../services/speech_scheduler.dart';
import '../services/speech_service.dart';
import '../services/voice_command_service.dart';
import '../services/ocr_service.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class VisionProvider extends ChangeNotifier {
  VisionProvider({
    required Esp32CameraService cameraService,
    required ObjectDetectionService detectionService,
    required ObstacleAnalyzer obstacleAnalyzer,
    required SpeechService speechService,
    required HapticService hapticService,
    required VoiceCommandService voiceCommandService,
    required OcrService ocrService,
  })  : _cameraService = cameraService,
        _detectionService = detectionService,
        _obstacleAnalyzer = obstacleAnalyzer,
        _speechService = speechService,
        _hapticService = hapticService,
        _voiceCommandService = voiceCommandService,
        _ocrService = ocrService {
    // Initialise pipeline stages.
    _scheduler = SpeechScheduler(speechService: _speechService);

    _connectionSub = _cameraService.connectionStream.listen((info) {
      _connection = info;
      notifyListeners();
    });
    _frameSub = _cameraService.frameStream.listen(_onEsp32Frame);
    _buttonEventSub =
        _cameraService.buttonEventStream.listen(handleButtonEvent);
    _voiceCommandService.onCommand = _handleVoiceCommand;
  }

  // ── Injected services ──────────────────────────────────────────────────────

  final Esp32CameraService _cameraService;
  final ObjectDetectionService _detectionService;
  final ObstacleAnalyzer _obstacleAnalyzer;
  final SpeechService _speechService;
  final HapticService _hapticService;
  final VoiceCommandService _voiceCommandService;
  final OcrService _ocrService;

  // ── Pipeline stages (created in constructor body) ──────────────────────────

  /// Stage 1 is YOLO — runs inside [YOLOView] or [ObjectDetectionService].

  /// Stage 2: assigns stable IDs to objects across frames.
  final ObjectTracker _tracker = ObjectTracker();

  /// Stage 3: scores and sorts tracked objects by danger level.
  final PriorityEngine _priorityEngine = PriorityEngine();

  /// Stage 4: converts ranked objects into human-readable phrases.
  final SceneUnderstanding _sceneUnderstanding = SceneUnderstanding();

  /// Stage 5: smart cooldown gate before reaching TTS.
  late final SpeechScheduler _scheduler;

  // ── Stream subscriptions ───────────────────────────────────────────────────

  late StreamSubscription<CameraConnectionInfo> _connectionSub;
  late StreamSubscription<Uint8List> _frameSub;
  late StreamSubscription<String> _buttonEventSub;

  // ── UI-observable state ────────────────────────────────────────────────────

  AppSettings _settings = const AppSettings();
  CameraConnectionInfo _connection = const CameraConnectionInfo();
  List<DetectedObject> _detections = [];
  List<ObstacleAlert> _alerts = [];
  Uint8List? _currentFrame; // Only populated in ESP32 mode
  bool _isVisionActive = false;
  bool _isProcessing = false; // Only used in ESP32 mode
  String _statusMessage = 'Ready';
  String _lastOcrText = '';
  AppMode _currentMode = AppMode.objectDetection;

  /// Cached ranked list — used by describeScene() and the UI.
  List<ScoredObject> _lastRanked = [];

  /// Throttle for notifyListeners() to avoid 30–60 rebuilds/second.
  DateTime? _lastUIUpdate;
  static const int _uiUpdateMinGapMs = 100; // max ~10 rebuilds/s

  // ── Getters ────────────────────────────────────────────────────────────────

  AppSettings get settings => _settings;
  CameraConnectionInfo get connection => _connection;
  List<DetectedObject> get detections => _detections;
  List<ObstacleAlert> get alerts => _alerts;
  Uint8List? get currentFrame => _currentFrame;
  bool get isVisionActive => _isVisionActive;
  bool get isProcessing => _isProcessing;
  bool get isModelReady => _detectionService.isReady;
  String get statusMessage => _statusMessage;
  /// Most-recent OCR result (empty when none)
  String get ocrText => _lastOcrText;
  bool get isVoiceListening => _voiceCommandService.isListening;
  AppMode get currentMode => _currentMode;

  /// Exposes the phone [CameraController] so the UI can pass it to [YOLOView].
  CameraController? get phoneController => _cameraService.phoneController;

  /// True when using the phone camera (vs ESP32-CAM).
  bool get isUsingPhoneCamera => _cameraService.isUsingPhoneCamera;

  // ── Settings ───────────────────────────────────────────────────────────────

  void updateSettings(AppSettings settings) {
    _settings = settings;
    _cameraService.updateSettings(settings);
    _speechService.updateSettings(settings);
    notifyListeners();
  }

  // ── Camera connection ──────────────────────────────────────────────────────

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

  // ── Vision lifecycle ───────────────────────────────────────────────────────

  Future<void> startVision() async {
    if (!_connection.isConnected) {
      await connectCamera();
      if (!_connection.isConnected) return;
    }

    if (!_detectionService.isReady) {
      _statusMessage = 'Loading object detection model...';
      notifyListeners();
      await _detectionService.initialize();
      if (!_detectionService.isReady) {
        _statusMessage = 'Object detection model failed to load';
        notifyListeners();
        return;
      }
    }

    _isVisionActive = true;
    _statusMessage = 'Vision active';
    _tracker.reset();
    _scheduler.reset();

    await _speechService.speak(
      'Vision assistance started. I will alert you to obstacles.',
      priority: SpeechPriority.high,
    );
    notifyListeners();
  }

  Future<void> stopVision() async {
    _isVisionActive = false;
    _statusMessage = 'Vision stopped';
    _tracker.reset();
    _scheduler.reset();
    await _speechService.stop();
    notifyListeners();
  }

  // ── Manual actions ─────────────────────────────────────────────────────────

  Future<void> describeScene() async {
    final description = _sceneUnderstanding.buildFullDescription(_lastRanked);
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

  // ── Pipeline: phone camera (live stream via YOLOView) ─────────────────────
  //
  // Diagram:
  //   YOLO (native YOLOView)
  //     ↓  onResult fires every processed frame
  //   onLiveDetections()
  //     ↓  raw YOLOResult list
  //   ObjectTracker.update()       – stable object IDs across frames
  //     ↓  List<TrackedObject>
  //   PriorityEngine.rank()        – score + sort by danger
  //     ↓  List<ScoredObject>
  //   SceneUnderstanding (inside SpeechScheduler)
  //     ↓  concise phrase
  //   SpeechScheduler.process()    – cooldown gating
  //     ↓  if all gates pass
  //   SpeechService.speak()        – Text-to-Speech

  /// Entry point called by [YOLOView.onResult] on every processed frame.
  void onLiveDetections(List<YOLOResult> results) {
    if (!_isVisionActive) return;

    // Stage 1 result: raw YOLO detections as typed records.
    // Filter by class allowlist and minimum bounding-box area to reject
    // irrelevant objects (laptop, cup…) and shadow/noise ghosts.
    final detections = results
        .where((r) {
          if (r.confidence < _settings.detectionConfidence) return false;
          final label = r.className.toLowerCase();
          if (!AppConstants.allowedLabels.contains(label)) return false;
          final area = r.normalizedBox.width * r.normalizedBox.height;
          if (area < AppConstants.minDetectionArea) return false;
          return true;
        })
        .map((r) => (label: r.className, box: r.normalizedBox, confidence: r.confidence))
        .toList();

    // Stage 2: object tracking.
    final trackResult = _tracker.update(detections);
    
    // Optional center filtering.
    var activeTracks = trackResult.active;
    if (_settings.announceOnlyCenter) {
      activeTracks = activeTracks.where((t) {
        final cx = t.boundingBox.center.dx;
        return cx > 0.33 && cx < 0.67;
      }).toList();
    }

    // Stage 3: priority scoring.
    final ranked = _priorityEngine.rank(activeTracks);
    _lastRanked = ranked;

    // Update UI state (throttled to ≤10 fps to avoid excessive rebuilds).
    _detections = ranked.map((o) => _trackedToDetected(o.track)).toList();
    _alerts = _obstacleAnalyzer.analyze(_detections);
    _throttledNotify();

    // Stages 4 + 5: scene language + speech gating. Fire-and-forget.
    _scheduler.process(
      ranked: ranked,
      dropped: trackResult.dropped,
      settings: _settings,
    ).ignore();
  }

  // ── Pipeline: ESP32-CAM (HTTP JPEG polling) ────────────────────────────────
  //
  // Same 5 stages but stage 1 is ObjectDetectionService.detectObjects()
  // instead of YOLOView since we get raw JPEG bytes from the network.

  bool _esp32Processing = false;
  DateTime? _lastEsp32Detection;

  Future<void> _onEsp32Frame(Uint8List frame) async {
    // Phone camera uses YOLOView — ignore frames on that path.
    if (_cameraService.isUsingPhoneCamera) return;

    _currentFrame = frame;
    _throttledNotify();

    if (!_isVisionActive || _esp32Processing) return;

    // Throttle inference to avoid overloading the device.
    final now = DateTime.now();
    if (_lastEsp32Detection != null &&
        now.difference(_lastEsp32Detection!).inMilliseconds < 1200) {
      return;
    }

    _esp32Processing = true;
    _isProcessing = true;
    _throttledNotify();

    try {
      debugPrint('[Vision] ESP32 inference on ${frame.length} bytes…');
      final rawObjects = await _detectionService.detectObjects(
        frame,
        minConfidence: _settings.detectionConfidence,
        announceAllObjects: _settings.announceAllObjects,
        imageWidth: 640,
        imageHeight: 480,
      );

      _lastEsp32Detection = DateTime.now();

      // Stage 2: tracking.
      final detections = rawObjects
          .map((o) => (label: o.label, box: o.boundingBox, confidence: o.confidence))
          .toList();
      final trackResult = _tracker.update(detections);
      
      var activeTracks = trackResult.active;
      if (_settings.announceOnlyCenter) {
        activeTracks = activeTracks.where((t) {
          final cx = t.boundingBox.center.dx;
          return cx > 0.33 && cx < 0.67;
        }).toList();
      }

      // Stage 3: priority.
      final ranked = _priorityEngine.rank(activeTracks);
      _lastRanked = ranked;

      // Update UI.
      _detections = ranked.map((o) => _trackedToDetected(o.track)).toList();
      _alerts = _obstacleAnalyzer.analyze(_detections);

      debugPrint('[Vision] ESP32 detected ${rawObjects.length} object(s)');

      // Stages 4 + 5: speech.
      await _scheduler.process(
        ranked: ranked,
        dropped: trackResult.dropped,
        settings: _settings,
      );
    } catch (e) {
      debugPrint('[Vision] ESP32 detection error: $e');
    } finally {
      _esp32Processing = false;
      _isProcessing = false;
      _throttledNotify();
    }
  }

  // ── Conversion helpers ─────────────────────────────────────────────────────

  /// Convert a [TrackedObject] into the [DetectedObject] model used by the UI.
  DetectedObject _trackedToDetected(TrackedObject t) {
    final box = t.boundingBox;
    final cx = box.center.dx;
    final area = t.area;

    final SpatialZone zone;
    if (cx < 0.33) {
      zone = SpatialZone.left;
    } else if (cx > 0.67) {
      zone = SpatialZone.right;
    } else {
      zone = SpatialZone.center;
    }

    final ProximityLevel proximity;
    if (area > 0.25) {
      proximity = ProximityLevel.immediate;
    } else if (area > 0.10) {
      proximity = ProximityLevel.close;
    } else if (area > 0.03) {
      proximity = ProximityLevel.approaching;
    } else {
      proximity = ProximityLevel.distant;
    }

    // Rough distance via pinhole model: d = (knownHeight * focalPx) / pixHeight
    const focalPx = 600.0;
    const knownHeights = <String, double>{
      'person': 1.7, 'car': 1.5, 'truck': 2.5, 'bus': 2.8,
      'bicycle': 1.1, 'motorcycle': 1.2, 'chair': 0.9, 'bench': 0.5,
      'dog': 0.5, 'cat': 0.35, 'fire hydrant': 0.6, 'stop sign': 0.75,
      'traffic light': 0.8, 'bottle': 0.25, 'cup': 0.12,
    };
    const defaultH = 0.5;
    final realH = knownHeights[t.label.toLowerCase()] ?? defaultH;
    final pixH = box.height * 480; // Assume 480 px frame height
    final distance = pixH > 0 ? (realH * focalPx) / pixH : null;

    return DetectedObject(
      label: t.label,
      confidence: t.confidence,
      boundingBox: box,
      zone: zone,
      proximity: proximity,
      isHazard: proximity == ProximityLevel.immediate ||
          proximity == ProximityLevel.close ||
          zone == SpatialZone.center,
      estimatedDistance: distance,
    );
  }

  // ── UI notification throttle ───────────────────────────────────────────────

  void _throttledNotify() {
    final now = DateTime.now();
    if (_lastUIUpdate != null &&
        now.difference(_lastUIUpdate!).inMilliseconds < _uiUpdateMinGapMs) {
      return;
    }
    _lastUIUpdate = now;
    notifyListeners();
  }

  // ── Voice / button event handlers ──────────────────────────────────────────

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

  void handleButtonEvent(String action) {
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
      case 'mode_changed':
        _statusMessage = 'Mode: ${_currentMode.displayName}';
        _speechService.speak(
          _currentMode.voiceFeedback,
          priority: SpeechPriority.high,
        );
      case 'object_detection_request':
        if (!_isVisionActive) startVision();
        _statusMessage = 'Analyzing objects in front of you';
        _speechService.speak(
          'What is in front of me?',
          priority: SpeechPriority.high,
        );
      case 'ocr_request':
        _handleOcrRequest();
      case 'navigation_request':
        _statusMessage = 'Navigation mode activated';
        _speechService.speak(
          'Navigation assistance activated',
          priority: SpeechPriority.high,
        );
      case 'button_1':
      case 'mode_button':
        // Toggle mode between object detection and OCR only
        if (_currentMode == AppMode.objectDetection) {
          _currentMode = AppMode.ocr;
          if (_isVisionActive) stopVision();
        } else {
          _currentMode = AppMode.objectDetection;
        }
        _statusMessage = 'Mode: ${_currentMode.displayName}';
        _speechService.speak(
          _currentMode.voiceFeedback,
          priority: SpeechPriority.high,
        );
      case 'button_2':
      case 'action_button':
        if (_currentMode == AppMode.objectDetection) {
          if (_isVisionActive) {
            stopVision();
            _speechService.speak('Detection paused', priority: SpeechPriority.high);
          } else {
            startVision();
            _speechService.speak('Detection resumed', priority: SpeechPriority.high);
          }
        } else if (_currentMode == AppMode.ocr) {
          _handleOcrRequest();
        }
    }
    notifyListeners();
  }

  void updateModeFromDevice(String modeName) {
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

  // ── Dispose ────────────────────────────────────────────────────────────────

  Future<void> _handleOcrRequest() async {
    _statusMessage = 'Capturing and reading text';
    _speechService.speak(
      'Capturing and reading text',
      priority: SpeechPriority.high,
    );
    notifyListeners();

    try {
      String text = '';
      if (_cameraService.isUsingPhoneCamera) {
        final controller = _cameraService.phoneController;
        if (controller != null && controller.value.isInitialized) {
          final xfile = await controller.takePicture();
          text = await _ocrService.recognizeText(xfile.path);
        }
      } else {
        final frame = _cameraService.latestFrame;
        if (frame != null) {
          final tempDir = await getTemporaryDirectory();
          final file = File('${tempDir.path}/temp_ocr.jpg');
          await file.writeAsBytes(frame);
          text = await _ocrService.recognizeText(file.path);
        }
      }

      _lastOcrText = text;
      notifyListeners();

      if (text.trim().isEmpty) {
        _speechService.speak('No text detected.', priority: SpeechPriority.high);
      } else {
        _speechService.speak('Detected text: $text', priority: SpeechPriority.high);
      }
    } catch (e) {
      _speechService.speak('Error reading text.', priority: SpeechPriority.high);
      debugPrint('OCR Request Error: $e');
    }
  }

  @override
  void dispose() {
    _connectionSub.cancel();
    _frameSub.cancel();
    _buttonEventSub.cancel();
    _ocrService.dispose();
    super.dispose();
  }
}
