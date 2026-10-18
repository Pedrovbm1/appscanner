import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../models/pdf_options.dart';
import '../models/scan_session.dart';
import 'ocr_service.dart';
import 'page_editor.dart';

class PdfWord {
  const PdfWord({
    required this.text,
    required this.left,
    required this.top,
    required this.height,
  });

  final String text;
  final double left;
  final double top;
  final double height;
}

class PdfPageInput {
  const PdfPageInput({
    required this.bytes,
    this.imageWidth = 0,
    this.imageHeight = 0,
    this.ocrText,
    this.ocrWords,
  });

  final Uint8List bytes;
  final int imageWidth;
  final int imageHeight;
  final String? ocrText;
  final List<PdfWord>? ocrWords;
}

class PdfJob {
  const PdfJob({required this.pages, this.watermark, this.password});

  final List<PdfPageInput> pages;
  final String? watermark;
  final String? password;
}

class PdfService {
  static const _maxSide = 2000;
  static const _jpegQuality = 72;
  static const _margin = 16.0;
  static const _wordFontRatio = 0.8;
  static const _minWordFontSize = 2.0;
  static const _maxWordFontSize = 40.0;
  static const _maxTitleLength = 60;
  static final _unsafeTitleChars = RegExp(r'[^A-Za-z0-9áéíóúÁÉÍÓÚñÑüÜ_-]');

  static Future<File> buildPdf(
    List<ScanPage> pages, {
    PdfOptions? options,
    String? title,
  }) async {
    final settings = options ?? const PdfOptions();
    final inputs = <PdfPageInput>[];
    for (final page in pages) {
      final bytes = settings.compress
          ? await _compressedBytes(page.currentPath)
          : await File(page.currentPath).readAsBytes();
      inputs.add(
        settings.includeOcr
            ? await _pageInput(bytes, page.currentPath)
            : PdfPageInput(bytes: bytes),
      );
    }

    final sanitizedWatermark = _sanitize(settings.watermark).trim();
    final job = PdfJob(
      pages: inputs,
      watermark: sanitizedWatermark.isEmpty ? null : sanitizedWatermark,
      password: settings.protect && settings.password.isNotEmpty
          ? settings.password
          : null,
    );

    final bytes = await _renderInBackground(job);

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}${fileName(null, title)}');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<Uint8List> _renderInBackground(PdfJob job) =>
      Isolate.run(() => _renderPdf(job));

  static Future<Uint8List> _renderPdf(PdfJob job) async {
    Uint8List bytes;
    try {
      bytes = await _render(job, withText: true);
    } catch (_) {
      bytes = await _render(job, withText: false);
    }
    final password = job.password;
    if (password != null && password.isNotEmpty) {
      bytes = await _encrypt(bytes, password);
    }
    return bytes;
  }

  static Future<PdfPageInput> _pageInput(
    Uint8List bytes,
    String imagePath,
  ) async {
    final ocr = await _readOcrJson(imagePath);
    if (ocr != null) {
      return PdfPageInput(
        bytes: bytes,
        imageWidth: ocr.width,
        imageHeight: ocr.height,
        ocrWords: [
          for (final word in ocr.words)
            PdfWord(
              text: word.text,
              left: word.box.left,
              top: word.box.top,
              height: word.box.height,
            ),
        ],
      );
    }
    return PdfPageInput(bytes: bytes, ocrText: await _readOcrText(imagePath));
  }

  static Future<Uint8List> _compressedBytes(String path) async {
    final src = await cv.imreadAsync(path);
    try {
      if (src.isEmpty) {
        return await File(path).readAsBytes();
      }
      final longest = math.max(src.cols, src.rows);
      cv.Mat? resized;
      try {
        if (longest > _maxSide) {
          final scale = _maxSide / longest;
          resized = await cv.resizeAsync(src, (
            math.max(1, (src.cols * scale).round()),
            math.max(1, (src.rows * scale).round()),
          ), interpolation: cv.INTER_AREA);
        }
        final params = cv.VecI32.fromList([
          cv.IMWRITE_JPEG_QUALITY,
          _jpegQuality,
        ]);
        try {
          final (ok, encoded) = await cv.imencodeAsync(
            '.jpg',
            resized ?? src,
            params: params,
          );
          return ok && encoded.isNotEmpty
              ? encoded
              : await File(path).readAsBytes();
        } finally {
          params.dispose();
        }
      } finally {
        resized?.dispose();
      }
    } finally {
      src.dispose();
    }
  }

  static Future<Uint8List> _encrypt(Uint8List bytes, String password) async {
    final document = sf.PdfDocument(inputBytes: bytes);
    try {
      document.security.userPassword = password;
      document.security.ownerPassword = password;
      document.security.algorithm = sf.PdfEncryptionAlgorithm.aesx256Bit;
      return Uint8List.fromList(await document.save());
    } finally {
      document.dispose();
    }
  }

