import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../core/theme/app_theme.dart';
import '../models/app_mode.dart';
import '../models/detected_object.dart';
import '../providers/vision_provider.dart';
import '../widgets/detection_overlay.dart';
import '../widgets/obstacle_alert_card.dart';

class VisionScreen extends StatefulWidget {
  const VisionScreen({super.key});

  @override
  State<VisionScreen> createState() => _VisionScreenState();
}

class _VisionScreenState extends State<VisionScreen> {
  bool _cameraPermissionDenied = false;
  bool _cameraPermissionPermanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startWithPermission());
  }

  @override
  void dispose() {
    context.read<VisionProvider>().stopVision();
    super.dispose();
  }

  Future<void> _startWithPermission() async {
    final hasPermission = await _requestCameraPermission();
    if (!mounted || !hasPermission) return;

    final vision = context.read<VisionProvider>();
    if (!vision.connection.isConnected) {
      await vision.connectCamera();
    }
    if (!mounted) return;
    await vision.startVision();
  }

  Future<bool> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    final isGranted = status.isGranted || status.isLimited;

    if (!mounted) return false;
    setState(() {
      _cameraPermissionDenied = !isGranted;
      _cameraPermissionPermanentlyDenied = status.isPermanentlyDenied;
    });

    return isGranted;
  }

  Future<void> _retryCameraPermission() async {
    if (_cameraPermissionPermanentlyDenied) {
      await openAppSettings();
      return;
    }
    await _startWithPermission();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VisionProvider>(
      builder: (context, vision, _) {
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Live Vision'),
                Text(
                  'Mode: ${vision.currentMode.displayName}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white70,
                      ),
                ),
              ],
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
              tooltip: 'Go back',
            ),
            actions: [
              _ModelStatusChip(isModelReady: vision.isModelReady),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.swap_horiz),
                onPressed: () => vision.handleButtonEvent('button_1'),
                tooltip: 'Switch Mode',
                color: AppTheme.accent,
              ),
              IconButton(
                icon: Icon(
                  vision.isVisionActive ? Icons.pause : Icons.play_arrow,
                ),
                onPressed: () {
                  if (vision.isVisionActive) {
                    vision.stopVision();
                  } else {
                    _startWithPermission();
                  }
                },
                tooltip: vision.isVisionActive ? 'Pause' : 'Resume',
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: vision.describeScene,
                tooltip: 'Describe scene',
              ),
            ],
          ),
          body: Column(
            children: [
              // ── Camera feed (3/5 of screen) ─────────────────────────────
              Expanded(
                flex: 3,
                child: _cameraPermissionDenied
                    ? _CameraPermissionPrompt(
                        permanentlyDenied:
                            _cameraPermissionPermanentlyDenied,
                        onRetry: _retryCameraPermission,
                      )
                    : _CameraView(vision: vision),
              ),

              // ── Detection info panel (2/5 of screen) ───────────────────
              Expanded(
                flex: 2,
                child: _DetectionPanel(vision: vision),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Model-ready chip ──────────────────────────────────────────────────────────

class _ModelStatusChip extends StatelessWidget {
  const _ModelStatusChip({required this.isModelReady});
  final bool isModelReady;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isModelReady
              ? AppTheme.accent.withValues(alpha: 0.18)
              : Colors.orange.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isModelReady ? AppTheme.accent : Colors.orange,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isModelReady ? Icons.memory : Icons.hourglass_empty,
              size: 12,
              color: isModelReady ? AppTheme.accent : Colors.orange,
            ),
            const SizedBox(width: 4),
            Text(
              isModelReady ? 'AI Ready' : 'Loading…',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isModelReady ? AppTheme.accent : Colors.orange,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Camera permission prompt ──────────────────────────────────────────────────

class _CameraPermissionPrompt extends StatelessWidget {
  const _CameraPermissionPrompt({
    required this.permanentlyDenied,
    required this.onRetry,
  });

  final bool permanentlyDenied;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.black,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.no_photography_outlined,
            color: AppTheme.warning,
            size: 56,
          ),
          const SizedBox(height: 16),
          const Text(
            'Camera permission required',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            permanentlyDenied
                ? 'Enable camera access in app settings to use live vision.'
                : 'Allow camera access to start live vision.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: Icon(
              permanentlyDenied
                  ? Icons.settings
                  : Icons.camera_alt_outlined,
            ),
            label: Text(
              permanentlyDenied ? 'Open settings' : 'Allow camera',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              minimumSize: const Size(0, 48),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Camera view ───────────────────────────────────────────────────────────────

/// Chooses the right camera display strategy:
///
/// **Phone camera** → [YOLOView] widget (native live-stream detection at the
/// platform level, runs on GPU/NPU, every frame is processed).
/// Our custom [DetectionOverlay] is drawn on top using results from
/// [VisionProvider.onLiveDetections].
///
/// **ESP32-CAM** → [Image.memory] decoded from JPEG bytes polled over HTTP.
/// Detection is done inside [VisionProvider._onFrame] using YOLO.predict().
class _CameraView extends StatelessWidget {
  const _CameraView({required this.vision});
  final VisionProvider vision;

  @override
  Widget build(BuildContext context) {
    if (!vision.connection.isConnected) {
      return _placeholder(
        icon: Icons.wifi_off,
        label: 'Camera not connected',
      );
    }

    if (vision.isUsingPhoneCamera) {
      return _PhoneCameraView(vision: vision);
    } else {
      return _Esp32CameraView(vision: vision);
    }
  }

  Widget _placeholder({required IconData icon, required String label}) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white38, size: 48),
            const SizedBox(height: 12),
            Text(label, style: const TextStyle(color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}

// ── Phone camera: YOLOView live stream ────────────────────────────────────────

/// Uses the native [YOLOView] widget which runs the full camera-stream +
/// YOLO detection pipeline at the platform level (GPU-accelerated).
///
/// Detection results arrive in [onResult] → forwarded to
/// [VisionProvider.onLiveDetections] → speech / haptic feedback.
///
/// Our custom [DetectionOverlay] is stacked on top using the converted
/// [DetectedObject] list stored in [VisionProvider.detections].
class _PhoneCameraView extends StatelessWidget {
  const _PhoneCameraView({required this.vision});
  final VisionProvider vision;

  @override
  Widget build(BuildContext context) {
    final isOcrMode = vision.currentMode == AppMode.ocr;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (isOcrMode) ...[
          // ── OCR Mode ────────────────────────────────────────────────────
          // Prefer the CameraController preview when available (used for
          // direct still-capture for OCR). If the controller isn't ready
          // (some devices or native widgets may own the camera), fall back
          // to a YOLOView so the user still sees the live camera feed.
          if (vision.phoneController != null &&
              vision.phoneController!.value.isInitialized)
            CameraPreview(vision.phoneController!)
          else if (vision.isUsingPhoneCamera)
            // Phone camera selected but controller isn't ready yet — show
            // a stable loading indicator instead of instantiating another
            // native camera view (which can cause plugin observer errors).
            const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          else
            // ESP32 mode: show the latest JPEG frame if available.
            (vision.currentFrame != null)
                ? Image.memory(vision.currentFrame!, fit: BoxFit.cover, gaplessPlayback: true)
                : const Center(child: CircularProgressIndicator(color: AppTheme.accent)),

          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'OCR Mode: Ready to read text',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
          ),

          // ── OCR result overlay ────────────────────────────────────
          if (vision.ocrText.isNotEmpty)
            Positioned(
              bottom: 72,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                ),
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: Text(
                    vision.ocrText,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            ),
        ] else ...[
          // ── Native live-stream detection widget ───────────────────────────
          YOLOView(
            // Use the bundled tflite model or fall back to built-in yolov8n.
            modelPath: 'assets/model.tflite',
            task: YOLOTask.detect,
            confidenceThreshold: vision.settings.detectionConfidence,
            iouThreshold: 0.45,
            useGpu: true,
            onResult: (results) {
              // Forward to provider — converts YOLOResult → DetectedObject
              // and triggers speech/haptic feedback for hazards.
              vision.onLiveDetections(results);
            },
          ),

          // ── Custom bounding-box overlay ───────────────────────────────────
          // Drawn on top of the native camera preview using the DetectedObject
          // list that onLiveDetections() just updated.
          if (vision.detections.isNotEmpty)
            DetectionOverlay(
              detections: vision.detections,
              imageSize: Size.zero,
            ),

          // ── "Scanning…" hint when no objects found ────────────────────────
          if (vision.detections.isEmpty && vision.isVisionActive)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Scanning for objects…',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            ),

          // ── "Paused" overlay ──────────────────────────────────────────────
          if (!vision.isVisionActive)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Text(
                  'Vision paused',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

// ── ESP32 camera: JPEG over HTTP ──────────────────────────────────────────────

class _Esp32CameraView extends StatelessWidget {
  const _Esp32CameraView({required this.vision});
  final VisionProvider vision;

  @override
  Widget build(BuildContext context) {
    final frame = vision.currentFrame;
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── JPEG frame from ESP32 ─────────────────────────────────────
          if (frame != null)
            Image.memory(frame, fit: BoxFit.cover, gaplessPlayback: true)
          else
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppTheme.accent),
                  const SizedBox(height: 12),
                  Text(
                    vision.isVisionActive
                        ? 'Receiving frames…'
                        : 'Vision paused',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),

          // ── Detection overlay ─────────────────────────────────────────
          if (vision.detections.isNotEmpty)
            DetectionOverlay(
              detections: vision.detections,
              imageSize: Size.zero,
            ),

          // ── Processing indicator ──────────────────────────────────────
          if (vision.isProcessing)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.accent,
                      ),
                    ),
                    SizedBox(width: 6),
                    Text('Analyzing', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Detection info panel ──────────────────────────────────────────────────────

class _DetectionPanel extends StatelessWidget {
  const _DetectionPanel({required this.vision});
  final VisionProvider vision;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.cardDark, AppTheme.surfaceDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Status row ────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: vision.isVisionActive
                      ? AppTheme.accent
                      : AppTheme.warning,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                vision.isVisionActive ? 'Live scanning…' : 'Paused',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              if (vision.isProcessing)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Object count + nearest ────────────────────────────────────
          Row(
            children: [
              Text(
                '${vision.detections.length} object'
                '${vision.detections.length == 1 ? '' : 's'} detected',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              if (vision.detections.isNotEmpty &&
                  vision.detections.first.estimatedDistance != null)
                Text(
                  'Nearest: ${vision.detections.first.distanceDescription}',
                  style: TextStyle(
                    color: AppTheme.accent.withValues(alpha: 0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Alert list ────────────────────────────────────────────────
          Expanded(
            child: ListView(
              children:
                  vision.alerts.map((a) => ObstacleAlertCard(alert: a)).toList(),
            ),
          ),
          const SizedBox(height: 8),

          // ── Action buttons ────────────────────────────────────────────
          Row(
            children: [
              if (vision.currentMode == AppMode.objectDetection) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: vision.scanObstacles,
                    icon: const Icon(Icons.warning_amber),
                    label: const Text('Scan'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.warning,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(0, 52),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              if (vision.currentMode == AppMode.ocr) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => vision.handleButtonEvent('button_2'),
                    icon: const Icon(Icons.document_scanner),
                    label: const Text('Read Text'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 52),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => vision.handleButtonEvent('button_1'),
                  icon: const Icon(Icons.swap_horiz),
                  label: Text(vision.currentMode == AppMode.objectDetection ? 'To OCR' : 'To Vision'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 52),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
