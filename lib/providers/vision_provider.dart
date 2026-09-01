import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';
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
import '../services/ocr_service.dart';
import '../services/priority_engine.dart';
import '../services/scene_understanding.dart';
import '../services/speech_scheduler.dart';
import '../services/speech_service.dart';
import '../services/voice_command_service.dart';

/// What the OCR pipeline is currently doing. The UI shows this directly, so a
/// blind user's sighted helper can see why nothing is being read out.
enum OcrStage { idle, capturing, recognising, done, failed }

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
    _scheduler = SpeechScheduler(speechService: _speechService);

    _connectionSub = _cameraService.connectionStream.listen((info) {
      _connection = info;
      notifyListeners();
    });
    _frameSub = _cameraService.frameStream.listen(_onEsp32Frame);
    _buttonEventSub =
        _cameraService.buttonEventStream.listen(_onDeviceButtonEvent);
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

  // ── Pipeline stages ────────────────────────────────────────────────────────

  /// Stage 1 is YOLO — inside [YOLOView] (phone) or [ObjectDetectionService]
  /// (ESP32).

  /// Stage 2: stable IDs across frames.
  final ObjectTracker _tracker = ObjectTracker();

  /// Stage 3: score and sort by danger.
  final PriorityEngine _priorityEngine = PriorityEngine();

  /// Stage 4: ranked objects into a spoken phrase.
  final SceneUnderstanding _sceneUnderstanding = SceneUnderstanding();

  /// Stage 5: decides whether the user actually hears it.
  late final SpeechScheduler _scheduler;

  // ── Subscriptions ──────────────────────────────────────────────────────────

  late StreamSubscription<CameraConnectionInfo> _connectionSub;
  late StreamSubscription<Uint8List> _frameSub;
  late StreamSubscription<ButtonEvent> _buttonEventSub;

  // ── UI-observable state ────────────────────────────────────────────────────

  AppSettings _settings = const AppSettings();
  CameraConnectionInfo _connection = const CameraConnectionInfo();
  List<DetectedObject> _detections = [];
  List<ObstacleAlert> _alerts = [];
  Uint8List? _currentFrame; // ESP32 only
  bool _isVisionActive = false;
  bool _isProcessing = false; // ESP32 only
  String _statusMessage = 'Ready';
  AppMode _currentMode = AppMode.objectDetection;

  /// Set when YOLOView fails to load its model, so the vision screen can say
  /// what went wrong instead of showing an empty camera feed forever.
  String? _detectionError;

  // OCR state.
  String _ocrText = '';
  OcrStage _ocrStage = OcrStage.idle;
  String _ocrMessage = '';

  /// Cached ranked list for describeScene() and the UI.
  List<ScoredObject> _lastRanked = [];

  /// Throttle for notifyListeners() to avoid 30–60 rebuilds/second.
  DateTime? _lastUIUpdate;
  static const int _uiUpdateMinGapMs = 100; // ≈10 rebuilds/s

  // ── Getters ────────────────────────────────────────────────────────────────

  AppSettings get settings => _settings;
  CameraConnectionInfo get connection => _connection;
  List<DetectedObject> get detections => _detections;
  List<ObstacleAlert> get alerts => _alerts;
  Uint8List? get currentFrame => _currentFrame;
  bool get isVisionActive => _isVisionActive;
  bool get isProcessing => _isProcessing;
  bool get isModelReady => isUsingPhoneCamera || _detectionService.isReady;
  String get statusMessage => _statusMessage;
  String? get detectionError => _detectionError;
  bool get isVoiceListening => _voiceCommandService.isListening;
  AppMode get currentMode => _currentMode;

  /// Most recent OCR result, empty when there is none.
  String get ocrText => _ocrText;
  OcrStage get ocrStage => _ocrStage;
  String get ocrMessage => _ocrMessage;
  bool get isReadingText =>
      _ocrStage == OcrStage.capturing || _ocrStage == OcrStage.recognising;

  /// The still-capture controller, non-null only in OCR mode on the phone.
  CameraController? get phoneController => _cameraService.phoneController;

  bool get isUsingPhoneCamera => _cameraService.isUsingPhoneCamera;

  /// True when the native [YOLOView] should be mounted. It owns the camera, so
  /// nothing else may hold it while this is true.
  bool get shouldMountYoloView =>
      isUsingPhoneCamera && _currentMode == AppMode.objectDetection;

  /// Available TTS voices, for the settings screen.
  List<SpeechVoice> get availableVoices => _speechService.availableVoices;

  /// Speaks a sample line in [voice] so the user can choose one by ear.
  Future<void> previewVoice(SpeechVoice voice) =>
      _speechService.previewVoice(voice);

  // ── Settings ───────────────────────────────────────────────────────────────

  void updateSettings(AppSettings settings) {
    _settings = settings;
    _cameraService.updateSettings(settings);
    unawaited(_speechService.updateSettings(settings));
    notifyListeners();
  }

  /// Warms up the ESP32 inference path at app start.
  ///
  /// Skipped entirely when the phone camera is selected: [YOLOView] loads and
  /// owns its own model natively, and loading a second copy here just burns
  /// memory on a device that is already running a camera and a neural net.
  Future<void> initializeDetection() async {
    if (isUsingPhoneCamera) return;
    if (_detectionService.isReady) return;
    await _detectionService.initialize();
    notifyListeners();
  }

  // ── Camera connection ──────────────────────────────────────────────────────

  Future<void> connectCamera() async {
    _statusMessage = 'Connecting...';
    notifyListeners();

    await _cameraService.connect();
    if (_cameraService.connection.isConnected) {
      _statusMessage = 'Camera connected';
      await _confirmWithHaptic();
    } else {
      _statusMessage = _cameraService.connection.message;
      await _speechService.speak(
        'Camera not connected',
        priority: SpeechPriority.high,
      );
    }
    notifyListeners();
  }

  Future<void> disconnectCamera() async {
    await stopVision();
    await _cameraService.closeStillCamera();
    await _cameraService.disconnect();
    _currentFrame = null;
    _detections = [];
    _alerts = [];
    _statusMessage = 'Disconnected';
    notifyListeners();
  }

  Future<DeviceStatus?> fetchDeviceStatus() => _cameraService.fetchStatus();

  Future<bool> provisionDeviceWifi(String ssid, String password) =>
      _cameraService.provisionDeviceWifi(ssid, password);

  Future<void> testConnection(String ip, String path) async {
    _statusMessage = 'Testing connection...';
    notifyListeners();

    final success = await _cameraService.testConnection(ip, path);
    _statusMessage = success ? 'Connection successful' : 'Connection failed';
    await _speechService.speak(
      success ? 'Connected' : 'Could not connect',
      priority: SpeechPriority.high,
    );
    if (success) await _confirmWithHaptic();
    notifyListeners();
  }

  // ── Mode switching ─────────────────────────────────────────────────────────

  /// Switches between the two modes and hands the camera over.
  ///
  /// On the phone, object detection is served by the native [YOLOView] and OCR
  /// by a [CameraController]; only one may hold the sensor. The order here
  /// matters: notify first so the widget tree unmounts the outgoing consumer,
  /// wait for that frame to be rendered, and only then open the incoming one.
  /// Opening before the teardown lands is exactly what produced the black
  /// preview and the "camera in use" errors.
  Future<void> setMode(AppMode mode) async {
    if (mode == _currentMode) return;

    _currentMode = mode;
    _clearOcr();
    _statusMessage = mode.displayName;
    notifyListeners();

    await _speechService.speak(
      mode.voiceFeedback,
      priority: SpeechPriority.high,
    );

    if (isUsingPhoneCamera) {
      if (mode == AppMode.ocr) {
        // YOLOView must let go of the camera before the controller can take it.
        if (_isVisionActive) await stopVision();
        await _waitForWidgetTeardown();
        final opened = await _cameraService.openStillCamera();
        if (!opened) {
          _ocrStage = OcrStage.failed;
          _ocrMessage = 'Could not open the camera for reading.';
          await _speechService.speak(
            'Camera unavailable',
            priority: SpeechPriority.high,
          );
        }
      } else {
        await _cameraService.closeStillCamera();
        await _waitForWidgetTeardown();
      }
    }

    // Best effort: if the device is unreachable the next /events response
    // resynchronises us anyway.
    unawaited(_cameraService.setDeviceMode(mode));
    notifyListeners();
  }

  /// There are only two modes, so the mode button is a toggle.
  Future<void> toggleMode() => setMode(_currentMode.toggled);

  /// Opens whichever camera the current mode needs.
  ///
  /// Called when the vision screen appears. [setMode] handles the handover
  /// when the mode *changes*, but entering the screen already in OCR mode is
  /// not a change, so without this the preview would sit on "Preparing
  /// camera…" indefinitely.
  Future<void> prepareCameraForMode() async {
    if (!isUsingPhoneCamera) return;

    if (_currentMode == AppMode.ocr) {
      if (phoneController != null) return;
      final opened = await _cameraService.openStillCamera();
      if (!opened) {
        _ocrStage = OcrStage.failed;
        _ocrMessage = 'Could not open the camera for reading.';
      }
      notifyListeners();
    } else {
      await _cameraService.closeStillCamera();
    }
  }

  /// Hands the camera back when the vision screen is dismissed, so the sensor
  /// is not held open behind an unrelated screen.
  Future<void> releaseCamera() async {
    await _cameraService.closeStillCamera();
  }

  /// Gives the framework one frame to actually dispose the outgoing camera
  /// widget, plus a short grace period for the platform view to release the
  /// hardware. Without the second part the handover races on slower Androids.
  Future<void> _waitForWidgetTeardown() async {
    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  // ── Vision lifecycle ───────────────────────────────────────────────────────

  Future<void> startVision() async {
    if (_currentMode != AppMode.objectDetection) {
      await setMode(AppMode.objectDetection);
    }

    if (!_connection.isConnected) {
      await connectCamera();
      if (!_connection.isConnected) return;
    }

    // The phone path loads its model inside YOLOView; only the ESP32 path needs
    // the Dart-side model.
    if (!isUsingPhoneCamera && !_detectionService.isReady) {
      _statusMessage = 'Loading detection model...';
      notifyListeners();
      await _detectionService.initialize();
      if (!_detectionService.isReady) {
        _detectionError = _detectionService.lastError ?? 'Model failed to load';
        _statusMessage = 'Detection model failed to load';
        notifyListeners();
        await _speechService.speak(
          'Detection model failed to load',
          priority: SpeechPriority.high,
        );
        return;
      }
    }

    _isVisionActive = true;
    _detectionError = null;
    _statusMessage = 'Vision active';
    _tracker.reset();
    _scheduler.reset();

    await _speechService.speak('Vision on', priority: SpeechPriority.high);
    notifyListeners();
  }

  Future<void> stopVision() async {
    if (!_isVisionActive) return;
    _isVisionActive = false;
    _statusMessage = 'Vision paused';
    _detections = [];
    _alerts = [];
    _tracker.reset();
    _scheduler.reset();
    await _speechService.stop();
    notifyListeners();
  }

  /// Reported by [YOLOView] when its model cannot be loaded.
  void reportDetectionError(Object error) {
    _detectionError = error.toString();
    _statusMessage = 'Detection model failed to load';
    notifyListeners();
    unawaited(
      _speechService.speak(
        'Detection model failed to load',
        priority: SpeechPriority.high,
      ),
    );
  }

  void reportDetectionReady() {
    if (_detectionError == null) return;
    _detectionError = null;
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
        'Path is clear.',
        priority: SpeechPriority.high,
      );
      return;
    }

    final hazards = _detections.where((d) => d.isHazard).toList();
    if (hazards.isEmpty) {
      await _speechService.speak(
        '${_detections.length} objects, none in your way.',
        priority: SpeechPriority.high,
      );
      return;
    }

    final text = hazards.map((h) => h.announcement).take(2).join('. ');
    await _speechService.speak(text, priority: SpeechPriority.high);
  }

  Future<void> repeatLast() => _speechService.repeatLast();

  Future<void> toggleVoiceListening() async {
    if (!_settings.enableVoiceCommands) return;

    if (_voiceCommandService.isListening) {
      await _voiceCommandService.stopListening();
    } else {
      final available = await _voiceCommandService.initialize();
      if (available) await _voiceCommandService.startListening();
    }
    notifyListeners();
  }

  // ── OCR ────────────────────────────────────────────────────────────────────

  /// Longest text handed to the TTS engine in one call. Android's engine
  /// silently truncates past roughly this, so the cut is made here where the
  /// user can be told it happened.
  static const int _maxSpokenChars = 3500;

  /// Captures a frame and reads whatever text is in it.
  ///
  /// The result is both spoken and left on screen — the screen copy is what a
  /// sighted helper reads, and what the user can have repeated.
  Future<void> readText() async {
    if (isReadingText) return;

    if (_currentMode != AppMode.ocr) {
      await setMode(AppMode.ocr);
    }

    _ocrText = '';
    _ocrMessage = '';
    _ocrStage = OcrStage.capturing;
    _statusMessage = 'Capturing…';
    notifyListeners();

    await _speechService.speak('Reading', priority: SpeechPriority.high);

    String? imagePath;
    try {
      imagePath = await _captureForOcr();
      if (imagePath == null) {
        _failOcr('No image to read. Check the camera.');
        return;
      }

      _ocrStage = OcrStage.recognising;
      _statusMessage = 'Reading text…';
      notifyListeners();

      final text = await _ocrService.recognizeText(imagePath);
      final cleaned = _tidyOcrText(text);

      if (cleaned.isEmpty) {
        _ocrStage = OcrStage.done;
        _ocrText = '';
        _ocrMessage = 'No text found. Move closer and hold steady.';
        _statusMessage = 'No text found';
        notifyListeners();
        await _speechService.speak(
          'No text found.',
          priority: SpeechPriority.high,
        );
        return;
      }

      _ocrText = cleaned;
      _ocrStage = OcrStage.done;
      _statusMessage = 'Text found';
      _ocrMessage = '';
      notifyListeners();

      await _confirmWithHaptic();

      final spoken = cleaned.length > _maxSpokenChars
          ? '${cleaned.substring(0, _maxSpokenChars)}… Text continues on screen.'
          : cleaned;
      await _speechService.speak(spoken, priority: SpeechPriority.high);
    } catch (e) {
      debugPrint('[OCR] failed: $e');
      _failOcr('Could not read the text.');
    } finally {
      // The capture is a temp file we created; do not leave a photo of the
      // user's surroundings on disk after we are done with it.
      if (imagePath != null) unawaited(_deleteTemp(imagePath));
    }
  }

  /// Reads the on-screen result again without taking a new photo.
  Future<void> repeatText() async {
    if (_ocrText.isEmpty) {
      await _speechService.speak(
        'Nothing to repeat.',
        priority: SpeechPriority.high,
      );
      return;
    }
    await _speechService.speak(_ocrText, priority: SpeechPriority.high);
  }

  /// Stops the current reading and clears the result.
  Future<void> clearText() async {
    await _speechService.stop();
    _clearOcr();
    notifyListeners();
  }

  Future<String?> _captureForOcr() async {
    if (isUsingPhoneCamera) {
      // Make sure the controller is up — the user may have jumped straight to
      // the read button without the mode switch having finished.
      if (phoneController == null) {
        await _cameraService.openStillCamera();
      }
      return _cameraService.captureStill();
    }

    final frame = _cameraService.latestFrame;
    if (frame == null || frame.isEmpty) return null;

    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/ocr_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(frame, flush: true);
    return file.path;
  }

  Future<void> _deleteTemp(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A leftover temp file is not worth surfacing to the user.
    }
  }

  /// ML Kit returns one line per detected text block. Joining them with spaces
  /// keeps the spoken version from pausing awkwardly at every line wrap, while
  /// paragraph breaks are preserved for the on-screen copy.
  String _tidyOcrText(String raw) {
    return raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n')
        .trim();
  }

  void _failOcr(String message) {
    _ocrStage = OcrStage.failed;
    _ocrMessage = message;
    _statusMessage = message;
    notifyListeners();
    unawaited(_speechService.speak(message, priority: SpeechPriority.high));
  }

  void _clearOcr() {
    _ocrText = '';
    _ocrMessage = '';
    _ocrStage = OcrStage.idle;
  }

  // ── Pipeline: phone camera (YOLOView live stream) ──────────────────────────
  //
  //   YOLOView.onResult  →  filter  →  ObjectTracker  →  PriorityEngine
  //     →  SceneUnderstanding  →  SpeechScheduler  →  SpeechService

  /// Called by [YOLOView.onResult] on every processed frame.
  void onLiveDetections(List<YOLOResult> results) {
    if (!_isVisionActive) return;
    if (_currentMode != AppMode.objectDetection) return;

    final detections = results
        .where((r) {
          if (r.confidence < _settings.detectionConfidence) return false;
          final label = r.className.toLowerCase();
          if (!AppConstants.allowedLabels.contains(label)) return false;
          final area = r.normalizedBox.width * r.normalizedBox.height;
          if (area < AppConstants.minDetectionArea) return false;
          return true;
        })
        .map((r) => (
              label: r.className,
              box: r.normalizedBox,
              confidence: r.confidence,
            ))
        .toList();

    _runPipeline(detections);
  }

  // ── Pipeline: ESP32-CAM (JPEG over HTTP) ───────────────────────────────────

  bool _esp32Processing = false;
  DateTime? _lastEsp32Detection;

  Future<void> _onEsp32Frame(Uint8List frame) async {
    if (isUsingPhoneCamera) return;

    _currentFrame = frame;
    _throttledNotify();

    if (!_isVisionActive || _esp32Processing) return;
    if (_currentMode != AppMode.objectDetection) return;

    final now = DateTime.now();
    final minGap = _settings.detectionIntervalMs.clamp(200, 5000);
    if (_lastEsp32Detection != null &&
        now.difference(_lastEsp32Detection!).inMilliseconds < minGap) {
      return;
    }

    _esp32Processing = true;
    _isProcessing = true;
    _throttledNotify();

    try {
      final rawObjects = await _detectionService.detectObjects(
        frame,
        minConfidence: _settings.detectionConfidence,
        announceAllObjects: _settings.announceAllObjects,
        imageWidth: AppConstants.frameWidth,
        imageHeight: AppConstants.frameHeight,
      );

      _lastEsp32Detection = DateTime.now();

      _runPipeline(
        rawObjects
            .map((o) => (
                  label: o.label,
                  box: o.boundingBox,
                  confidence: o.confidence,
                ))
            .toList(),
        awaitSpeech: true,
      );
    } catch (e) {
      debugPrint('[Vision] ESP32 detection error: $e');
    } finally {
      _esp32Processing = false;
      _isProcessing = false;
      _throttledNotify();
    }
  }

  // ── Shared pipeline stages 2–5 ─────────────────────────────────────────────

  /// Both camera paths converge here so tracking, ranking and speech gating
  /// behave identically whichever camera the frame came from. They used to be
  /// duplicated, and had already drifted apart.
  void _runPipeline(List<Detection> detections, {bool awaitSpeech = false}) {
    final trackResult = _tracker.update(detections);

    var activeTracks = trackResult.active;
    if (_settings.announceOnlyCenter) {
      activeTracks = activeTracks.where((t) {
        final cx = t.boundingBox.center.dx;
        return cx > 0.25 && cx < 0.75;
      }).toList();
    }

    final ranked = _priorityEngine.rank(activeTracks);
    _lastRanked = ranked;

    _detections = ranked.map((o) => _trackedToDetected(o.track)).toList();
    _alerts = _obstacleAnalyzer.analyze(_detections);
    _throttledNotify();

    unawaited(
      _scheduler.process(
        ranked: ranked,
        dropped: trackResult.dropped,
        settings: _settings,
      ),
    );
  }

  // Detections deliberately do NOT vibrate.
  //
  // A head-mounted camera sees dozens of transient objects a minute, and any
  // per-detection buzz — however well rate-limited — becomes a constant hum
  // that the wearer stops being able to distinguish from anything else. Worse,
  // it competes for attention with the speech, which is the channel that
  // actually carries information. Haptics are now reserved for confirming
  // something the user themselves did, and are off by default.

  /// A single short tap confirming an action the user deliberately took.
  /// Silent unless the user has switched haptics on.
  Future<void> _confirmWithHaptic() async {
    if (!_settings.enableHaptics) return;
    await _hapticService.success();
  }

  // ── Conversion helpers ─────────────────────────────────────────────────────

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
    final pixH = box.height * AppConstants.frameHeight;
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

  void _throttledNotify() {
    final now = DateTime.now();
    if (_lastUIUpdate != null &&
        now.difference(_lastUIUpdate!).inMilliseconds < _uiUpdateMinGapMs) {
      return;
    }
    _lastUIUpdate = now;
    notifyListeners();
  }

  // ── Voice / button handlers ────────────────────────────────────────────────

  void _handleVoiceCommand(String command) {
    if (command.contains('read') || command.contains('text')) {
      unawaited(readText());
    } else if (command.contains('start')) {
      unawaited(startVision());
    } else if (command.contains('stop') || command.contains('pause')) {
      unawaited(stopVision());
    } else if (command.contains('describe')) {
      unawaited(describeScene());
    } else if (command.contains('scan') || command.contains('obstacle')) {
      unawaited(scanObstacles());
    } else if (command.contains('repeat')) {
      unawaited(repeatLast());
    } else if (command.contains('mode') || command.contains('switch')) {
      unawaited(toggleMode());
    } else if (command.contains('settings')) {
      _statusMessage = 'navigate:settings';
    } else if (command.contains('help')) {
      _statusMessage = 'navigate:help';
    }
    notifyListeners();
  }

  /// A button press reported by the ESP32.
  ///
  /// Every event carries the mode the device is in, which is how the phone and
  /// the hardware stay in agreement.
  ///
  /// `mode_changed` is handled separately and deliberately: the firmware
  /// switches its own mode *first* and then reports the mode it switched **to**.
  /// Adopting that mode and then also running the generic mode-button handler
  /// would toggle a second time, leaving the app exactly one step out of phase
  /// with the glasses — the mode button would appear to do nothing, or the
  /// wrong thing.
  void _onDeviceButtonEvent(ButtonEvent event) {
    if (event.action == ButtonAction.modeChanged) {
      _adoptDeviceMode(event.mode);
      return;
    }

    if (event.mode.isNotEmpty) {
      final reported = event.parsedMode;
      if (reported == null) {
        // A board still running three-mode firmware has landed in
        // "navigation", which this app no longer has. Resync instead of
        // drifting, then drop the event — its action is meaningless here.
        _adoptDeviceMode(event.mode);
        return;
      }
      if (reported != _currentMode) unawaited(setMode(reported));
    }

    handleButtonEvent(event.action);
  }

  /// Brings the app into whatever mode the device says it is in.
  void _adoptDeviceMode(String wireName) {
    final parsed = appModeFromWireName(wireName);
    if (parsed != null) {
      unawaited(setMode(parsed));
      return;
    }

    // Unknown mode name: older firmware cycling through a third mode. Put both
    // sides back into object detection rather than leaving them disagreeing.
    debugPrint('[Vision] device reported unknown mode "$wireName"; resyncing');
    unawaited(setMode(AppMode.objectDetection));
    unawaited(_cameraService.setDeviceMode(AppMode.objectDetection));
  }

  /// Handles a button action by name. Shared by the hardware buttons and the
  /// on-screen ones that mirror them.
  void handleButtonEvent(String action) {
    switch (action) {
      // Only the on-screen mode control reaches this. Device-initiated mode
      // changes are handled in _onDeviceButtonEvent, which adopts rather than
      // toggles.
      case ButtonAction.modeButton:
      case 'mode_button':
        unawaited(toggleMode());

      case ButtonAction.actionButton:
      case 'action_button':
        // The action button does whatever the current mode is for.
        if (_currentMode == AppMode.ocr) {
          unawaited(readText());
        } else if (_isVisionActive) {
          unawaited(stopVision());
        } else {
          unawaited(startVision());
        }

      case ButtonAction.modeAnnounce:
        unawaited(
          _speechService.speak(
            _currentMode.voiceFeedback,
            priority: SpeechPriority.high,
          ),
        );

      case ButtonAction.toggleVision:
        if (_isVisionActive) {
          unawaited(stopVision());
        } else {
          unawaited(startVision());
        }

      case ButtonAction.ocrRequest:
        unawaited(readText());

      case ButtonAction.objectDetectionRequest:
        unawaited(setMode(AppMode.objectDetection));
        if (!_isVisionActive) unawaited(startVision());

      // v2 firmware.
      case ButtonAction.scanObstacles:
        unawaited(scanObstacles());
      case ButtonAction.describeScene:
        unawaited(describeScene());
    }
    notifyListeners();
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _connectionSub.cancel();
    _frameSub.cancel();
    _buttonEventSub.cancel();
    _ocrService.dispose();
    unawaited(_speechService.dispose());
    super.dispose();
  }
}
