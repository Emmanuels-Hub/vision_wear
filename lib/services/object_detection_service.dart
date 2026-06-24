// import 'dart:io';
// import 'dart:typed_data';
// import 'dart:ui';

// import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart'
//     as mlkit;
// import 'package:path/path.dart' as p;
// import 'package:path_provider/path_provider.dart';

// import '../core/constants.dart';
// import '../models/detected_object.dart';

// class ObjectDetectionService {
//   ObjectDetectionService() {
//     _initialize();
//   }

//   late final mlkit.ObjectDetector _detector;
//   bool _isReady = false;
//   String? _tempDir;

//   void _initialize() {
//     final options = mlkit.ObjectDetectorOptions(
//       mode: mlkit.DetectionMode.stream,
//       classifyObjects: true,
//       multipleObjects: true,
//     );
//     _detector = mlkit.ObjectDetector(options: options);
//     _isReady = true;
//     _initTempDir();
//   }

//   Future<void> _initTempDir() async {
//     final dir = await getTemporaryDirectory();
//     _tempDir = dir.path;
//   }

//   bool get isReady => _isReady;

//   Future<List<DetectedObject>> detectObjects(
//     Uint8List imageBytes, {
//     required double minConfidence,
//     required bool announceAllObjects,
//   }) async {
//     if (!_isReady || imageBytes.isEmpty) return [];

//     _tempDir ??= (await getTemporaryDirectory()).path;
//     final tempFile = File(
//       p.join(_tempDir!, 'frame_${DateTime.now().millisecondsSinceEpoch}.jpg'),
//     );

//     try {
//       await tempFile.writeAsBytes(imageBytes, flush: true);
//       final inputImage = mlkit.InputImage.fromFilePath(tempFile.path);
//       final detected = await _detector.processImage(inputImage);

//       return _mapDetections(
//         detected,
//         minConfidence: minConfidence,
//         announceAllObjects: announceAllObjects,
//       );
//     } catch (_) {
//       return [];
//     } finally {
//       if (await tempFile.exists()) {
//         await tempFile.delete();
//       }
//     }
//   }

//   List<DetectedObject> _mapDetections(
//     List<mlkit.DetectedObject> detected, {
//     required double minConfidence,
//     required bool announceAllObjects,
//   }) {
//     return detected
//         .where((d) => d.labels.isNotEmpty)
//         .map((d) {
//           final label = d.labels.first.text.toLowerCase();
//           final confidence = d.labels.first.confidence;
//           if (confidence < minConfidence) return null;
//           if (!announceAllObjects &&
//               !AppConstants.hazardLabels.contains(label) &&
//               confidence < minConfidence + 0.15) {
//             return null;
//           }

//           final box = d.boundingBox;
//           const imageWidth = 640.0;
//           const imageHeight = 480.0;
//           final normalizedBox = Rect.fromLTWH(
//             box.left / imageWidth,
//             box.top / imageHeight,
//             box.width / imageWidth,
//             box.height / imageHeight,
//           );

//           return DetectedObject(
//             label: label,
//             confidence: confidence,
//             boundingBox: normalizedBox,
//             zone: _determineZone(normalizedBox),
//             proximity: _determineProximity(normalizedBox),
//             isHazard: AppConstants.hazardLabels.contains(label) ||
//                 _isObstacleByPosition(normalizedBox),
//           );
//         })
//         .whereType<DetectedObject>()
//         .toList()
//       ..sort(
//         (a, b) =>
//             _proximityRank(b.proximity).compareTo(_proximityRank(a.proximity)),
//       );
//   }

//   int _proximityRank(ProximityLevel level) {
//     switch (level) {
//       case ProximityLevel.immediate:
//         return 4;
//       case ProximityLevel.close:
//         return 3;
//       case ProximityLevel.approaching:
//         return 2;
//       case ProximityLevel.distant:
//         return 1;
//     }
//   }

//   SpatialZone _determineZone(Rect box) {
//     final centerX = box.left + box.width / 2;
//     final centerY = box.top + box.height / 2;

//     if (centerY > 0.65) return SpatialZone.near;
//     if (centerY < 0.25) return SpatialZone.far;

//     if (centerX < 0.33) return SpatialZone.left;
//     if (centerX > 0.66) return SpatialZone.right;
//     return SpatialZone.center;
//   }

