import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/constants.dart';
import '../core/layout.dart';
import '../core/theme/app_theme.dart';
import '../models/app_mode.dart';
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

  /// Captured in initState. Reading the provider off `context` inside
  /// dispose() throws, because the element is already unmounted by then.
  late final VisionProvider _vision;

  @override
  void initState() {
    super.initState();
    _vision = context.read<VisionProvider>();
    // Navigation assistance is useless if the screen sleeps mid-walk.
    WakelockPlus.enable();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startWithPermission());
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _vision.stopVision();
    // Do not leave the OCR still-capture camera holding the sensor once this
    // screen is gone.
    _vision.releaseCamera();
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

    // Only auto-start the detector. Landing in OCR mode brings the preview up
    // but leaves the reading itself until the user asks for it.
    if (vision.currentMode == AppMode.objectDetection) {
      await vision.startVision();
    } else {
      await vision.prepareCameraForMode();
    }
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
        final isOcr = vision.currentMode == AppMode.ocr;

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Live Vision'),
                Text(
                  vision.currentMode.displayName,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: context.appColors.muted,
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
              if (!isOcr) ...[
                _ModelStatusChip(isModelReady: vision.isModelReady),
                const SizedBox(width: 4),
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
                  icon: const Icon(Icons.record_voice_over),
                  onPressed: vision.describeScene,
                  tooltip: 'Describe scene',
                ),
              ],
              if (isOcr && vision.ocrText.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.replay),
                  onPressed: vision.repeatText,
                  tooltip: 'Read again',
                ),
            ],
          ),
          body: SafeArea(
            child: _VisionLayout(
              camera: _cameraPermissionDenied
                  ? _CameraPermissionPrompt(
                      permanentlyDenied: _cameraPermissionPermanentlyDenied,
                      onRetry: _retryCameraPermission,
                    )
                  : _CameraStage(vision: vision),
              panel: isOcr
                  ? _OcrPanel(vision: vision)
                  : _DetectionPanel(vision: vision),
            ),
          ),
        );
      },
    );
  }
}

// ── Responsive split ──────────────────────────────────────────────────────────

/// Stacks the camera above its panel on a phone in portrait, and puts them
/// side by side when the window is short or wide.
///
/// Stacking is the right default — the camera wants the width. But a phone in
/// landscape is only ~360px tall, and splitting that 3:2 leaves the panel with
/// roughly 140px, which cannot hold the OCR text or the two action buttons.
class _VisionLayout extends StatelessWidget {
  const _VisionLayout({required this.camera, required this.panel});

  final Widget camera;
  final Widget panel;

  @override
  Widget build(BuildContext context) {
    if (context.prefersSideBySide) {
      return Row(
        children: [
          Expanded(flex: 3, child: camera),
          // Fixed rather than proportional: the panel needs a readable width,
          // and on a very wide window a 40% share is far more than it uses.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, minWidth: 300),
            child: panel,
          ),
        ],
      );
    }

    return Column(
      children: [
        Expanded(flex: 3, child: camera),
        Expanded(flex: 2, child: panel),
      ],
    );
  }
}

// ── Model-ready chip ──────────────────────────────────────────────────────────

class _ModelStatusChip extends StatelessWidget {
  const _ModelStatusChip({required this.isModelReady});
  final bool isModelReady;

