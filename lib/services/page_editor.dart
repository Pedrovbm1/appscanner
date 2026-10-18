import 'dart:io';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../models/scan_session.dart';

class PageEditor {
  static final _rotationSuffix = RegExp(r'_r(0|90|180|270)$');
  static final _imageExtension = RegExp(
    r'\.(jpe?g|png)$',
    caseSensitive: false,
  );
  static final _annotatedSuffix = RegExp(r'_annotated$');

  static String ocrTextPath(String imagePath) =>
      imagePath.replaceFirst(_imageExtension, '_ocr.txt');

  static String ocrJsonPath(String imagePath) =>
      imagePath.replaceFirst(_imageExtension, '_ocr.json');

  static Future<void> deleteOcrSidecars(String imagePath) async {
    for (final path in [ocrTextPath(imagePath), ocrJsonPath(imagePath)]) {
      if (path == imagePath) {
        continue;
      }
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

  static String annotatedPath(String path) {
    final separator = path.lastIndexOf(RegExp(r'[/\\]'));
    final dot = path.lastIndexOf('.');
    final stem = dot > separator + 1 ? path.substring(0, dot) : path;
    final directory = stem.substring(0, separator + 1);
    final name = stem
        .substring(separator + 1)
        .replaceFirst(_annotatedSuffix, '');
    return '$directory${name}_annotated.png';
  }

  static Future<String> rotateClockwise(ScanPage page) async {
    final source = page.currentPath;
    final target = rotatedPath(source, 90);
    final src = await cv.imreadAsync(source);
    try {
      if (src.isEmpty) {
        throw StateError('No se pudo leer la página');
      }
      final rotated = await cv.rotateAsync(src, cv.ROTATE_90_CLOCKWISE);
      try {
        final saved = await cv.imwriteAsync(target, rotated);
        if (!saved) {
          throw StateError('No se pudo guardar la página');
        }
      } finally {
        rotated.dispose();
      }
    } finally {
      src.dispose();
    }
    return target;
  }

  static String rotatedPath(String path, int degrees) {
    final separator = path.lastIndexOf(RegExp(r'[/\\]'));
    final dot = path.lastIndexOf('.');
    final hasExtension = dot > separator + 1;
    final stem = hasExtension ? path.substring(0, dot) : path;
    final extension = hasExtension ? path.substring(dot) : '.jpg';
    final match = _rotationSuffix.firstMatch(stem.substring(separator + 1));
    final current = match == null ? 0 : int.parse(match.group(1)!);
    final base = match == null
        ? stem
        : stem.substring(0, stem.length - match.group(0)!.length);
    final angle = (current + degrees) % 360;
    return '${base}_r$angle$extension';
  }
}
