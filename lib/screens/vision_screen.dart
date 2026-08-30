import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/constants.dart';
import '../core/theme/app_theme.dart';
import '../models/connection_state.dart';
import '../models/detected_object.dart';
import '../providers/vision_provider.dart';
import '../widgets/detection_overlay.dart';
import '../widgets/obstacle_alert_card.dart';

class VisionScreen extends StatefulWidget {
  const VisionScreen({super.key});

  @override
  State<VisionScreen> createState() => _VisionScreenState();
}

class _VisionScreenState extends State<VisionScreen>
    with WidgetsBindingObserver {
  /// Captured in initState. Reading the provider off `context` in dispose()
  /// throws, because the element is already unmounted by then.
  late final VisionProvider _vision;

  bool _resumeVisionOnForeground = false;

  @override
  void initState() {
    super.initState();
    _vision = context.read<VisionProvider>();
    WidgetsBinding.instance.addObserver(this);

    // Navigation assistance is useless if the screen sleeps mid-walk.
    WakelockPlus.enable();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (!_vision.connection.isConnected) {
        await _vision.connectCamera();
      }
      if (!mounted) return;
      await _vision.startVision();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Stop speaking and inferring while backgrounded, but leave the camera
        // link up so the physical buttons still reach the app.
        if (_vision.isVisionActive) {
          _resumeVisionOnForeground = true;
          _vision.stopVision();
        }
      case AppLifecycleState.resumed:
        if (_resumeVisionOnForeground) {
          _resumeVisionOnForeground = false;
          _vision.startVision();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _vision.stopVision();
    super.dispose();
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
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: Colors.white70),
                ),
              ],
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
              tooltip: 'Go back',
            ),
            actions: [
              IconButton(
                icon: Icon(
                  vision.isVisionActive ? Icons.pause : Icons.play_arrow,
                ),
                onPressed: () {
                  if (vision.isVisionActive) {
                    vision.stopVision();
                  } else {
                    vision.startVision();
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
              Expanded(
                flex: 3,
                child: _CameraPreview(
                  frameListenable: vision.frameNotifier,
                  detections: vision.detections,
                  connection: vision.connection,
                  isProcessing: vision.isProcessing,
                ),
              ),
              Expanded(
                flex: 2,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: AppTheme.cardDark,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _StatusRow(vision: vision),
                      const SizedBox(height: 12),
                      Text(
                        vision.isDetectionReady
                            ? '${vision.detections.length} objects detected'
                            : 'Loading detection model...',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView(
                          children: vision.alerts
                              .map((a) => ObstacleAlertCard(alert: a))
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
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
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: vision.repeatLast,
                              icon: const Icon(Icons.replay),
                              label: const Text('Repeat'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                minimumSize: const Size(0, 52),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.vision});

  final VisionProvider vision;

  @override
  Widget build(BuildContext context) {
    final connection = vision.connection;

    final (Color color, String label) = switch (connection.status) {
      ConnectionStatus.connected => vision.isVisionActive
          ? (AppTheme.accent, 'Scanning...')
          : (AppTheme.warning, 'Paused'),
      ConnectionStatus.reconnecting => (AppTheme.warning, 'Reconnecting...'),
      ConnectionStatus.discovering => (AppTheme.warning, 'Finding camera...'),
      ConnectionStatus.connecting => (AppTheme.warning, 'Connecting...'),
      ConnectionStatus.error => (AppTheme.danger, connection.message),
      ConnectionStatus.disconnected => (Colors.grey, 'Not connected'),
    };

    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
        ),
        if (connection.isConnected && connection.fps > 0)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              '${connection.fps.toStringAsFixed(0)} fps',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ),
        if (vision.isProcessing)
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.accent,
              ),
            ),
          ),
      ],
    );
  }
}

class _CameraPreview extends StatelessWidget {
  const _CameraPreview({
    required this.frameListenable,
    required this.detections,
    required this.connection,
    required this.isProcessing,
  });

  final ValueListenable<Uint8List?> frameListenable;
  final List<DetectedObject> detections;
  final CameraConnectionInfo connection;
  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Only this subtree rebuilds per frame.
          ValueListenableBuilder<Uint8List?>(
            valueListenable: frameListenable,
            builder: (context, frame, _) {
              if (frame == null) {
                return _WaitingForFeed(connection: connection);
              }
              // The bounding boxes are normalised against the source frame, so
              // the overlay has to sit on exactly the rect the image occupies.
              // Letting the image letterbox inside a larger stack (or crop with
              // BoxFit.cover) puts every box in the wrong place.
              return Center(
                child: AspectRatio(
                  aspectRatio:
                      AppConstants.frameWidth / AppConstants.frameHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(
                        frame,
                        fit: BoxFit.fill,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.low,
                      ),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          return DetectionOverlay(
                            detections: detections,
                            imageSize: Size(
                              constraints.maxWidth,
                              constraints.maxHeight,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Reconnect banner sits above the last good frame rather than
          // replacing it, so the user is not left staring at a blank screen
          // during a one-second WiFi hiccup.
          if (connection.isBusy)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: _Pill(
                color: AppTheme.warning,
                icon: Icons.wifi_tethering,
                text: connection.message,
              ),
            ),

          if (isProcessing)
            const Positioned(
              bottom: 12,
              right: 12,
              child: _Pill(
                color: AppTheme.accent,
                icon: null,
                text: 'Analyzing',
              ),
            ),
        ],
      ),
    );
  }
}

class _WaitingForFeed extends StatelessWidget {
  const _WaitingForFeed({required this.connection});

  final CameraConnectionInfo connection;

  @override
  Widget build(BuildContext context) {
    final failed = connection.status == ConnectionStatus.error;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (failed)
              const Icon(Icons.videocam_off, color: AppTheme.danger, size: 48)
            else
              const CircularProgressIndicator(color: AppTheme.accent),
            const SizedBox(height: 16),
            Text(
              failed ? connection.message : 'Waiting for camera feed...',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            if (connection.reconnectAttempts > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Retrying automatically',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.icon, required this.text});

  final Color color;
  final IconData? icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 14, color: color)
          else
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