  static String fileName([DateTime? time, String? title]) {
    final safeTitle = _safeTitle(title);
    if (safeTitle.isNotEmpty) {
      return '$safeTitle.pdf';
    }
    final now = time ?? DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final date = '${now.year}${two(now.month)}${two(now.day)}';
    return 'Escaneo_${date}_${two(now.hour)}${two(now.minute)}.pdf';
  }

  static String _safeTitle(String? title) {
    if (title == null) {
      return '';
    }
    String tidy(String value) => value
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    var name = tidy(
      title.trim().replaceAll(' ', '_').replaceAll(_unsafeTitleChars, '_'),
    );
    if (name.length > _maxTitleLength) {
      name = tidy(name.substring(0, _maxTitleLength));
    }
    return name;
  }

  static Future<Uint8List> _render(PdfJob job, {required bool withText}) {
    final watermark = job.watermark;
    final doc = pw.Document();
    for (final page in job.pages) {
      final image = pw.MemoryImage(page.bytes);
      final text = withText ? page.ocrText : null;
      final words = withText ? page.ocrWords : null;
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(_margin),
          build: (_) => pw.Stack(
            children: [
              pw.Center(
                child: pw.Stack(
                  children: [
                    pw.Image(image, fit: pw.BoxFit.contain),
                    if (text != null)
                      pw.Positioned.fill(
                        child: pw.Opacity(
                          opacity: 0,
                          child: pw.Text(
                            text,
                            style: const pw.TextStyle(fontSize: 6),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (words != null)
                pw.Positioned.fill(child: _wordLayer(page, words)),
              if (watermark != null)
                pw.Positioned.fill(child: _watermark(watermark)),
            ],
          ),
        ),
      );
    }
    return doc.save();
  }

  static pw.Widget _wordLayer(PdfPageInput page, List<PdfWord> words) {
    const format = PdfPageFormat.a4;
    final boxWidth = format.width - 2 * _margin;
    final boxHeight = format.height - 2 * _margin;
    final scale = math.min(
      boxWidth / page.imageWidth,
      boxHeight / page.imageHeight,
    );
    final offsetX = (boxWidth - page.imageWidth * scale) / 2;
    final offsetY = (boxHeight - page.imageHeight * scale) / 2;
    final children = <pw.Widget>[];
    for (final word in words) {
      final text = _sanitize(word.text).replaceAll('\n', ' ').trim();
      if (text.isEmpty) {
        continue;
      }
      final fontSize = (word.height * scale * _wordFontRatio)
          .clamp(_minWordFontSize, _maxWordFontSize)
          .toDouble();
      children.add(
        pw.Positioned(
          left: offsetX + word.left * scale,
          top: offsetY + word.top * scale,
          child: pw.Text(text, style: pw.TextStyle(fontSize: fontSize)),
        ),
      );
    }
    return pw.Opacity(
      opacity: 0,
      child: pw.Stack(overflow: pw.Overflow.visible, children: children),
    );
  }

  static pw.Widget _watermark(String text) {
    final fontSize = (600 / text.length).clamp(24, 60).toDouble();
    return pw.Center(
      child: pw.Transform.rotate(
        angle: math.pi / 4,
        child: pw.Opacity(
          opacity: 0.15,
          child: pw.Text(
            text,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey,
            ),
          ),
        ),
      ),
    );
  }

  static Future<OcrResult?> _readOcrJson(String imagePath) async {
    final jsonPath = PageEditor.ocrJsonPath(imagePath);
    if (jsonPath == imagePath) {
      return null;
    }
    try {
      final file = File(jsonPath);
      if (!await file.exists()) {
        return null;
      }
      final ocr = OcrResult.fromJson(jsonDecode(await file.readAsString()));
      return ocr != null && ocr.hasLayout ? ocr : null;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _readOcrText(String imagePath) async {
    final txtPath = PageEditor.ocrTextPath(imagePath);
    if (txtPath == imagePath) {
      return null;
    }
    final file = File(txtPath);
    if (!await file.exists()) {
      return null;
    }
    final text = _sanitize(await file.readAsString());
    return text.trim().isEmpty ? null : text;
  }

  static const _replacements = {
    0x2018: "'",
    0x2019: "'",
    0x201C: '"',
    0x201D: '"',
    0x2013: '-',
    0x2014: '-',
    0x2026: '...',
    0x2022: '-',
  };

  static String _sanitize(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      if (rune == 0x0A) {
        buffer.writeCharCode(rune);
      } else if (rune == 0x09 || rune == 0x0D) {
        buffer.write(' ');
      } else if ((rune >= 0x20 && rune < 0x7F) ||
          (rune >= 0xA0 && rune <= 0xFF)) {
        buffer.writeCharCode(rune);
      } else if (rune > 0xFF) {
        buffer.write(_replacements[rune] ?? '?');
      }
    }
    return buffer.toString();
  }
}
