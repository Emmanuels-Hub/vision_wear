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
    // Use SizedBox.expand so the CustomPaint fills the parent Stack cell.
    return SizedBox.expand(
      child: CustomPaint(
        painter: _DetectionPainter(detections: detections),
      ),
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

      // Skip degenerate boxes.
      if (rect.width < 4 || rect.height < 4) continue;

      // Colour coding: red = immediate hazard, orange = close hazard, teal = other.
      final Color boxColor;
      if (obj.isHazard && obj.proximity == ProximityLevel.immediate) {
        boxColor = AppTheme.danger;
      } else if (obj.isHazard) {
        boxColor = AppTheme.warning;
      } else {
        boxColor = AppTheme.accent;
      }

      // ── Corner-bracket style bounding box ─────────────────────────────────
      final bracketPaint = Paint()
        ..color = boxColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round;

      final cornerLen = (rect.shortestSide * 0.18).clamp(10.0, 28.0);
      _drawCornerBrackets(canvas, rect, cornerLen, bracketPaint);

      // Semi-transparent fill so the box outline stands out from the feed.
      final fillPaint = Paint()
        ..color = boxColor.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, fillPaint);

      // ── Label ─────────────────────────────────────────────────────────────
      final label = obj.label;
      final confidence = '${(obj.confidence * 100).round()}%';
      final distText =
          obj.estimatedDistance != null ? obj.distanceDescription : '';

      final labelText = distText.isEmpty
          ? '$label $confidence'
          : '$label $confidence  |  $distText';

      final textPainter = TextPainter(
        text: TextSpan(
          text: labelText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: size.width - rect.left - 4);

      final labelW = textPainter.width + 10;
      final labelH = textPainter.height + 6;

      // Place label above the box; if too close to the top edge, place below.
      double labelTop = rect.top - labelH - 2;
      if (labelTop < 0) labelTop = rect.top + 2;

      final labelRect = Rect.fromLTWH(
        rect.left,
        labelTop,
        labelW,
        labelH,
      );

      // Label background with rounded left & right on top.
      final rrect = RRect.fromRectAndCorners(
        labelRect,
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
        bottomRight: const Radius.circular(4),
      );
      canvas.drawRRect(rrect, Paint()..color = boxColor.withValues(alpha: 0.9));
      textPainter.paint(canvas, Offset(rect.left + 5, labelTop + 3));
    }
  }

  void _drawCornerBrackets(
    Canvas canvas,
    Rect rect,
    double len,
    Paint paint,
  ) {
    // Top-left
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(len, 0), paint);
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(0, len), paint);
    // Top-right
    canvas.drawLine(rect.topRight, rect.topRight + Offset(-len, 0), paint);
    canvas.drawLine(rect.topRight, rect.topRight + Offset(0, len), paint);
    // Bottom-left
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + Offset(len, 0), paint);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + Offset(0, -len), paint);
    // Bottom-right
    canvas.drawLine(rect.bottomRight, rect.bottomRight + Offset(-len, 0), paint);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + Offset(0, -len), paint);
  }

  @override
  bool shouldRepaint(covariant _DetectionPainter old) =>
      old.detections != detections;
}
