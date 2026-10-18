import 'dart:ui' as ui;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrWord {
  const OcrWord({required this.text, required this.box});

  final String text;
  final ui.Rect box;

  Map<String, Object> toJson() => {
    'text': text,
    'l': box.left.round(),
    't': box.top.round(),
    'r': box.right.round(),
    'b': box.bottom.round(),
  };

  static OcrWord? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final text = json['text'];
    final l = json['l'];
    final t = json['t'];
    final r = json['r'];
    final b = json['b'];
    if (text is! String || l is! num || t is! num || r is! num || b is! num) {
      return null;
    }
    if (r <= l || b <= t) {
      return null;
    }
    return OcrWord(
      text: text,
      box: ui.Rect.fromLTRB(
        l.toDouble(),
        t.toDouble(),
        r.toDouble(),
        b.toDouble(),
      ),
    );
  }
}

class OcrResult {
  const OcrResult({
    required this.text,
    required this.width,
    required this.height,
    required this.words,
  });

  final String text;
  final int width;
  final int height;
  final List<OcrWord> words;

  bool get hasLayout => width > 0 && height > 0 && words.isNotEmpty;

  Map<String, Object> toJson() => {
    'width': width,
    'height': height,
    'words': [for (final word in words) word.toJson()],
  };

  static OcrResult? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final width = json['width'];
    final height = json['height'];
    final rawWords = json['words'];
    if (width is! num || height is! num || rawWords is! List) {
      return null;
    }
    final words = [for (final raw in rawWords) ?OcrWord.fromJson(raw)];
    return OcrResult(
      text: words.map((word) => word.text).join(' '),
      width: width.round(),
      height: height.round(),
      words: words,
    );
  }
}

class OcrService {
  static Future<String> recognize(String imagePath) async {
    final result = await _process(imagePath);
    return result.text;
  }

  static Future<OcrResult> recognizeDetailed(String imagePath) async {
    final result = await _process(imagePath);
    final (width, height) = await _imageSize(imagePath);
    final words = <OcrWord>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        for (final element in line.elements) {
          final text = element.text.trim();
          if (text.isEmpty) {
            continue;
          }
          words.add(OcrWord(text: text, box: element.boundingBox));
        }
      }
    }
    return OcrResult(
      text: result.text,
      width: width,
      height: height,
      words: words,
    );
  }

  static Future<RecognizedText> _process(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final input = InputImage.fromFilePath(imagePath);
      return await recognizer.processImage(input);
    } finally {
      await recognizer.close();
    }
  }

  static Future<(int, int)> _imageSize(String imagePath) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromFilePath(imagePath);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      return (descriptor.width, descriptor.height);
    } catch (_) {
      return (0, 0);
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}