//   ProximityLevel _determineProximity(Rect box) {
//     final area = box.width * box.height;
//     final bottomWeight = box.bottom;
//     final score = area * 2 + bottomWeight;

//     if (score > AppConstants.criticalProximityThreshold) {
//       return ProximityLevel.immediate;
//     }
//     if (score > AppConstants.obstacleProximityThreshold) {
//       return ProximityLevel.close;
//     }
//     if (score > 0.08) return ProximityLevel.approaching;
//     return ProximityLevel.distant;
//   }

//   bool _isObstacleByPosition(Rect box) {
//     final area = box.width * box.height;
//     return box.bottom > 0.55 && area > 0.06;
//   }

//   void dispose() {
//     _detector.close();
//     _isReady = false;
//   }
// }

import 'dart:typed_data';
import 'dart:ui';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../core/constants.dart';
import '../models/detected_object.dart';

class ObjectDetectionService {
  late final YOLO _yolo;
  bool _isReady = false;

  ObjectDetectionService() {
    _initialize();
  }

  Future<void> _initialize() async {
    // Load the model locally. The plugin automatically routes to the .tflite on
    // Android or the .mlpackage on iOS.
    _yolo = YOLO(modelPath: 'yolo11n', task: YOLOTask.detect);
    await _yolo.loadModel();
    _isReady = true;
  }

  bool get isReady => _isReady;

  Future<List<DetectedObject>> detectObjects(
    Uint8List imageBytes, {
    required double minConfidence,
    required bool announceAllObjects,
    int imageWidth = 640, // Match this to your ESP32 stream resolution!
    int imageHeight = 480,
  }) async {
    if (!_isReady || imageBytes.isEmpty) return [];

    try {
      // Pass the raw JPEG bytes from the ESP32 straight to the NPU/GPU
      final results = await _yolo.predict(imageBytes);

      return _mapDetections(
        results,
        minConfidence: minConfidence,
        announceAllObjects: announceAllObjects,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
    } catch (e) {
      return [];
    }
  }

  List<DetectedObject> _mapDetections(
    List<dynamic> detected, {
    required double minConfidence,
    required bool announceAllObjects,
    required int imageWidth,
    required int imageHeight,
  }) {
    return detected
        .map((d) {
          final label = d.className.toLowerCase();
          final confidence = d.confidence;

          if (confidence < minConfidence) return null;
          if (!announceAllObjects &&
              !AppConstants.hazardLabels.contains(label)) {
            return null; // Skip if we are filtering out non-hazards
          }

          // Ensure the bounding box is normalized (between 0.0 and 1.0)
          // so your Proximity Math works correctly regardless of camera resolution.
          final normalizedBox = Rect.fromLTRB(
            d.left / imageWidth,
            d.top / imageHeight,
            d.right / imageWidth,
            d.bottom / imageHeight,
          );

          return DetectedObject(
            label: label,
            confidence: confidence,
            boundingBox: normalizedBox,
            zone: _determineZone(normalizedBox),
            proximity: _determineProximity(normalizedBox),
            isHazard:
                AppConstants.hazardLabels.contains(label) ||
                _isObstacleByPosition(normalizedBox),
          );
        })
        .whereType<DetectedObject>()
        .toList()
      ..sort(
        (a, b) =>
            _proximityRank(b.proximity).compareTo(_proximityRank(a.proximity)),
      );
  }

  int _proximityRank(ProximityLevel level) {
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
    final bottomWeight = box
        .bottom; // Objects closer to the bottom edge of the frame are physically closer to the user
    final score = (area * 2) + bottomWeight;

    if (score > AppConstants.criticalProximityThreshold)
      return ProximityLevel.immediate;
    if (score > AppConstants.obstacleProximityThreshold)
      return ProximityLevel.close;
    if (score > 0.08) return ProximityLevel.approaching;
    return ProximityLevel.distant;
  }

  bool _isObstacleByPosition(Rect box) {
    // If something is massive and at the bottom of the user's feet, flag it as an obstacle regardless of the label
    final area = box.width * box.height;
    return box.bottom > 0.55 && area > 0.06;
  }

  Future<void> dispose() async {
    _isReady = false;
  }
}
