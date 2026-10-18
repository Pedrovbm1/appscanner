import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:opencv_dart/opencv.dart' as cv;

class _QuadCandidate {
  _QuadCandidate(this.points, this.area, this.fill);

  final List<cv.Point> points;
  final double area;
  final double fill;
}

class DocumentDetector {
  static const double _cropMinAreaRatio = 0.08;
  static const double _liveMinAreaRatio = 0.12;
  static const int _cropWorkWidth = 800;

  static Future<List<Offset>> detect(String imagePath) async =>
      (await _detectCorners(imagePath, fallback: true))!;

  static Future<List<Offset>?> detectOrNull(String imagePath) =>
      _detectCorners(imagePath, fallback: false);

  static Future<List<Offset>?> _detectCorners(
    String imagePath, {
    required bool fallback,
  }) async {
    List<double>? raw;
    try {
      raw = await Isolate.run(() => _detectInFile(imagePath, fallback));
    } catch (_) {
      raw = _detectInFile(imagePath, fallback);
    }
    if (raw == null) {
      return null;
    }
    return orderCorners([
      for (var i = 0; i < 8; i += 2) Offset(raw[i], raw[i + 1]),
    ]);
  }

  static List<double>? _detectInFile(String imagePath, bool fallback) {
    final src = cv.imread(imagePath);
    cv.Mat? work;
    try {
      if (src.isEmpty) {
        throw StateError('No se pudo leer la imagen');
      }
      final width = src.cols;
      final height = src.rows;
      final scale = width > _cropWorkWidth ? width / _cropWorkWidth : 1.0;
      if (scale > 1.0) {
        work = cv.resize(
          src,
          (_cropWorkWidth, math.max(1, (height / scale).round())),
          interpolation: cv.INTER_AREA,
        );
      }
      final quad = _findDocument(work ?? src);
      if (quad == null) {
        if (!fallback) {
          return null;
        }
        final insetX = width * 0.03;
        final insetY = height * 0.03;
        return [
          insetX,
          insetY,
          width - insetX,
          insetY,
          width - insetX,
          height - insetY,
          insetX,
          height - insetY,
        ];
      }
      return [
        for (final p in quad) ...[p.x * scale, p.y * scale],
      ];
    } finally {
      work?.dispose();
      src.dispose();
    }
  }

