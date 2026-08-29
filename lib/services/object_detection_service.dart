import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../core/constants.dart';
import '../models/detected_object.dart';

/// Heuristic focal-length constant used for monocular distance estimation.
/// Tuned for a ~60° horizontal field of view at 640 px resolution.
const double _kFocalLength = 600.0;

/// Assumed real-world heights (in metres) for common object classes.
/// Used for rough distance estimation via the pinhole camera model:
///   distance = (knownHeight * focalLength) / pixelHeight
const Map<String, double> _kObjectHeights = {
  'person': 1.7,
  'car': 1.5,
  'truck': 2.5,
  'bus': 2.8,
  'train': 3.0,
  'bicycle': 1.1,
  'motorcycle': 1.2,
  'chair': 0.9,
  'bench': 0.5,
  'dog': 0.5,
  'cat': 0.35,
  'fire hydrant': 0.6,
  'stop sign': 0.75,
  'traffic light': 0.8,
  'parking meter': 1.2,
  'dining table': 0.75,
  'door': 2.0,
  'stairs': 0.2,
  'laptop': 0.3, // using 30cm so it doesn't give absurd distance
  'bottle': 0.25,
  'cup': 0.12,
  'keyboard': 0.05,
  'mouse': 0.04,
  'cell phone': 0.15,
  'book': 0.25,
};
const double _kDefaultObjectHeight = 0.5;

class ObjectDetectionService {
  ObjectDetectionService();

  static const String _bundledModelPath = 'assets/model.tflite';
  static const String _fallbackModelPath = 'yolov8n';

  late YOLO _yolo;
  String _modelPath = _bundledModelPath;

  bool _initialized = false;
  bool _loading = false;
  bool _processing = false;
  bool _usingFallbackModel = false;
  bool _resultLogged = false;

  bool get isReady => _initialized;

