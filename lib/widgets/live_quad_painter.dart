import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class LiveQuadPainter extends CustomPainter {
  const LiveQuadPainter({
    required this.quad,
    required this.stable,
    required this.previewRect,
    required this.sensorOrientation,
  });

  final List<Offset> quad;
  final bool stable;
  final Rect previewRect;
  final int sensorOrientation;

  static Offset toPortrait(Offset sensorPoint, int sensorOrientation) =>
      switch (sensorOrientation % 360) {
        90 => Offset(1 - sensorPoint.dy, sensorPoint.dx),
        270 => Offset(sensorPoint.dy, 1 - sensorPoint.dx),
        _ => sensorPoint,
      };

  static List<Offset> mapToScreen(
    List<Offset> sensorQuad, {
    required int sensorOrientation,
    required Rect previewRect,
  }) {
    if (previewRect.isEmpty) {
      return const [];
    }
    return [
      for (final point in sensorQuad)
        previewRect.topLeft +
            _scaled(
              toPortrait(point, sensorOrientation),
              previewRect.width,
              previewRect.height,
            ),
    ];
  }

  static Offset _scaled(Offset point, double width, double height) =>
      Offset(point.dx * width, point.dy * height);

  @override
  void paint(Canvas canvas, Size size) {
    final points = mapToScreen(
      quad,
      sensorOrientation: sensorOrientation,
      previewRect: previewRect,
    );
    if (points.length < 3) {
      return;
    }
    final path = Path()..addPolygon(points, true);
    final color = stable
        ? AppColors.mint
        : AppColors.mint.withValues(alpha: 0.75);
    canvas.drawPath(
      path,
      Paint()..color = AppColors.mint.withValues(alpha: stable ? 0.14 : 0.08),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    final dot = Paint()..color = color;
    for (final point in points) {
      canvas.drawCircle(point, 7.5, dot);
    }
  }

  @override
  bool shouldRepaint(covariant LiveQuadPainter oldDelegate) =>
      oldDelegate.stable != stable ||
      oldDelegate.previewRect != previewRect ||
      oldDelegate.sensorOrientation != sensorOrientation ||
      !listEquals(oldDelegate.quad, quad);
}
