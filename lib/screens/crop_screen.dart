import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/document_detector.dart';
import '../theme/app_theme.dart';
import '../widgets/crop_loupe.dart';

class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.file, this.pageLabel});

  final File file;
  final String? pageLabel;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  static const double _horizontalPadding = 24;
  static const double _verticalPadding = 16;
  static const double _magnetRadius = 64;

  ui.Image? _image;
  List<Offset>? _corners;
  int? _activeCorner;
  Offset? _touchPoint;
  bool _cropping = false;

  double _scale = 1;
  Offset _origin = Offset.zero;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await widget.file.readAsBytes();
    final image = await decodeImageFromList(bytes);
    if (!mounted) {
      return;
    }
    setState(() => _image = image);
    List<Offset> corners;
    try {
      corners = await DocumentDetector.detect(widget.file.path);
    } catch (_) {
      final w = image.width.toDouble();
      final h = image.height.toDouble();
      corners = [
        const Offset(1, 1),
        Offset(w - 1, 1),
        Offset(w - 1, h - 1),
        Offset(1, h - 1),
      ];
    }
    if (!mounted) {
      return;
    }
    setState(() => _corners = corners);
  }

  Offset _toScreen(Offset p) =>
      Offset(_origin.dx + p.dx * _scale, _origin.dy + p.dy * _scale);

  Offset _toImage(Offset p) =>
      Offset((p.dx - _origin.dx) / _scale, (p.dy - _origin.dy) / _scale);

  void _resetFrame() {
    final image = _image;
    if (image == null) {
      return;
    }
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    setState(() {
      _corners = [
        const Offset(1, 1),
        Offset(w - 1, 1),
        Offset(w - 1, h - 1),
        Offset(1, h - 1),
      ];
    });
  }

  void _onPanStart(DragStartDetails details) {
    final corners = _corners;
    if (corners == null) {
      return;
    }
    final p = details.localPosition;
    int? best;
    var bestDistance = _magnetRadius;
    for (var i = 0; i < corners.length; i++) {
      final distance = (_toScreen(corners[i]) - p).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    setState(() {
      _activeCorner = best;
      _touchPoint = best == null ? null : p;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final corners = _corners;
    final active = _activeCorner;
    final image = _image;
    if (corners == null || active == null || image == null) {
      return;
    }
    final maxW = image.width.toDouble();
    final maxH = image.height.toDouble();
    final imgPt = _toImage(details.localPosition);
    setState(() {
      corners[active] = Offset(
        imgPt.dx.clamp(0.0, maxW).toDouble(),
        imgPt.dy.clamp(0.0, maxH).toDouble(),
      );
      _touchPoint = details.localPosition;
    });
  }

  void _endDrag() {
    setState(() {
      _activeCorner = null;
      _touchPoint = null;
    });
  }

  Offset _loupeTopLeft(Size area, Offset touch) {
    const radius = CropLoupe.diameter / 2;
    const lift = 110.0;
    var cy = touch.dy - lift;
    if (cy - radius < 0) {
      cy = touch.dy + lift;
    }
    final cx = touch.dx
        .clamp(radius, math.max(radius, area.width - radius))
        .toDouble();
    cy = cy.clamp(radius, math.max(radius, area.height - radius)).toDouble();
    return Offset(cx - radius, cy - radius);
  }

  Future<void> _crop() async {
    final corners = _corners;
    if (corners == null) {
      return;
    }
    setState(() => _cropping = true);
    try {
      final ordered = DocumentDetector.orderCorners(corners);
      final outPath = await DocumentDetector.applyWarp(
        widget.file.path,
        ordered,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(outPath);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _cropping = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo recortar la imagen.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final corners = _corners;
    final pageLabel = widget.pageLabel;
    return Theme(
      data: AppTheme.camera(Theme.of(context)),
      child: Scaffold(
        backgroundColor: AppColors.camBg,
        appBar: AppBar(
          toolbarHeight: 64,
          leading: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Volver a la cámara',
          ),
          titleSpacing: 4,
          title: const Text('Ajusta las esquinas'),
          actions: [
            if (pageLabel != null)
              Padding(
                padding: const EdgeInsets.only(right: 20),
                child: Center(
                  child: Text(
                    pageLabel,
                    style: const TextStyle(fontSize: 14, color: AppColors.camMuted),
                  ),
                ),
              ),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: ColoredBox(
                        color: AppColors.camSurface,
                        child: _stage(image, corners),
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 14, 24, 0),
                  child: Text(
                    'Arrastra un punto. La lupa te ayuda a ser preciso.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: AppColors.camTextSoft),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: _toolButton(
                                icon: Icons.replay,
                                label: 'Repetir foto',
                                onTap: _cropping
                                    ? null
                                    : () => Navigator.of(context).pop(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _toolButton(
                                icon: Icons.fullscreen,
                                label: 'Toda la foto',
                                onTap: corners == null ? null : _resetFrame,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: (_cropping || corners == null) ? null : _crop,
                            iconAlignment: IconAlignment.end,
                            icon: const Icon(Icons.arrow_forward, size: 20),
                            label: const Text('Siguiente'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_cropping)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.6),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppColors.mint),
                        SizedBox(height: 14),
                        Text(
                          'Enderezando…',
                          style: TextStyle(
                            color: AppColors.camText,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _stage(ui.Image? image, List<Offset>? corners) {
    if (image == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.mint),
      );
    }
    if (corners == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.mint),
            SizedBox(height: 14),
            Text(
              'Detectando bordes…',
              style: TextStyle(color: AppColors.camTextSoft, fontSize: 14),
            ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final imgW = image.width.toDouble();
        final imgH = image.height.toDouble();
        final availableW = math.max(
          constraints.maxWidth - _horizontalPadding * 2,
          1.0,
        );
        final availableH = math.max(
          constraints.maxHeight - _verticalPadding * 2,
          1.0,
        );
        final scale = math.min(
          availableW / imgW,
          availableH / imgH,
        );
        _scale = scale;
        _origin = Offset(
          (constraints.maxWidth - imgW * scale) / 2,
          (constraints.maxHeight - imgH * scale) / 2,
        );
        final screenCorners = [
          for (final c in corners) _toScreen(c),
        ];
        final active = _activeCorner;
        final touch = _touchPoint;
        final loupeTopLeft = active == null || touch == null
            ? null
            : _loupeTopLeft(constraints.biggest, touch);
        return GestureDetector(
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: (_) => _endDrag(),
          onPanCancel: _endDrag,
          child: Stack(
            children: [
              Positioned(
                left: _origin.dx,
                top: _origin.dy,
                width: imgW * scale,
                height: imgH * scale,
                child: Image.file(
                  widget.file,
                  fit: BoxFit.fill,
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _CropOverlayPainter(
                    corners: screenCorners,
                    active: _activeCorner,
                  ),
                ),
              ),
              if (active != null && loupeTopLeft != null)
                Positioned(
                  left: loupeTopLeft.dx,
                  top: loupeTopLeft.dy,
                  child: IgnorePointer(
                    child: CropLoupe(
                      file: widget.file,
                      imageSize: Size(imgW, imgH),
                      focus: corners[active],
                      scale: scale,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _toolButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    final color = onTap == null ? AppColors.camMuted : AppColors.camText;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 24, color: color),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter({required this.corners, required this.active});

  final List<Offset> corners;
  final int? active;

  @override
  void paint(Canvas canvas, Size size) {
    final quad = Path()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();

    final dim = Path()
      ..addRect(Offset.zero & size)
      ..addPath(quad, Offset.zero)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: 0.5));

    if (active != null) {
      final grid = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.3);
      for (final t in const [1 / 3, 2 / 3]) {
        canvas.drawLine(
          Offset.lerp(corners[0], corners[1], t)!,
          Offset.lerp(corners[3], corners[2], t)!,
          grid,
        );
        canvas.drawLine(
          Offset.lerp(corners[0], corners[3], t)!,
          Offset.lerp(corners[1], corners[2], t)!,
          grid,
        );
      }
    }

    canvas.drawPath(
      quad,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..color = AppColors.mint,
    );

    for (var i = 0; i < corners.length; i++) {
      final isActive = i == active;
      final radius = isActive ? 17.0 : 13.0;
      canvas.drawCircle(
        corners[i],
        radius + 2,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawCircle(
        corners[i],
        radius,
        Paint()..color = isActive ? Colors.white : AppColors.mint,
      );
      canvas.drawCircle(
        corners[i],
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isActive ? 4 : 3
          ..color = isActive ? AppColors.mint : Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) => true;
}
