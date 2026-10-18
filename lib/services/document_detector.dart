import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:opencv_dart/opencv.dart' as cv;

class DocumentDetector {
  static Future<List<Offset>> detect(String imagePath) async =>
      (await _detectCorners(imagePath, fallback: true))!;

  static Future<List<Offset>?> detectOrNull(String imagePath) =>
      _detectCorners(imagePath, fallback: false);

  static Future<List<Offset>?> _detectCorners(
    String imagePath, {
    required bool fallback,
  }) async {
    final src = await cv.imreadAsync(imagePath);
    cv.Mat? work;
    cv.Mat? gray;
    try {
      final width = src.cols;
      final height = src.rows;
      const targetWidth = 800;
      final scale = width > targetWidth ? width / targetWidth : 1.0;
      if (scale > 1.0) {
        work = await cv.resizeAsync(
          src,
          (targetWidth, (height / scale).round()),
        );
      }
      gray = await cv.cvtColorAsync(work ?? src, cv.COLOR_BGR2GRAY);
      final quad = await _detectQuadInGrayAsync(gray);
      if (quad == null && !fallback) {
        return null;
      }
      final corners = quad == null
          ? _insetBounds(width, height)
          : [for (final p in quad) Offset(p.dx * scale, p.dy * scale)];
      return orderCorners(corners);
    } finally {
      gray?.dispose();
      work?.dispose();
      src.dispose();
    }
  }

  static Future<List<Offset>?> _detectQuadInGrayAsync(
    cv.Mat gray, {
    double minAreaRatio = 0.15,
  }) async {
    cv.Mat? blurred;
    cv.Mat? edges;
    cv.Mat? kernel;
    cv.Mat? closed;
    cv.Contours? contours;
    cv.VecVec4i? hierarchy;
    try {
      blurred = await cv.gaussianBlurAsync(gray, (5, 5), 0);
      edges = await cv.cannyAsync(blurred, 60, 180);
      kernel = await cv.getStructuringElementAsync(cv.MORPH_RECT, (5, 5));
      closed = await cv.morphologyExAsync(edges, cv.MORPH_CLOSE, kernel);
      final (found, links) = await cv.findContoursAsync(
        closed,
        cv.RETR_EXTERNAL,
        cv.CHAIN_APPROX_SIMPLE,
      );
      contours = found;
      hierarchy = links;
      return _bestQuad(found, gray.cols * gray.rows * minAreaRatio);
    } finally {
      contours?.dispose();
      hierarchy?.dispose();
      closed?.dispose();
      kernel?.dispose();
      edges?.dispose();
      blurred?.dispose();
    }
  }

