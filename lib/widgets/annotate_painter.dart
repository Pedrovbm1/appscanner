import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/annotation.dart';

class AnnotationPainter extends CustomPainter {
  AnnotationPainter({
    required this.image,
    required this.annotations,
    required this.scale,
    this.selected,
  });

  static const inkColor = Color(0xFF000000);
  static const highlightColor = Color(0x59FFEB3B);
  static const selectionColor = Color(0xFF2196F3);

  final ui.Image image;
  final List<Annotation> annotations;
  final double scale;
  final Annotation? selected;

  static Rect? boundsOf(Annotation annotation) => switch (annotation) {
        final TextAnnotation a => a.bounds,
        final HighlightAnnotation a => a.rect,
        final SignatureAnnotation a => a.rect,
        PenAnnotation() => null,
      };

  static void paintStroke(
    Canvas canvas,
    List<Offset> points,
    double width,
    Color color,
  ) {
    if (points.isEmpty) {
      return;
    }
    if (points.length == 1) {
      canvas.drawCircle(points.first, width / 2, Paint()..color = color);
      return;
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    final full = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas.drawImageRect(
      image,
      full,
      full,
      Paint()..filterQuality = FilterQuality.medium,
    );
    for (final annotation in annotations) {
      _paintAnnotation(canvas, annotation);
    }
    final current = selected;
    if (current != null) {
      _paintSelection(canvas, current);
    }
    canvas.restore();
  }

  void _paintAnnotation(Canvas canvas, Annotation annotation) {
    switch (annotation) {
      case final TextAnnotation a:
        final painter = a.layout();
        painter.paint(canvas, a.offset);
        painter.dispose();
      case final HighlightAnnotation a:
        canvas.drawRect(a.rect, Paint()..color = highlightColor);
      case final PenAnnotation a:
        paintStroke(canvas, a.points, a.width, inkColor);
      case final SignatureAnnotation a:
        canvas.drawImageRect(
          a.image,
          Rect.fromLTWH(
            0,
            0,
            a.image.width.toDouble(),
            a.image.height.toDouble(),
          ),
          a.rect,
          Paint()..filterQuality = FilterQuality.high,
        );
    }
  }

  void _paintSelection(Canvas canvas, Annotation annotation) {
    final bounds = boundsOf(annotation);
    if (bounds == null) {
      return;
    }
    final border = Paint()
      ..color = selectionColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 / scale;
    canvas.drawRect(bounds.inflate(4 / scale), border);
    if (annotation is! HighlightAnnotation) {
      return;
    }
    final fill = Paint()..color = const Color(0xFFFFFFFF);
    for (final corner in [
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomRight,
      bounds.bottomLeft,
    ]) {
      canvas.drawCircle(corner, 7 / scale, fill);
      canvas.drawCircle(corner, 7 / scale, border);
    }
  }

  @override
  bool shouldRepaint(covariant AnnotationPainter oldDelegate) => true;
}
