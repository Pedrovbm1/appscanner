import 'dart:io';
import 'dart:math' as math;

import 'package:opencv_dart/opencv.dart' as cv;

enum ScanFilter { original, enhance, grayscale, bw, lighten, invert, noShadow }

extension ScanFilterLabel on ScanFilter {
  String get label => switch (this) {
        ScanFilter.original => 'Original',
        ScanFilter.enhance => 'Mejorar',
        ScanFilter.grayscale => 'Grises',
        ScanFilter.bw => 'B y N',
        ScanFilter.lighten => 'Aclarar',
        ScanFilter.invert => 'Invertir',
        ScanFilter.noShadow => 'Sin sombra',
      };
}

class ImageFilters {
  static const int previewMaxDimension = 1400;

  static Future<String> buildPreview({
    required String sourcePath,
    required String previewPath,
    required ScanFilter filter,
  }) async {
    final src = await cv.imreadAsync(sourcePath);
    cv.Mat? resized;
    cv.Mat? out;
    try {
      final maxDimension = math.max(src.cols, src.rows);
      if (maxDimension > previewMaxDimension) {
        final scale = previewMaxDimension / maxDimension;
        resized = await cv.resizeAsync(
          src,
          ((src.cols * scale).round(), (src.rows * scale).round()),
        );
      }
      out = await _apply(resized ?? src, filter);
      final saved = await cv.imwriteAsync(previewPath, out);
      if (!saved) {
        throw StateError('No se pudo escribir la vista previa');
      }
      return previewPath;
    } finally {
      out?.dispose();
      resized?.dispose();
      src.dispose();
    }
  }

  static Future<String> export({
    required String sourcePath,
    required String outPath,
    required ScanFilter filter,
  }) async {
    if (filter == ScanFilter.original) {
      await File(sourcePath).copy(outPath);
      return outPath;
    }
    final src = await cv.imreadAsync(sourcePath);
    cv.Mat? out;
    try {
      out = await _apply(src, filter);
      final saved = await cv.imwriteAsync(outPath, out);
      if (!saved) {
        throw StateError('No se pudo guardar el filtro');
      }
      return outPath;
    } finally {
      out?.dispose();
      src.dispose();
    }
  }

  static Future<cv.Mat> _apply(cv.Mat src, ScanFilter filter) async {
    switch (filter) {
      case ScanFilter.original:
        return src.cloneAsync();
      case ScanFilter.grayscale:
        return cv.cvtColorAsync(src, cv.COLOR_BGR2GRAY);
      case ScanFilter.bw:
        final gray = await cv.cvtColorAsync(src, cv.COLOR_BGR2GRAY);
        try {
          return await cv.adaptiveThresholdAsync(
            gray,
            255,
            cv.ADAPTIVE_THRESH_GAUSSIAN_C,
            cv.THRESH_BINARY,
            25,
            12,
          );
        } finally {
          gray.dispose();
        }
      case ScanFilter.lighten:
        return cv.convertScaleAbsAsync(src, alpha: 1.15, beta: 18);
      case ScanFilter.invert:
        return cv.bitwiseNOTAsync(src);
      case ScanFilter.enhance:
        return _enhance(src);
      case ScanFilter.noShadow:
        final gray = await cv.cvtColorAsync(src, cv.COLOR_BGR2GRAY);
        cv.Mat? background;
        try {
          background = await cv.gaussianBlurAsync(gray, (41, 41), 0);
          return await cv.divideAsync(gray, background, scale: 200);
        } finally {
          background?.dispose();
          gray.dispose();
        }
    }
  }

  static Future<cv.Mat> _enhance(cv.Mat src) async {
    final lab = await cv.cvtColorAsync(src, cv.COLOR_BGR2Lab);
    List<cv.Mat> channels = const [];
    cv.Mat? enhanced;
    cv.Mat? merged;
    try {
      channels = (await cv.splitAsync(lab)).toList();
      final clahe = cv.createCLAHE(clipLimit: 3, tileGridSize: (8, 8));
      try {
        enhanced = await clahe.applyAsync(channels[0]);
      } finally {
        clahe.dispose();
      }
      merged = await cv.mergeAsync(cv.VecMat.fromList([
        enhanced,
        channels[1],
        channels[2],
      ]));
      return await cv.cvtColorAsync(merged, cv.COLOR_Lab2BGR);
    } finally {
      merged?.dispose();
      enhanced?.dispose();
      for (final channel in channels) {
        channel.dispose();
      }
      lab.dispose();
    }
  }
}