  @override
  Widget build(BuildContext context) {
    final color =
        isModelReady ? context.appColors.success : context.appColors.warning;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isModelReady ? Icons.memory : Icons.hourglass_empty,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            isModelReady ? 'AI Ready' : 'Loading…',
            style: TextStyle(fontSize: 12, color: color),
          ),
        ],
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
      color: context.appColors.letterbox,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.no_photography_outlined,
            color: context.appColors.warning,
            size: 56,
          ),
          const SizedBox(height: 16),
          Text(
            'Camera permission required',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.appColors.onOverlay,
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
            style: TextStyle(color: context.appColors.onOverlay),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: Icon(
              permanentlyDenied ? Icons.settings : Icons.camera_alt_outlined,
            ),
            label: Text(permanentlyDenied ? 'Open settings' : 'Allow camera'),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.primary,
              foregroundColor: context.colors.onPrimary,
              minimumSize: const Size(0, 48),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Camera stage ──────────────────────────────────────────────────────────────

/// Picks exactly one camera consumer for the current source and mode.
///
/// There are four real combinations, and only one widget may hold the camera
/// at a time:
///
/// | source | mode      | widget                              |
/// |--------|-----------|-------------------------------------|
/// | phone  | detection | [YOLOView] — native camera + YOLO   |
/// | phone  | OCR       | [CameraPreview] — still capture     |
/// | ESP32  | detection | [Image.memory] + [DetectionOverlay] |
/// | ESP32  | OCR       | [Image.memory]                      |
///
/// The previous version mounted a `YOLOView` and a `CameraController` at the
/// same time, which is why the phone preview came up black.
class _CameraStage extends StatelessWidget {
  const _CameraStage({required this.vision});
  final VisionProvider vision;

  @override
  Widget build(BuildContext context) {
    if (!vision.connection.isConnected) {
      return const _Letterbox(
        child: _StageMessage(
          icon: Icons.wifi_off,
          label: 'Camera not connected',
        ),
      );
    }

    final isOcr = vision.currentMode == AppMode.ocr;

    return _Letterbox(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (vision.isUsingPhoneCamera)
            isOcr
                ? _PhoneStillPreview(vision: vision)
                : _YoloStage(vision: vision)
          else
            _Esp32Frame(vision: vision),

          // The ESP32 path needs our painter; YOLOView renders boxes natively,
          // so drawing ours on top of it would double every box.
          if (!isOcr &&
              !vision.isUsingPhoneCamera &&
              vision.detections.isNotEmpty)
            DetectionOverlay(detections: vision.detections),

          // ESP32 inference takes about a second per frame, so show that
          // something is happening rather than looking frozen.
          if (!vision.isUsingPhoneCamera && vision.isProcessing)
            const Positioned(top: 12, right: 12, child: _AnalyzingChip()),

          if (isOcr)
            _OcrCameraHint(vision: vision)
          else
            _DetectionCameraHint(vision: vision),
        ],
      ),
    );
  }
}

class _Letterbox extends StatelessWidget {
  const _Letterbox({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(color: context.appColors.letterbox, child: child);
  }
}

class _StageMessage extends StatelessWidget {
  const _StageMessage({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: context.appColors.onOverlay.withValues(alpha: 0.4),
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.appColors.onOverlay.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Native live-stream detection. Owns the phone camera while mounted.
class _YoloStage extends StatelessWidget {
  const _YoloStage({required this.vision});
  final VisionProvider vision;

  @override
  Widget build(BuildContext context) {
    final error = vision.detectionError;
    if (error != null) {
      return _StageMessage(
        icon: Icons.error_outline,
        label: 'Detection model failed to load.\n$error',
      );
    }

    return YOLOView(
      modelPath: AppConstants.yoloModelPath,
      task: YOLOTask.detect,
      confidenceThreshold: vision.settings.detectionConfidence,
      iouThreshold: 0.45,
      useGpu: true,
      onResult: vision.onLiveDetections,
      // Surfaced so a missing or corrupt model reads as an error rather than a
      // camera that silently never detects anything.
      onModelLoad: (modelPath, task) => vision.reportDetectionReady(),
      onModelError: (error, modelPath, task) =>
          vision.reportDetectionError(error),
    );
  }
}

/// Still-capture preview used for OCR on the phone.
class _PhoneStillPreview extends StatelessWidget {
  const _PhoneStillPreview({required this.vision});
  final VisionProvider vision;

  @override
  Widget build(BuildContext context) {
    final controller = vision.phoneController;
    if (controller == null || !controller.value.isInitialized) {
      return _StageMessage(
        icon: Icons.photo_camera_outlined,
        label: vision.ocrStage == OcrStage.failed
            ? vision.ocrMessage
            : 'Preparing camera…',
      );
    }
    return CameraPreview(controller);
  }
}

/// Frames streamed from the ESP32-CAM.
///
/// The provider decodes each JPEG to a [ui.Image] once and publishes it on a
/// [ValueNotifier]; a [RawImage] inside a [RepaintBoundary] paints it. This
/// keeps the video off the `notifyListeners` path (so it is not capped at the
/// UI-update throttle) and out of Flutter's `ImageCache` (which a per-frame
/// feed thrashes). The old `Image.memory(bytes)` did both.
class _Esp32Frame extends StatelessWidget {
  const _Esp32Frame({required this.vision});
  final VisionProvider vision;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<ui.Image?>(
        valueListenable: vision.esp32Frame,
        builder: (context, image, _) {
          if (image == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: context.appColors.accent),
                  const SizedBox(height: 12),
                  Text(
                    'Waiting for frames…',
                    style: TextStyle(color: context.appColors.onOverlay),
                  ),
                ],
              ),
            );
          }
          return RawImage(image: image, fit: BoxFit.cover);
        },
      ),
    );
  }
}

