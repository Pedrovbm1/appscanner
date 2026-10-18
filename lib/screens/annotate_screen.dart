import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/annotation.dart';
import '../models/scan_session.dart';
import '../services/page_editor.dart';
import '../services/session_store.dart';
import '../widgets/annotate_painter.dart';
import '../widgets/annotate_signature_pad.dart';
import '../widgets/annotate_text_dialog.dart';

enum AnnotateTool { text, highlight, pen, signature }

enum _DragMode { none, move, resize, pinch, pen, highlight }

class AnnotateScreen extends StatefulWidget {
  const AnnotateScreen({
    super.key,
    required this.session,
    required this.page,
  });

  final ScanSession session;
  final ScanPage page;

  @override
  State<AnnotateScreen> createState() => _AnnotateScreenState();
}

class _AnnotateScreenState extends State<AnnotateScreen> {
  static const _maxSide = 3000;
  static const _textSize = 18.0;
  static const _strokeWidth = 4.0;
  static const _handleRadius = 24.0;
  static const _hitSlop = 8.0;
  static const _minHighlight = 8.0;
  static const _signatureWidth = 0.3;
  static const _signatureMargin = 0.04;
  static const _minSignatureWidth = 0.1;

  final List<Annotation> _annotations = [];
  ui.Image? _image;
  bool _loadFailed = false;
  bool _saving = false;
  AnnotateTool _tool = AnnotateTool.text;
  Annotation? _selected;
  double _displayScale = 1;

  _DragMode _mode = _DragMode.none;
  Annotation? _active;
  Offset? _downPosition;
  Offset _dragStart = Offset.zero;
  Offset _originOffset = Offset.zero;
  Rect _originRect = Rect.zero;
  Offset _anchor = Offset.zero;
  double _pinchBaseScale = 1;

  double get _imageWidth => _image!.width.toDouble();

