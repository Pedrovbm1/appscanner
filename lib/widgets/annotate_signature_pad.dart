import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'annotate_painter.dart';

class AnnotateSignaturePad extends StatefulWidget {
  const AnnotateSignaturePad({super.key});

  @override
  State<AnnotateSignaturePad> createState() => _AnnotateSignaturePadState();
}

class _AnnotateSignaturePadState extends State<AnnotateSignaturePad> {
  static const _strokeWidth = 4.0;
  static const _padding = 12.0;
  static const _pixelRatio = 3.0;

  final List<List<Offset>> _strokes = [];
  bool _rendering = false;

  void _onPanStart(DragStartDetails details) {
    setState(() => _strokes.add([details.localPosition]));
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_strokes.isEmpty) {
      return;
    }
    setState(() => _strokes.last.add(details.localPosition));
  }

  void _onTapUp(TapUpDetails details) {
    setState(() => _strokes.add([details.localPosition]));
  }

  void _clear() {
    setState(_strokes.clear);
  }

  Future<void> _confirm() async {
    if (_strokes.isEmpty || _rendering) {
      return;
    }
    setState(() => _rendering = true);
    try {
      final image = await _render();
      if (!mounted) {
        image.dispose();
        return;
      }
      Navigator.of(context).pop(image);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _rendering = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo crear la firma.')),
      );
    }
  }

  Future<ui.Image> _render() async {
    final first = _strokes.first.first;
    var bounds = Rect.fromPoints(first, first);
    for (final stroke in _strokes) {
      for (final point in stroke) {
        bounds = bounds.expandToInclude(Rect.fromPoints(point, point));
      }
    }
    bounds = bounds.inflate(_strokeWidth / 2 + _padding);
    final width = math.max(1, (bounds.width * _pixelRatio).ceil());
    final height = math.max(1, (bounds.height * _pixelRatio).ceil());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(_pixelRatio);
    canvas.translate(-bounds.left, -bounds.top);
    for (final stroke in _strokes) {
      AnnotationPainter.paintStroke(
        canvas,
        stroke,
        _strokeWidth,
        AnnotationPainter.inkColor,
      );
    }
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        automaticallyImplyLeading: false,
        title: const Text('Firma'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black26),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      dragStartBehavior: DragStartBehavior.down,
                      onPanStart: _rendering ? null : _onPanStart,
                      onPanUpdate: _rendering ? null : _onPanUpdate,
                      onTapUp: _rendering ? null : _onTapUp,
                      child: CustomPaint(
                        painter: _SignaturePadPainter(_strokes, _strokeWidth),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Text(
              'Firma dentro del recuadro',
              style: TextStyle(color: Colors.black54),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _rendering || _strokes.isEmpty ? null : _clear,
                    child: const Text('Borrar'),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed:
                        _rendering ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _rendering || _strokes.isEmpty ? null : _confirm,
                    child: _rendering
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Usar firma'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignaturePadPainter extends CustomPainter {
  _SignaturePadPainter(this.strokes, this.strokeWidth);

  final List<List<Offset>> strokes;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      AnnotationPainter.paintStroke(
        canvas,
        stroke,
        strokeWidth,
        AnnotationPainter.inkColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePadPainter oldDelegate) => true;
}