/// Bottom-of-frame status shown over the detector.
class _DetectionCameraHint extends StatelessWidget {
  const _DetectionCameraHint({required this.vision});
  final VisionProvider vision;

  @override
  Widget build(BuildContext context) {
    if (!vision.isVisionActive) {
      return Container(
        color: context.appColors.overlayScrim,
        child: Center(
          child: Text(
            'Vision paused',
            style: TextStyle(
              color: context.appColors.onOverlay,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    if (vision.detections.isNotEmpty) return const SizedBox.shrink();

    return const _BottomPill(label: 'Scanning for obstacles…');
  }
}

/// Bottom-of-frame status shown over the OCR preview.
class _OcrCameraHint extends StatelessWidget {
  const _OcrCameraHint({required this.vision});
  final VisionProvider vision;

  @override
  Widget build(BuildContext context) {
    final label = switch (vision.ocrStage) {
      OcrStage.capturing => 'Hold still…',
      OcrStage.recognising => 'Reading text…',
      OcrStage.done =>
        vision.ocrText.isEmpty ? 'No text found' : 'Text captured',
      OcrStage.failed => vision.ocrMessage,
      OcrStage.idle => 'Point at text, then press Read Text',
    };

    return _BottomPill(label: label, busy: vision.isReadingText);
  }
}

class _AnalyzingChip extends StatelessWidget {
  const _AnalyzingChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.appColors.overlayScrim,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.appColors.accent,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Analyzing',
            style: TextStyle(
              fontSize: 12,
              color: context.appColors.onOverlay,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomPill extends StatelessWidget {
  const _BottomPill({required this.label, this.busy = false});
  final String label;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 12,
      left: 16,
      right: 16,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: context.appColors.overlayScrim,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy) ...[
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.appColors.accent,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.appColors.onOverlay,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Detection panel ───────────────────────────────────────────────────────────

class _DetectionPanel extends StatelessWidget {
  const _DetectionPanel({required this.vision});
  final VisionProvider vision;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusRow(vision: vision),
          const SizedBox(height: 8),
          Expanded(
            child: vision.alerts.isEmpty
                ? Center(
                    child: Text(
                      'No obstacles detected',
                      style: TextStyle(color: context.appColors.muted),
                    ),
                  )
                : ListView(
                    children: vision.alerts
                        .map((a) => ObstacleAlertCard(alert: a))
                        .toList(),
                  ),
          ),
          const SizedBox(height: 8),
          _ActionRow(vision: vision),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.vision});
  final VisionProvider vision;

  @override
  Widget build(BuildContext context) {
    final active = vision.isVisionActive;
    final count = vision.detections.length;

    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                active ? context.appColors.success : context.appColors.warning,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            active ? 'Live scanning' : 'Paused',
            style: context.texts.bodyMedium,
          ),
        ),
        Text(
          '$count object${count == 1 ? '' : 's'}',
          style: context.texts.bodySmall?.copyWith(
            color: context.appColors.muted,
          ),
        ),
      ],
    );
  }
}

// ── OCR panel ─────────────────────────────────────────────────────────────────

/// The read-text result, shown large enough to be usable by someone with low
/// vision or by a sighted helper reading over the user's shoulder.
class _OcrPanel extends StatelessWidget {
  const _OcrPanel({required this.vision});
  final VisionProvider vision;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.text_fields,
                size: 18,
                color: context.appColors.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Detected text', style: context.texts.titleMedium),
              ),
              if (vision.ocrText.isNotEmpty)
                TextButton.icon(
                  onPressed: vision.clearText,
                  icon: const Icon(Icons.clear, size: 18),
                  label: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(child: _OcrBody(vision: vision)),
          const SizedBox(height: 8),
          _ActionRow(vision: vision),
        ],
      ),
    );
  }
}

