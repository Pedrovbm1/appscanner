import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ocr_service.dart';
import '../services/page_editor.dart';

class OcrScreen extends StatefulWidget {
  const OcrScreen({super.key, required this.image});

  final File image;

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  String? _text;
  String? _error;

  @override
  void initState() {
    super.initState();
    _recognize();
  }

  Future<void> _recognize() async {
    try {
      final imagePath = widget.image.path;
      final result = await OcrService.recognizeDetailed(imagePath);
      final text = result.text;
      final txtPath = PageEditor.ocrTextPath(imagePath);
      if (txtPath != imagePath) {
        await File(txtPath).writeAsString(text);
      }
      final jsonPath = PageEditor.ocrJsonPath(imagePath);
      if (jsonPath != imagePath) {
        final jsonFile = File(jsonPath);
        if (result.hasLayout) {
          await jsonFile.writeAsString(jsonEncode(result.toJson()));
        } else if (await jsonFile.exists()) {
          await jsonFile.delete();
        }
      }
      if (!mounted) {
        return;
      }
      setState(() => _text = text);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _error = 'No se pudo reconocer el texto de esta página.');
    }
  }

  Future<void> _copy() async {
    final text = _text;
    if (text == null || text.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Texto copiado al portapapeles.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    final error = _error;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Texto reconocido'),
        actions: [
          IconButton(
            onPressed: (text == null || text.isEmpty) ? null : _copy,
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: 'Copiar todo',
          ),
        ],
      ),
      body: error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(error, textAlign: TextAlign.center),
              ),
            )
          : text == null
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Reconociendo texto…'),
                    ],
                  ),
                )
              : text.trim().isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No se encontró texto en esta página.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: SelectableText(
                        text,
                        style: const TextStyle(fontSize: 15, height: 1.45),
                      ),
                    ),
    );
  }
}
