import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

class ImportService {
  static const double pdfMaxDimension = 2000;

  static Future<Directory> createSessionDir({String? stamp}) async {
    final docs = await getApplicationDocumentsDirectory();
    final name = stamp ?? DateTime.now().millisecondsSinceEpoch.toString();
    final sessionDir = Directory(
      '${docs.path}${Platform.pathSeparator}scans${Platform.pathSeparator}$name',
    );
    await sessionDir.create(recursive: true);
    return sessionDir;
  }

  static String pagePath(Directory sessionDir, int number) =>
      '${sessionDir.path}${Platform.pathSeparator}page_$number.jpg';

  static Future<File> importImage(String sourcePath, String destPath) async {
    final mat = await cv.imreadAsync(sourcePath);
    try {
      if (mat.isEmpty) {
        throw const FileSystemException('No se pudo leer la imagen');
      }
      final saved = await cv.imwriteAsync(destPath, mat);
      if (!saved) {
        throw FileSystemException('No se pudo guardar la imagen', destPath);
      }
    } finally {
      mat.dispose();
    }
    return File(destPath);
  }

  static Future<PdfDocument> openPdf(PlatformFile file) async {
    final path = file.path;
    if (path != null) {
      return PdfDocument.openFile(path);
    }
    return PdfDocument.openData(await file.readAsBytes());
  }

  static Future<void> renderPdfPages(
    PdfDocument document, {
    required String Function(int pageNumber) pathFor,
    required void Function(int pageNumber, String path) onPageSaved,
  }) async {
    for (var number = 1; number <= document.pagesCount; number++) {
      final page = await document.getPage(number);
      try {
        final scale =
            pdfMaxDimension / math.max(page.width, page.height);
        final image = await page.render(
          width: (page.width * scale).roundToDouble(),
          height: (page.height * scale).roundToDouble(),
          format: PdfPageImageFormat.jpeg,
          backgroundColor: '#FFFFFF',
          quality: 90,
        );
        if (image == null) {
          throw StateError('No se pudo renderizar la página $number');
        }
        final path = pathFor(number);
        await File(path).writeAsBytes(image.bytes, flush: true);
        onPageSaved(number, path);
      } finally {
        await page.close();
      }
    }
  }
}
