import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../core/constants.dart';
import '../models/detected_object.dart';

class ObjectDetectionService {
  ObjectDetectionService();

  YOLO? _yolo;

  bool _initialized = false;
  bool _loading = false;
  bool _processing = false;
  String? _lastError;

  bool get isReady => _initialized;

  /// Null unless model loading failed, in which case it carries the reason so
  /// the UI can say something more useful than "0 objects detected".
  String? get lastError => _lastError;

  Future<void> initialize() async {
    if (_initialized || _loading) return;

    _loading = true;
    try {
      // Try the bundled model first so the ESP32 path and the phone's YOLOView
      // run the same weights. These used to name different models, which meant
      // the two cameras could disagree about what was in front of the user.
      // Fall back to the plugin's built-in model if the asset cannot be
      // resolved on this platform, rather than leaving detection dead.
      for (final path in const [
        AppConstants.yoloModelPath,
        AppConstants.yoloFallbackModel,
      ]) {
        try {
          final yolo = YOLO(modelPath: path, task: YOLOTask.detect);
          await yolo.loadModel();
          _yolo = yolo;
          _initialized = true;
          _lastError = null;
          debugPrint("YOLO model loaded from $path");
          return;
        } catch (e) {
          _lastError = e.toString();
          debugPrint("YOLO model $path failed to load: $e");
        }
      }
    } finally {
      _loading = false;
    }
  }

  Future<List<DetectedObject>> detectObjects(
    Uint8List imageBytes, {
    required double minConfidence,
    required bool announceAllObjects,
    required int imageWidth,
    required int imageHeight,
  }) async {
    final yolo = _yolo;
    if (!_initialized || yolo == null) return [];
    if (_processing) return [];
    if (imageBytes.isEmpty) return [];

    _processing = true;
    try {
      final prediction = await yolo.predict(imageBytes);

      // The plugin has returned a bare list in some versions and a keyed map in
      // others. Go through `dynamic` so this keeps compiling and working across
      // either shape rather than breaking on a plugin upgrade.
      final dynamic raw = prediction;
      List<dynamic> detections = const [];
      if (raw is List) {
        detections = raw;
      } else if (raw is Map) {
        final boxes = raw['boxes'] ?? raw['results'] ?? raw['detections'];
        if (boxes is List) detections = boxes;
      }

      return _convertDetections(
        detections,
        minConfidence,
        announceAllObjects,
        imageWidth,
        imageHeight,
      );
    } catch (e) {
      debugPrint('Detection error: $e');
      return [];
    } finally {
      _processing = false;
    }
  }

  List<DetectedObject> _convertDetections(
    List<dynamic> detections,
    double minConfidence,
    bool announceAllObjects,
    int imageWidth,
    int imageHeight,
  ) {
    final objects = <DetectedObject>[];

    for (final detection in detections) {
      try {
        final parsed = _parseDetection(detection, imageWidth, imageHeight);
        if (parsed == null) continue;

        final (label, confidence, rect) = parsed;

        if (confidence < minConfidence) continue;
        if (!announceAllObjects &&
            !AppConstants.hazardLabels.contains(label)) {
          continue;
        }

        objects.add(
          DetectedObject(
            label: label,
            confidence: confidence,
            boundingBox: rect,
            zone: _determineZone(rect),
            proximity: _determineProximity(rect),
            isHazard:
                AppConstants.hazardLabels.contains(label) || _isObstacle(rect),
          ),
        );
      } catch (_) {
        // Skip anything that does not match a shape we understand rather than
        // dropping the whole frame's results.
      }
    }

    objects.sort(
      (a, b) => _priority(b.proximity).compareTo(_priority(a.proximity)),
    );

    return objects;
  }

  /// The plugin has returned both typed result objects and plain maps across
  /// versions, so handle either rather than crashing on an upgrade.
  (String, double, Rect)? _parseDetection(
    dynamic detection,
    int imageWidth,
    int imageHeight,
  ) {
    String? label;
    double? confidence;
    double? left, top, right, bottom;

    if (detection is Map) {
      label = (detection['className'] ?? detection['class'] ?? detection['label'])
          ?.toString()
          .toLowerCase();
      confidence = (detection['confidence'] as num?)?.toDouble();

      final box = detection['box'] ?? detection['bbox'] ?? detection;
      if (box is Map) {
        left = (box['x1'] ?? box['left'] as num?)?.toDouble();
        top = (box['y1'] ?? box['top'] as num?)?.toDouble();
        right = (box['x2'] ?? box['right'] as num?)?.toDouble();
        bottom = (box['y2'] ?? box['bottom'] as num?)?.toDouble();
      } else if (box is List && box.length >= 4) {
        left = (box[0] as num).toDouble();
        top = (box[1] as num).toDouble();
        right = (box[2] as num).toDouble();
        bottom = (box[3] as num).toDouble();
      }
    } else {
      label = detection.className?.toString().toLowerCase();
      confidence = (detection.confidence as num?)?.toDouble();
      left = (detection.left as num?)?.toDouble();
      top = (detection.top as num?)?.toDouble();
      right = (detection.right as num?)?.toDouble();
      bottom = (detection.bottom as num?)?.toDouble();
    }

    if (label == null || label.isEmpty) return null;
    if (confidence == null) return null;
    if (left == null || top == null || right == null || bottom == null) {
      return null;
    }

    // Some builds return pixel coordinates, others already-normalised ones.
    // Anything above 1.0 must be pixels.
    final isPixels = right > 1.0 || bottom > 1.0;
    final rect = isPixels
        ? Rect.fromLTRB(
            left / imageWidth,
            top / imageHeight,
            right / imageWidth,
            bottom / imageHeight,
          )
        : Rect.fromLTRB(left, top, right, bottom);

    // Clamp so a box that runs off the edge of the frame does not paint
    // outside the preview.
    final clamped = Rect.fromLTRB(
      rect.left.clamp(0.0, 1.0),
      rect.top.clamp(0.0, 1.0),
      rect.right.clamp(0.0, 1.0),
      rect.bottom.clamp(0.0, 1.0),
    );
    if (clamped.width <= 0 || clamped.height <= 0) return null;

    return (label, confidence.clamp(0.0, 1.0), clamped);
  }

  int _priority(ProximityLevel level) {
    switch (level) {
      case ProximityLevel.immediate:
        return 4;
      case ProximityLevel.close:
        return 3;
      case ProximityLevel.approaching:
        return 2;
      case ProximityLevel.distant:
        return 1;
    }
  }

  SpatialZone _determineZone(Rect box) {
    final centerX = box.left + box.width / 2;

    if (centerX < 0.33) return SpatialZone.left;
    if (centerX > 0.66) return SpatialZone.right;
    return SpatialZone.center;
  }

  ProximityLevel _determineProximity(Rect box) {
    final area = box.width * box.height;
    final score = (area * 2) + box.bottom;

    if (score > AppConstants.criticalProximityThreshold) {
      return ProximityLevel.immediate;
    }
    if (score > AppConstants.obstacleProximityThreshold) {
      return ProximityLevel.close;
    }
    if (score > 0.08) return ProximityLevel.approaching;
    return ProximityLevel.distant;
  }

  bool _isObstacle(Rect box) {
    final area = box.width * box.height;
    return box.bottom > 0.55 && area > 0.06;
  }

  Future<void> dispose() async {
    _initialized = false;
    _yolo = null;
  }
}