  static List<Offset>? detectQuadInGray(
    cv.Mat gray, {
    double minAreaRatio = 0.15,
  }) {
    final blurred = cv.gaussianBlur(gray, (5, 5), 0);
    final edges = cv.canny(blurred, 60, 180);
    final kernel = cv.getStructuringElement(cv.MORPH_RECT, (5, 5));
    final closed = cv.morphologyEx(edges, cv.MORPH_CLOSE, kernel);
    final (contours, hierarchy) =
        cv.findContours(closed, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
    try {
      return _bestQuad(contours, gray.cols * gray.rows * minAreaRatio);
    } finally {
      contours.dispose();
      hierarchy.dispose();
      closed.dispose();
      kernel.dispose();
      edges.dispose();
      blurred.dispose();
    }
  }

  static List<Offset>? _bestQuad(cv.Contours contours, double minArea) {
    List<Offset>? best;
    var bestArea = 0.0;
    for (final contour in contours) {
      final area = cv.contourArea(contour);
      if (area < minArea || area <= bestArea) {
        continue;
      }
      final perimeter = cv.arcLength(contour, true);
      final approx = cv.approxPolyDP(contour, 0.02 * perimeter, true);
      try {
        if (approx.length == 4) {
          bestArea = area;
          best = [
            for (final p in approx) Offset(p.x.toDouble(), p.y.toDouble()),
          ];
        }
      } finally {
        approx.dispose();
      }
    }
    return best == null ? null : orderCorners(best);
  }

  static List<Offset>? detectNormalizedInLuma(
    Uint8List bytes, {
    required int width,
    required int height,
    required int bytesPerRow,
    int targetWidth = 320,
    double minAreaRatio = 0.35,
  }) {
    if (width <= 0 || height <= 0 || bytesPerRow < width) {
      return null;
    }
    final rows = math.min(height, bytes.length ~/ bytesPerRow);
    if (rows <= 0) {
      return null;
    }
    final vec = cv.VecU8.fromList(
      Uint8List.sublistView(bytes, 0, rows * bytesPerRow),
    );
    final cv.Mat full;
    try {
      full = cv.Mat.fromVec(
        vec,
        rows: rows,
        cols: bytesPerRow,
        type: cv.MatType.CV_8UC1,
      );
    } finally {
      vec.dispose();
    }
    final roi = cv.Rect(0, 0, width, rows);
    cv.Mat? gray;
    cv.Mat? small;
    try {
      final region = full.region(roi);
      gray = region;
      final resized = width > targetWidth
          ? cv.resize(
              region,
              (targetWidth, math.max(1, (rows * targetWidth / width).round())),
              interpolation: cv.INTER_AREA,
            )
          : region;
      small = resized;
      final quad = detectQuadInGray(resized, minAreaRatio: minAreaRatio);
      if (quad == null) {
        return null;
      }
      final w = resized.cols.toDouble();
      final h = resized.rows.toDouble();
      return [for (final p in quad) Offset(p.dx / w, p.dy / h)];
    } finally {
      if (small != null && small != gray) {
        small.dispose();
      }
      gray?.dispose();
      roi.dispose();
      full.dispose();
    }
  }

  static Future<String> applyWarp(
    String imagePath,
    List<Offset> orderedCorners,
  ) async {
    final top = (orderedCorners[1] - orderedCorners[0]).distance;
    final bottom = (orderedCorners[2] - orderedCorners[3]).distance;
    final left = (orderedCorners[3] - orderedCorners[0]).distance;
    final right = (orderedCorners[2] - orderedCorners[1]).distance;
    final outWidth = math.max(1, ((top + bottom) / 2).round());
    final outHeight = math.max(1, ((left + right) / 2).round());

    final srcPts = cv.VecPoint.fromList([
      for (final corner in orderedCorners)
        cv.Point(corner.dx.round(), corner.dy.round()),
    ]);
    final dstPts = cv.VecPoint.fromList([
      cv.Point(0, 0),
      cv.Point(outWidth - 1, 0),
      cv.Point(outWidth - 1, outHeight - 1),
      cv.Point(0, outHeight - 1),
    ]);
    cv.Mat? src;
    cv.Mat? transform;
    cv.Mat? warped;
    try {
      src = await cv.imreadAsync(imagePath);
      transform = await cv.getPerspectiveTransformAsync(srcPts, dstPts);
      warped = await cv.warpPerspectiveAsync(
        src,
        transform,
        (outWidth, outHeight),
      );
      final outPath = imagePath.replaceFirst(
        RegExp(r'\.jpg$', caseSensitive: false),
        '_crop.jpg',
      );
      if (!await cv.imwriteAsync(outPath, warped)) {
        throw StateError('No se pudo guardar el recorte');
      }
      return outPath;
    } finally {
      warped?.dispose();
      transform?.dispose();
      src?.dispose();
      dstPts.dispose();
      srcPts.dispose();
    }
  }

  static List<Offset> orderCorners(List<Offset> points) {
    final sorted = [...points]
      ..sort((a, b) => (a.dx + a.dy).compareTo(b.dx + b.dy));
    final topLeft = sorted.first;
    final bottomRight = sorted.last;
    final rest = points.where((p) => p != topLeft && p != bottomRight).toList()
      ..sort((a, b) => (a.dx - a.dy).compareTo(b.dx - b.dy));
    final bottomLeft = rest.first;
    final topRight = rest.last;
    return [topLeft, topRight, bottomRight, bottomLeft];
  }

  static List<Offset> _insetBounds(int width, int height) {
    final insetX = width * 0.03;
    final insetY = height * 0.03;
    return [
      Offset(insetX, insetY),
      Offset(width - insetX, insetY),
      Offset(width - insetX, height - insetY),
      Offset(insetX, height - insetY),
    ];
  }
}
