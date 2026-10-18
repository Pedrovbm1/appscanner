import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class LiveQuadPainter extends CustomPainter {
  const LiveQuadPainter({
    required this.quad,
    required this.stable,
    required this.previewSize,
    required this.sensorOrientation,
  });

  final List<Offset> quad;
  final bool stable;
  final Size previewSize;
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
    required Size previewSize,
    required Size box,
  }) {
    if (previewSize.width <= 0 || previewSize.height <= 0) {
      return const [];
    }
    final scale = math.max(
      box.width / previewSize.width,
      box.height / previewSize.height,
    );
    final drawnWidth = previewSize.width * scale;
    final drawnHeight = previewSize.height * scale;
    final offset = Offset(
      (box.width - drawnWidth) / 2,
      (box.height - drawnHeight) / 2,
    );
    return [
      for (final point in sensorQuad)
        _scaled(toPortrait(point, sensorOrientation), drawnWidth, drawnHeight) +
            offset,
    ];
  }

  static Offset _scaled(Offset point, double width, double height) =>
      Offset(point.dx * width, point.dy * height);

  @override
  void paint(Canvas canvas, Size size) {
    final points = mapToScreen(
      quad,
      sensorOrientation: sensorOrientation,
      previewSize: previewSize,
      box: size,
    );
    if (points.length < 3) {
      return;
    }
    final path = Path()..addPolygon(points, true);
    final color = stable
        ? const Color(0xFF69F0AE)
        : Colors.white.withValues(alpha: 0.7);
    canvas.drawPath(
      path,
      Paint()..color = color.withValues(alpha: 0.12),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant LiveQuadPainter oldDelegate) =>
      oldDelegate.stable != stable ||
      oldDelegate.previewSize != previewSize ||
      oldDelegate.sensorOrientation != sensorOrientation ||
      !listEquals(oldDelegate.quad, quad);
}
