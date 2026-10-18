import 'dart:math' as math;

import 'package:opencv_dart/opencv.dart' as cv;

class IdComposer {
  static const int canvasWidth = 2480;
  static const int canvasHeight = 3508;
  static const int labelSpace = 90;

  static Future<String> compose({
    required String frontPath,
    required String backPath,
    required String outputPath,
  }) async {
    final margin = (canvasWidth * 0.08).round();
    final maxWidth = canvasWidth - 2 * margin;
    final maxHeight = (canvasHeight / 2 - 1.5 * margin - labelSpace).floor();
    final canvas = await cv.MatAsync.fromScalarAsync(
      canvasHeight,
      canvasWidth,
      cv.MatType.CV_8UC3,
      cv.Scalar(255, 255, 255),
    );
    try {
      await _place(
        canvas: canvas,
        sourcePath: frontPath,
        label: 'Frente',
        areaTop: margin,
        margin: margin,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );
      await _place(
        canvas: canvas,
        sourcePath: backPath,
        label: 'Reverso',
        areaTop: canvasHeight ~/ 2 + margin ~/ 2,
        margin: margin,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );
      if (!await cv.imwriteAsync(outputPath, canvas)) {
        throw StateError('No se pudo guardar la identificación');
      }
      return outputPath;
    } finally {
      canvas.dispose();
    }
  }

  static Future<void> _place({
    required cv.Mat canvas,
    required String sourcePath,
    required String label,
    required int areaTop,
    required int margin,
    required int maxWidth,
    required int maxHeight,
  }) async {
    final src = await cv.imreadAsync(sourcePath);
    cv.Mat? resized;
    try {
      if (src.isEmpty) {
        throw StateError('No se pudo leer $sourcePath');
      }
      final scale = math.min(maxWidth / src.cols, maxHeight / src.rows);
      final width = math.max(1, math.min(maxWidth, (src.cols * scale).round()));
      final height = math.max(1, math.min(maxHeight, (src.rows * scale).round()));
      resized = await cv.resizeAsync(
        src,
        (width, height),
        interpolation: scale < 1 ? cv.INTER_AREA : cv.INTER_CUBIC,
      );
      final areaHeight = maxHeight + labelSpace;
      final blockHeight = labelSpace + height;
      final blockTop = areaTop + ((areaHeight - blockHeight) / 2).round();
      final x = ((canvasWidth - width) / 2).round();
      final y = blockTop + labelSpace;
      final rect = cv.Rect(x, y, width, height);
      cv.Mat? roi;
      try {
        roi = await canvas.regionAsync(rect);
        await resized.copyToAsync(roi);
      } finally {
        roi?.dispose();
        rect.dispose();
      }
      await cv.putTextAsync(
        canvas,
        label,
        cv.Point(x, y - 28),
        cv.FONT_HERSHEY_SIMPLEX,
        2.0,
        cv.Scalar(128, 128, 128),
        thickness: 3,
        lineType: cv.LINE_AA,
      );
    } finally {
      resized?.dispose();
      src.dispose();
    }
  }
}
