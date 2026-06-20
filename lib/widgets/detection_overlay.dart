import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/detected_object.dart';

class DetectionOverlay extends StatelessWidget {
  const DetectionOverlay({
    super.key,
    required this.detections,
    required this.imageSize,
  });

  final List<DetectedObject> detections;
  final Size imageSize;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: imageSize,
      painter: _DetectionPainter(detections: detections),
    );
  }
}

class _DetectionPainter extends CustomPainter {
  _DetectionPainter({required this.detections});

  final List<DetectedObject> detections;

  @override
  void paint(Canvas canvas, Size size) {
    for (final obj in detections) {
      final rect = Rect.fromLTWH(
        obj.boundingBox.left * size.width,
        obj.boundingBox.top * size.height,
        obj.boundingBox.width * size.width,
        obj.boundingBox.height * size.height,
      );

      final color = obj.isHazard
          ? (obj.proximity == ProximityLevel.immediate
              ? AppTheme.danger
              : AppTheme.warning)
          : AppTheme.accent;

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;

      canvas.drawRect(rect, paint);

      final bgPaint = Paint()..color = color.withValues(alpha: 0.85);
      final text = '${obj.label} ${(obj.confidence * 100).toInt()}%';
      final textPainter = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelRect = Rect.fromLTWH(
        rect.left,
        rect.top - 20,
        textPainter.width + 8,
        20,
      );
      canvas.drawRect(labelRect, bgPaint);
      textPainter.paint(canvas, Offset(rect.left + 4, rect.top - 18));
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionPainter oldDelegate) {
    return oldDelegate.detections != detections;
  }
}
