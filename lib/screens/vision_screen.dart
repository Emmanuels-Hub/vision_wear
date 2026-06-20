import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final vision = context.read<VisionProvider>();
      if (!vision.connection.isConnected) {
        await vision.connectCamera();
      }
      await vision.startVision();
    });
  }

  @override
  void dispose() {
    context.read<VisionProvider>().stopVision();
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
                  frame: vision.currentFrame,
                  detections: vision.detections,
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
                            vision.isVisionActive ? 'Scanning...' : 'Paused',
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
                      Text(
                        '${vision.detections.length} objects detected',
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

class _CameraPreview extends StatelessWidget {
  const _CameraPreview({
    required this.frame,
    required this.detections,
    required this.isProcessing,
  });

  final Uint8List? frame;
  final List<DetectedObject> detections;
  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (frame != null)
            Image.memory(frame!, fit: BoxFit.cover, gaplessPlayback: true)
          else
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppTheme.accent),
                  SizedBox(height: 16),
                  Text(
                    'Waiting for camera feed...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          if (frame != null)
            LayoutBuilder(
              builder: (context, constraints) {
                return DetectionOverlay(
                  detections: detections,
                  imageSize: Size(constraints.maxWidth, constraints.maxHeight),
                );
              },
            ),
          if (isProcessing)
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