  Future<void> initialize() async {
    if (_initialized || _loading) return;

    _loading = true;
    try {
      _yolo = YOLO(
        modelPath: _modelPath,
        task: YOLOTask.detect,
        useGpu: false,
      );

      await _yolo.loadModel();
      _initialized = true;
      debugPrint('YOLO model loaded: $_modelPath');
    } catch (e, st) {
      debugPrint('YOLO load failed: $e');
      debugPrintStack(stackTrace: st);
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
    if (imageBytes.isEmpty) return [];

    if (!_initialized) {
      await initialize();
      if (!_initialized) return [];
    }

    if (_processing) return [];
    _processing = true;

    try {
      // ultralytics_yolo ≥0.6 predict() returns Map<String,dynamic>.
      final result = await _yolo.predict(
        imageBytes,
        confidenceThreshold: minConfidence,
        iouThreshold: 0.45,
      );

      // Debug: log the raw result structure once per session.
      if (!_resultLogged) {
        _resultLogged = true;
        debugPrint('[YOLO] Raw result keys: ${result.keys.toList()}');
        debugPrint('[YOLO] Raw result: $result');
      }

      return _parseResult(
        result,
        minConfidence: minConfidence,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
    } catch (e, st) {
      debugPrint('YOLO predict failed: $e');
      debugPrintStack(stackTrace: st);

      if (!_usingFallbackModel && _isModelError(e)) {
        final ok = await _tryFallback();
        if (ok) {
          _processing = false;
          return detectObjects(
            imageBytes,
            minConfidence: minConfidence,
            announceAllObjects: announceAllObjects,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
          );
        }
      }
      return [];
    } finally {
      _processing = false;
    }
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  List<DetectedObject> _parseResult(
    Map<String, dynamic> result, {
    required double minConfidence,
    required int imageWidth,
    required int imageHeight,
  }) {
    // ultralytics_yolo returns detections under various possible keys.
    final rawList = (result['boxes'] ??
        result['detections'] ??
        result['results'] ??
        []) as List<dynamic>;

    final List<DetectedObject> objects = [];

    for (final raw in rawList) {
      try {
        if (raw is! Map) continue;

        final confidence = _toDouble(raw['confidence'] ?? raw['conf'] ?? 0);
        if (confidence < minConfidence) continue;

        final label = (raw['className'] ??
                raw['class_name'] ??
                raw['label'] ??
                raw['name'] ??
                'unknown')
            .toString()
            .toLowerCase();

        // Bounding box – prefer normalised coords [0,1] when available.
        Rect box;
        if (raw.containsKey('normalizedBox')) {
          final nb = raw['normalizedBox'];
          box = Rect.fromLTRB(
            _toDouble(nb['left'] ?? nb['x1'] ?? 0),
            _toDouble(nb['top'] ?? nb['y1'] ?? 0),
            _toDouble(nb['right'] ?? nb['x2'] ?? 0),
            _toDouble(nb['bottom'] ?? nb['y2'] ?? 0),
          );
        } else {
          // Fall back to pixel coords and normalise.
          double l, t, r, b;
          if (raw.containsKey('boundingBox')) {
            final bb = raw['boundingBox'];
            l = _toDouble(bb['left'] ?? bb['x1'] ?? 0);
            t = _toDouble(bb['top'] ?? bb['y1'] ?? 0);
            r = _toDouble(bb['right'] ?? bb['x2'] ?? l);
            b = _toDouble(bb['bottom'] ?? bb['y2'] ?? t);
          } else {
            l = _toDouble(raw['x1'] ?? raw['xmin'] ?? 0);
            t = _toDouble(raw['y1'] ?? raw['ymin'] ?? 0);
            r = _toDouble(raw['x2'] ?? raw['xmax'] ?? 0);
            b = _toDouble(raw['y2'] ?? raw['ymax'] ?? 0);
          }
          // If coordinates look like pixel values, normalise them.
          if (r > 1.5 || b > 1.5) {
            l /= imageWidth;
            t /= imageHeight;
            r /= imageWidth;
            b /= imageHeight;
          }
          box = Rect.fromLTRB(
            l.clamp(0.0, 1.0),
            t.clamp(0.0, 1.0),
            r.clamp(0.0, 1.0),
            b.clamp(0.0, 1.0),
          );
        }

        if (box.isEmpty || box == Rect.zero) continue;

        // ── Filter: class allowlist ──────────────────────────────────────
        // Drop classes irrelevant to blind navigation (laptop, keyboard…).
        if (!AppConstants.allowedLabels.contains(label)) continue;

        // ── Filter: minimum bounding-box area ────────────────────────────
        // Reject shadow ghosts / noise that produce tiny or paper-thin boxes.
        final boxArea = box.width * box.height;
        if (boxArea < AppConstants.minDetectionArea) continue;

        final zone = _zone(box);
        final proximity = _proximity(box);
        final distance = _estimateDistance(label, box, imageHeight);

        objects.add(
          DetectedObject(
            label: label,
            confidence: confidence,
            boundingBox: box,
            zone: zone,
            proximity: proximity,
            isHazard: AppConstants.hazardLabels.contains(label) ||
                _isObstacle(box),
            estimatedDistance: distance,
          ),
        );
      } catch (e) {
        debugPrint('Skipped detection entry: $e');
      }
    }

    objects.sort(
      (a, b) => _priorityOf(b.proximity).compareTo(_priorityOf(a.proximity)),
    );

    return objects;
  }

  /// Monocular distance estimate using the pinhole formula:
  ///   d = (H_real * f) / H_pixel
  /// where H_pixel = box.height * imageHeight.
  double? _estimateDistance(String label, Rect box, int imageHeight) {
    final pixelHeight = box.height * imageHeight;
    if (pixelHeight < 5) return null; // too small to estimate reliably

    final realHeight = _kObjectHeights[label] ?? _kDefaultObjectHeight;
    final distance = (realHeight * _kFocalLength) / pixelHeight;
    // Clamp to a sensible range (0.2 m – 20 m).
    return distance.clamp(0.2, 20.0);
  }

  SpatialZone _zone(Rect box) {
    final cx = box.left + box.width / 2;
    if (cx < 0.33) return SpatialZone.left;
    if (cx > 0.66) return SpatialZone.right;
    return SpatialZone.center;
  }

  ProximityLevel _proximity(Rect box) {
    final area = box.width * box.height;
    final score = area * 2 + box.bottom;
    if (score > AppConstants.criticalProximityThreshold) {
      return ProximityLevel.immediate;
    }
    if (score > AppConstants.obstacleProximityThreshold) {
      return ProximityLevel.close;
    }
    if (score > 0.08) return ProximityLevel.approaching;
    return ProximityLevel.distant;
  }

  bool _isObstacle(Rect box) =>
      box.bottom > 0.55 && box.width * box.height > 0.06;

  int _priorityOf(ProximityLevel level) {
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

  bool _isModelError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('failed to load') || msg.contains('model');
  }

  Future<bool> _tryFallback() async {
    debugPrint('Trying fallback model: $_fallbackModelPath');
    _initialized = false;
    _modelPath = _fallbackModelPath;
    _usingFallbackModel = true;
    await initialize();
    return _initialized;
  }

  static double _toDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  Future<void> dispose() async {
    _initialized = false;
  }
}
