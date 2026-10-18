import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

sealed class Annotation {}

class TextAnnotation extends Annotation {
  TextAnnotation({
    required this.offset,
    required this.text,
    required this.fontSize,
  });

  static const color = Color(0xFF000000);

  Offset offset;
  final String text;
  final double fontSize;

  TextPainter layout() => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(color: color, fontSize: fontSize),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  Rect get bounds {
    final painter = layout();
    final size = painter.size;
    painter.dispose();
    return offset & size;
  }
}

class HighlightAnnotation extends Annotation {
  HighlightAnnotation({required this.rect});

  Rect rect;
}

class PenAnnotation extends Annotation {
  PenAnnotation({required this.points, required this.width});

  final List<Offset> points;
  final double width;
}

class SignatureAnnotation extends Annotation {
  SignatureAnnotation({required this.image, required this.rect});

  final ui.Image image;
  Rect rect;

  double get aspectRatio => image.height / image.width;
}