class _OcrBody extends StatelessWidget {
  const _OcrBody({required this.vision});
  final VisionProvider vision;

  @override
  Widget build(BuildContext context) {
    if (vision.isReadingText) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: context.appColors.accent),
            const SizedBox(height: 12),
            Text(
              vision.ocrStage == OcrStage.capturing
                  ? 'Capturing…'
                  : 'Recognising text…',
              style: context.texts.bodyMedium,
            ),
          ],
        ),
      );
    }

    if (vision.ocrText.isEmpty) {
      final message = switch (vision.ocrStage) {
        OcrStage.failed => vision.ocrMessage,
        OcrStage.done =>
          vision.ocrMessage.isEmpty ? 'No text found.' : vision.ocrMessage,
        _ =>
          'Point the camera at a sign, label, or page, then press Read Text.',
      };
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: context.texts.bodyMedium?.copyWith(
              color: vision.ocrStage == OcrStage.failed
                  ? context.appColors.danger
                  : context.appColors.muted,
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Scrollbar(
        child: SingleChildScrollView(
          child: SelectableText(
            vision.ocrText,
            style: context.texts.bodyLarge?.copyWith(height: 1.45),
          ),
        ),
      ),
    );
  }
}

// ── Shared panel chrome ───────────────────────────────────────────────────────

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            context.colors.surfaceContainerHighest,
            context.colors.surface,
          ],
        ),
      ),
      child: child,
    );
  }
}

/// The two buttons at the bottom of the screen: the filled action for the
/// current mode on the left, and an outlined mode switch on the right. The
/// filled/outlined split keeps the primary action obvious when both buttons
/// would otherwise be the same blue.
class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.vision});
  final VisionProvider vision;

  @override
  Widget build(BuildContext context) {
    final isOcr = vision.currentMode == AppMode.ocr;

    return Row(
      children: [
        Expanded(
          child: isOcr
              ? ElevatedButton.icon(
                  onPressed: vision.isReadingText ? null : vision.readText,
                  icon: const Icon(Icons.document_scanner),
                  label: const Text('Read Text'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.primary,
                    foregroundColor: context.colors.onPrimary,
                    minimumSize: const Size(0, 56),
                  ),
                )
              : ElevatedButton.icon(
                  onPressed: vision.scanObstacles,
                  icon: const Icon(Icons.warning_amber),
                  label: const Text('Scan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.appColors.warning,
                    foregroundColor: context.appColors.onWarning,
                    minimumSize: const Size(0, 56),
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Semantics(
            button: true,
            label: 'Switch to ${vision.currentMode.toggled.displayName}',
            child: OutlinedButton.icon(
              onPressed: vision.toggleMode,
              icon: const Icon(Icons.swap_horiz),
              label: Text(
                isOcr ? 'Detect' : 'Read Text',
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 56),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