  double get _imageHeight => _image!.height.toDouble();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final annotation in _annotations) {
      if (annotation is SignatureAnnotation) {
        annotation.image.dispose();
      }
    }
    _image?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.page.currentPath).readAsBytes();
      final image = await decodeImageFromList(bytes);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
    } catch (_) {
      if (mounted) {
        setState(() => _loadFailed = true);
      }
    }
  }

  Offset _toImage(Offset local) => local / _displayScale;

  Offset _clampPoint(Offset point) => Offset(
        point.dx.clamp(0.0, _imageWidth),
        point.dy.clamp(0.0, _imageHeight),
      );

  Rect _clampCenter(Rect rect) {
    final center = _clampPoint(rect.center);
    return Rect.fromCenter(
      center: center,
      width: rect.width,
      height: rect.height,
    );
  }

  bool _contains(Annotation annotation, Offset point) {
    final bounds = AnnotationPainter.boundsOf(annotation);
    if (bounds == null) {
      return false;
    }
    return bounds.inflate(_hitSlop / _displayScale).contains(point);
  }

  Annotation? _hitTest(Offset point) {
    for (final annotation in _annotations.reversed) {
      if (_contains(annotation, point)) {
        return annotation;
      }
    }
    return null;
  }

  Offset? _resizeAnchor(HighlightAnnotation annotation, Offset point) {
    final rect = annotation.rect;
    final corners = [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ];
    final radius = _handleRadius / _displayScale;
    int? nearest;
    var best = double.infinity;
    for (var i = 0; i < corners.length; i++) {
      final distance = (corners[i] - point).distance;
      if (distance <= radius && distance < best) {
        best = distance;
        nearest = i;
      }
    }
    if (nearest == null) {
      return null;
    }
    return corners[(nearest + 2) % corners.length];
  }

  Future<void> _onTapUp(TapUpDetails details) async {
    if (_saving) {
      return;
    }
    final point = _toImage(details.localPosition);
    final hit = _hitTest(point);
    if (hit != null) {
      setState(() => _selected = hit);
      return;
    }
    setState(() {
      _selected = null;
      if (_tool == AnnotateTool.pen) {
        _annotations.add(
          PenAnnotation(
            points: [_clampPoint(point)],
            width: _strokeWidth / _displayScale,
          ),
        );
      }
    });
    if (_tool == AnnotateTool.text) {
      await _addText(point);
    }
  }

  Future<void> _addText(Offset point) async {
    final scale = _displayScale;
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const AnnotateTextDialog(),
    );
    if (!mounted || text == null || text.isEmpty) {
      return;
    }
    final annotation = TextAnnotation(
      offset: point,
      text: text,
      fontSize: _textSize / scale,
    );
    final height = annotation.bounds.height;
    annotation.offset = _clampPoint(point - Offset(0, height / 2));
    setState(() {
      _annotations.add(annotation);
      _selected = annotation;
    });
  }

  void _onPointerDown(PointerDownEvent event) {
    _downPosition = event.localPosition;
  }

  void _onScaleStart(ScaleStartDetails details) {
    final local = _downPosition ?? details.localFocalPoint;
    _downPosition = null;
    _mode = _DragMode.none;
    _active = null;
    if (_saving) {
      return;
    }
    if (details.pointerCount > 1) {
      _beginPinch(details.localFocalPoint, 1);
      return;
    }
    final point = _toImage(local);
    final selected = _selected;
    if (selected is HighlightAnnotation) {
      final anchor = _resizeAnchor(selected, point);
      if (anchor != null) {
        _mode = _DragMode.resize;
        _active = selected;
        _anchor = anchor;
        return;
      }
    }
    final Annotation? hit;
    if (selected != null && _contains(selected, point)) {
      hit = selected;
    } else if (_tool == AnnotateTool.pen) {
      hit = null;
    } else {
      hit = _hitTest(point);
    }
    if (hit != null) {
      _beginMove(hit, point);
      return;
    }
    switch (_tool) {
      case AnnotateTool.pen:
        final stroke = PenAnnotation(
          points: [_clampPoint(point)],
          width: _strokeWidth / _displayScale,
        );
        _mode = _DragMode.pen;
        _active = stroke;
        setState(() {
          _annotations.add(stroke);
          _selected = null;
        });
      case AnnotateTool.highlight:
        final start = _clampPoint(point);
        final highlight = HighlightAnnotation(
          rect: Rect.fromPoints(start, start),
        );
        _mode = _DragMode.highlight;
        _active = highlight;
        _anchor = start;
        setState(() {
          _annotations.add(highlight);
          _selected = null;
        });
      case AnnotateTool.text:
      case AnnotateTool.signature:
        if (_selected != null) {
          setState(() => _selected = null);
        }
    }
  }

  void _beginMove(Annotation annotation, Offset point) {
    final bounds = AnnotationPainter.boundsOf(annotation);
    if (bounds == null) {
      return;
    }
    _mode = _DragMode.move;
    _active = annotation;
    _dragStart = point;
    _originRect = bounds;
    if (annotation is TextAnnotation) {
      _originOffset = annotation.offset;
    }
    setState(() => _selected = annotation);
  }

  void _beginPinch(Offset localFocalPoint, double scale) {
    final selected = _selected;
    if (selected is! SignatureAnnotation) {
      _mode = _DragMode.none;
      _active = null;
      return;
    }
    _mode = _DragMode.pinch;
    _active = selected;
    _originRect = selected.rect;
    _dragStart = _toImage(localFocalPoint);
    _pinchBaseScale = scale;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_saving) {
      return;
    }
    if (details.pointerCount > 1 && _mode != _DragMode.pinch) {
      _endGesture();
      _beginPinch(details.localFocalPoint, details.scale);
    }
    if (_mode == _DragMode.none) {
      return;
    }
    final point = _toImage(details.localFocalPoint);
    setState(() => _applyDrag(point, details.scale));
  }

  void _applyDrag(Offset point, double scale) {
    final delta = point - _dragStart;
    switch ((_mode, _active)) {
      case (_DragMode.move, final TextAnnotation a):
        a.offset = _clampPoint(_originOffset + delta);
      case (_DragMode.move, final HighlightAnnotation a):
        a.rect = _clampCenter(_originRect.shift(delta));
      case (_DragMode.move, final SignatureAnnotation a):
        a.rect = _clampCenter(_originRect.shift(delta));
      case (_DragMode.resize, final HighlightAnnotation a):
        a.rect = Rect.fromPoints(_anchor, _clampPoint(point));
      case (_DragMode.highlight, final HighlightAnnotation a):
        a.rect = Rect.fromPoints(_anchor, _clampPoint(point));
      case (_DragMode.pen, final PenAnnotation a):
        a.points.add(_clampPoint(point));
      case (_DragMode.pinch, final SignatureAnnotation a):
        final ratio = _pinchBaseScale == 0 ? 1.0 : scale / _pinchBaseScale;
        final width = (_originRect.width * ratio).clamp(
          _imageWidth * _minSignatureWidth,
          _imageWidth,
        );
        a.rect = _clampCenter(
          Rect.fromCenter(
            center: _originRect.center + delta,
            width: width,
            height: width * a.aspectRatio,
          ),
        );
      default:
        break;
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _endGesture();
  }

  void _endGesture() {
    final active = _active;
    if (_mode == _DragMode.highlight && active is HighlightAnnotation) {
      final minimum = _minHighlight / _displayScale;
      setState(() {
        if (active.rect.width < minimum || active.rect.height < minimum) {
          _annotations.remove(active);
        } else {
          _selected = active;
        }
      });
    }
    _mode = _DragMode.none;
    _active = null;
  }

  void _undo() {
    if (_annotations.isEmpty || _saving) {
      return;
    }
    final removed = _annotations.last;
    setState(() {
      _annotations.removeLast();
      if (identical(_selected, removed)) {
        _selected = null;
      }
      _mode = _DragMode.none;
      _active = null;
    });
    if (removed is SignatureAnnotation) {
      removed.image.dispose();
    }
  }

  Future<void> _selectTool(AnnotateTool tool) async {
    if (tool == AnnotateTool.signature) {
      await _addSignature();
      return;
    }
    setState(() {
      _tool = tool;
      if (tool == AnnotateTool.pen) {
        _selected = null;
      }
    });
  }

  Future<void> _addSignature() async {
    final signature = await Navigator.of(context).push<ui.Image>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const AnnotateSignaturePad(),
      ),
    );
    if (signature == null) {
      return;
    }
    if (!mounted || _image == null) {
      signature.dispose();
      return;
    }
    final width = _imageWidth * _signatureWidth;
    final height = width * signature.height / signature.width;
    final margin = _imageWidth * _signatureMargin;
    final annotation = SignatureAnnotation(
      image: signature,
      rect: _clampCenter(
        Rect.fromLTWH(
          _imageWidth - margin - width,
          _imageHeight - margin - height,
          width,
          height,
        ),
      ),
    );
    setState(() {
      _annotations.add(annotation);
      _selected = annotation;
      _tool = AnnotateTool.signature;
    });
  }

  Future<Uint8List> _render(ui.Image image) async {
    final longest = math.max(image.width, image.height);
    final factor = longest > _maxSide ? _maxSide / longest : 1.0;
    final width = math.max(1, (image.width * factor).round());
    final height = math.max(1, (image.height * factor).round());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    AnnotationPainter(
      image: image,
      annotations: _annotations,
      scale: width / image.width,
    ).paint(canvas, Size(width.toDouble(), height.toDouble()));
    final picture = recorder.endRecording();
    final ui.Image output;
    try {
      output = await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
    try {
      final data = await output.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('No se pudo codificar la anotación');
      }
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      output.dispose();
    }
  }

  Future<void> _save() async {
    final image = _image;
    if (image == null || _saving) {
      return;
    }
    setState(() {
      _saving = true;
      _selected = null;
      _mode = _DragMode.none;
      _active = null;
    });
    final page = widget.page;
    final previous = page.currentPath;
    final target = PageEditor.annotatedPath(previous);
    try {
      final bytes = await _render(image);
      final temp = File('$target.tmp');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(target);
      await PageEditor.deleteOcrSidecars(target);
      await FileImage(File(target)).evict();
      page.currentPath = target;
      await SessionStore.save(widget.session);
      await PageEditor.deleteOcrSidecars(previous);
      unawaited(SessionStore.cleanup(widget.session));
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (_) {
      page.currentPath = previous;
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar la anotación.')),
      );
    }
  }

  Future<void> _confirmLeave() async {
    if (_saving) {
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Salir sin guardar?'),
        content: const Text('Se perderán las anotaciones de esta página.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final busy = _saving || image == null;
    return PopScope(
      canPop: _annotations.isEmpty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _confirmLeave();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Anotar'),
          actions: [
            IconButton(
              onPressed: busy ? null : _save,
              tooltip: 'Guardar',
              disabledColor: Colors.white38,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(child: _buildCanvas(image)),
            _buildToolbar(busy),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvas(ui.Image? image) {
    if (_loadFailed) {
      return const Center(
        child: Text(
          'No se pudo abrir la página.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    if (image == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fitted = applyBoxFit(
            BoxFit.contain,
            Size(image.width.toDouble(), image.height.toDouble()),
            constraints.biggest,
          ).destination;
          if (fitted.isEmpty) {
            return const SizedBox.shrink();
          }
          _displayScale = fitted.width / image.width;
          return Center(
            child: SizedBox.fromSize(
              size: fitted,
              child: Listener(
                onPointerDown: _onPointerDown,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: _onTapUp,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  child: CustomPaint(
                    size: fitted,
                    painter: AnnotationPainter(
                      image: image,
                      annotations: _annotations,
                      scale: _displayScale,
                      selected: _selected,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildToolbar(bool busy) {
    return Material(
      color: const Color(0xFF1C1C1C),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              for (final tool in AnnotateTool.values)
                Expanded(
                  child: _ToolButton(
                    icon: _toolIcon(tool),
                    label: _toolLabel(tool),
                    selected: _tool == tool,
                    onPressed: busy ? null : () => _selectTool(tool),
                  ),
                ),
              IconButton(
                onPressed: busy || _annotations.isEmpty ? null : _undo,
                tooltip: 'Deshacer',
                color: Colors.white,
                disabledColor: Colors.white38,
                icon: const Icon(Icons.undo),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _toolIcon(AnnotateTool tool) => switch (tool) {
        AnnotateTool.text => Icons.text_fields,
        AnnotateTool.highlight => Icons.border_color_outlined,
        AnnotateTool.pen => Icons.edit_outlined,
        AnnotateTool.signature => Icons.gesture,
      };

  static String _toolLabel(AnnotateTool tool) => switch (tool) {
        AnnotateTool.text => 'Texto',
        AnnotateTool.highlight => 'Resaltado',
        AnnotateTool.pen => 'Lápiz',
        AnnotateTool.signature => 'Firma',
      };
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color color;
    if (onPressed == null) {
      color = Colors.white38;
    } else if (selected) {
      color = scheme.onPrimaryContainer;
    } else {
      color = Colors.white;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