  static List<cv.Point>? _findDocument(cv.Mat bgr) {
    final width = bgr.cols;
    final height = bgr.rows;
    final total = (width * height).toDouble();
    final minArea = total * _cropMinAreaRatio;
    final gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY);
    final hsv = cv.cvtColor(bgr, cv.COLOR_BGR2HSV);
    final channels = cv.split(hsv);
    final sat = channels[1];
    final val = channels[2];
    final blur = cv.gaussianBlur(gray, (5, 5), 0);
    final kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
    try {
      final edgeCandidates = <_QuadCandidate>[];
      for (final (lo, hi) in _cannyThresholds(_median(blur))) {
        final edges = cv.canny(blur, lo, hi);
        final dilated = cv.dilate(edges, kernel, iterations: 2);
        try {
          edgeCandidates.addAll(
            _quadsIn(dilated, minArea, total, width, height),
          );
        } finally {
          dilated.dispose();
          edges.dispose();
        }
      }
      final paperCandidates = _paperCandidates(
        val,
        sat,
        minArea,
        total,
        width,
        height,
      );
      _QuadCandidate? best;
      cv.Mat? bestMask;
      var bestScore = double.negativeInfinity;
      for (final candidate in [...edgeCandidates, ...paperCandidates]) {
        final mask = _polygonMask(candidate.points, width, height);
        final score = _contrast(gray, sat, mask) * candidate.fill;
        if (score > bestScore) {
          bestMask?.dispose();
          best = candidate;
          bestMask = mask;
          bestScore = score;
        } else {
          mask.dispose();
        }
      }
      if (best == null || bestMask == null) {
        return null;
      }
      try {
        if (bestScore < 12) {
          final strong = edgeCandidates.where((c) => c.fill > 0.97).toList()
            ..sort((a, b) => b.area.compareTo(a.area));
          return strong.isEmpty ? null : strong.first.points;
        }
        return _refine(best, bestMask, edgeCandidates, width, height).points;
      } finally {
        bestMask.dispose();
      }
    } finally {
      kernel.dispose();
      blur.dispose();
      channels.dispose();
      hsv.dispose();
      gray.dispose();
    }
  }

  static _QuadCandidate _refine(
    _QuadCandidate best,
    cv.Mat bestMask,
    List<_QuadCandidate> edgeCandidates,
    int width,
    int height,
  ) {
    final bestArea = math.max(1, cv.countNonZero(bestMask));
    _QuadCandidate? refined;
    var refinedArea = 0;
    for (final candidate in edgeCandidates) {
      final mask = _polygonMask(candidate.points, width, height);
      final overlap = cv.bitwiseAND(mask, bestMask);
      try {
        final inter = cv.countNonZero(overlap);
        final area = cv.countNonZero(mask);
        if (inter / bestArea > 0.92 &&
            area <= bestArea * 1.35 &&
            area > refinedArea) {
          refined = candidate;
          refinedArea = area;
        }
      } finally {
        overlap.dispose();
        mask.dispose();
      }
    }
    return refined ?? best;
  }

  static List<_QuadCandidate> _paperCandidates(
    cv.Mat val,
    cv.Mat sat,
    double minArea,
    double total,
    int width,
    int height,
  ) {
    final score = cv.addWeighted(val, 1.0, sat, -1.2, 0);
    final smooth = cv.gaussianBlur(score, (7, 7), 0);
    final (_, paper) = cv.threshold(
      smooth,
      0,
      255,
      cv.THRESH_BINARY | cv.THRESH_OTSU,
    );
    final openKernel = cv.getStructuringElement(cv.MORPH_RECT, (5, 5));
    final closeKernel = cv.getStructuringElement(cv.MORPH_RECT, (9, 9));
    final opened = cv.morphologyEx(paper, cv.MORPH_OPEN, openKernel);
    final closed = cv.morphologyEx(opened, cv.MORPH_CLOSE, closeKernel);
    try {
      return _quadsIn(closed, minArea, total, width, height);
    } finally {
      closed.dispose();
      opened.dispose();
      closeKernel.dispose();
      openKernel.dispose();
      paper.dispose();
      smooth.dispose();
      score.dispose();
    }
  }

  static List<(double, double)> _cannyThresholds(double median) => [
        (math.max(5.0, 0.33 * median), math.max(15.0, 0.665 * median)),
        (60.0, 180.0),
        (math.max(5.0, 0.165 * median), math.max(15.0, 0.33 * median)),
      ];

  static double _median(cv.Mat gray) {
    final data = gray.data;
    if (data.isEmpty) {
      return 128;
    }
    final histogram = List<int>.filled(256, 0);
    for (final v in data) {
      histogram[v]++;
    }
    final half = data.length / 2;
    var count = 0;
    for (var i = 0; i < 256; i++) {
      count += histogram[i];
      if (count >= half) {
        return i.toDouble();
      }
    }
    return 128;
  }

  static List<_QuadCandidate> _quadsIn(
    cv.Mat binary,
    double minArea,
    double total,
    int width,
    int height,
  ) {
    final out = <_QuadCandidate>[];
    final (contours, hierarchy) = cv.findContours(
      binary,
      cv.RETR_LIST,
      cv.CHAIN_APPROX_SIMPLE,
    );
    try {
      final indexed = <(int, double)>[
        for (var i = 0; i < contours.length; i++)
          (i, cv.contourArea(contours[i])),
      ]..sort((a, b) => b.$2.compareTo(a.$2));
      final margin = 0.01 * math.min(width, height);
      for (final (index, contourArea) in indexed.take(12)) {
        if (contourArea < minArea || contourArea > total * 0.95) {
          continue;
        }
        final candidate = _quadFromContour(
          contours[index],
          contourArea,
          minArea,
          margin,
          width,
          height,
        );
        if (candidate != null) {
          out.add(candidate);
        }
      }
    } finally {
      contours.dispose();
      hierarchy.dispose();
    }
    return out;
  }

  static _QuadCandidate? _quadFromContour(
    cv.VecPoint contour,
    double contourArea,
    double minArea,
    double margin,
    int width,
    int height,
  ) {
    final hullMat = cv.convexHull(contour);
    final hull = cv.VecPoint.fromMat(hullMat);
    try {
      final perimeter = cv.arcLength(hull, true);
      for (final eps in const [0.015, 0.02, 0.03, 0.04, 0.05, 0.06, 0.08]) {
        final approx = cv.approxPolyDP(hull, eps * perimeter, true);
        try {
          if (approx.length < 4) {
            return null;
          }
          if (approx.length != 4 || !cv.isContourConvex(approx)) {
            continue;
          }
          final quadArea = cv.contourArea(approx);
          if (quadArea < minArea) {
            return null;
          }
          final points = [for (final p in approx) cv.Point(p.x, p.y)];
          final touching = points
              .where(
                (p) =>
                    p.x <= margin ||
                    p.y <= margin ||
                    p.x >= width - 1 - margin ||
                    p.y >= height - 1 - margin,
              )
              .length;
          if (touching >= 2) {
            return null;
          }
          return _QuadCandidate(
            points,
            quadArea,
            math.min(1.0, contourArea / quadArea),
          );
        } finally {
          approx.dispose();
        }
      }
      return null;
    } finally {
      hull.dispose();
      hullMat.dispose();
    }
  }

  static cv.Mat _polygonMask(List<cv.Point> points, int width, int height) {
    final mask = cv.Mat.zeros(height, width, cv.MatType.CV_8UC1);
    final polygon = cv.VecVecPoint.fromList([points]);
    try {
      cv.fillPoly(mask, polygon, cv.Scalar.all(255));
    } finally {
      polygon.dispose();
    }
    return mask;
  }

  static double _contrast(cv.Mat gray, cv.Mat? sat, cv.Mat mask) {
    final outside = cv.bitwiseNOT(mask);
    try {
      final inside = cv.mean(gray, mask: mask).val1;
      final out = cv.mean(gray, mask: outside).val1;
      var satTerm = 0.0;
      if (sat != null) {
        final satOut = cv.mean(sat, mask: outside).val1;
        final satIn = cv.mean(sat, mask: mask).val1;
        satTerm = math.max(0.0, satOut - satIn) * 0.5;
      }
      return inside - out + satTerm;
    } finally {
      outside.dispose();
    }
  }

  static List<Offset>? detectQuadInGray(
    cv.Mat gray, {
    double minAreaRatio = _liveMinAreaRatio,
  }) {
    final width = gray.cols;
    final height = gray.rows;
    final total = (width * height).toDouble();
    final minArea = total * math.min(minAreaRatio, _liveMinAreaRatio);
    final blur = cv.gaussianBlur(gray, (5, 5), 0);
    final kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
    try {
      final candidates = <_QuadCandidate>[];
      for (final (lo, hi) in _cannyThresholds(_median(blur))) {
        final edges = cv.canny(blur, lo, hi);
        final dilated = cv.dilate(edges, kernel);
        try {
          candidates.addAll(_quadsIn(dilated, minArea, total, width, height));
        } finally {
          dilated.dispose();
          edges.dispose();
        }
      }
      _QuadCandidate? best;
      var bestScore = double.negativeInfinity;
      for (final candidate in candidates) {
        final mask = _polygonMask(candidate.points, width, height);
        try {
          final score = _contrast(gray, null, mask) * candidate.fill +
              2 * candidate.area / total;
          if (score > bestScore) {
            best = candidate;
            bestScore = score;
          }
        } finally {
          mask.dispose();
        }
      }
      if (best == null || bestScore <= 8) {
        return null;
      }
      return orderCorners([
        for (final p in best.points) Offset(p.x.toDouble(), p.y.toDouble()),
      ]);
    } finally {
      kernel.dispose();
      blur.dispose();
    }
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
}
