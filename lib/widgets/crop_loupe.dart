import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class CropLoupe extends StatelessWidget {
  const CropLoupe({
    super.key,
    required this.file,
    required this.imageSize,
    required this.focus,
    required this.scale,
  });

  static const double diameter = 130;
  static const double zoom = 2.5;

  final File file;
  final Size imageSize;
  final Offset focus;
  final double scale;

  @override
  Widget build(BuildContext context) {
    const radius = diameter / 2;
    final factor = zoom * scale;
    final matrix = Matrix4.identity()
      ..translateByDouble(radius, radius, 0, 1)
      ..scaleByDouble(factor, factor, 1, 1)
      ..translateByDouble(-focus.dx, -focus.dy, 0, 1);
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
      ),
      child: ClipOval(
        child: ColoredBox(
          color: AppColors.camBg,
          child: SizedBox(
            width: diameter,
            height: diameter,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: Transform(
                    alignment: Alignment.topLeft,
                    transform: matrix,
                    child: Image.file(
                      file,
                      width: imageSize.width,
                      height: imageSize.height,
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
                const Positioned.fill(
                  child: CustomPaint(painter: _CrosshairPainter()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  const _CrosshairPainter();

  static const double _gap = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outline = Paint()
      ..strokeWidth = 4
      ..color = Colors.black.withValues(alpha: 0.35);
    final line = Paint()
      ..strokeWidth = 2
      ..color = AppColors.mint;
    for (final paint in [outline, line]) {
      canvas.drawLine(Offset(0, c.dy), c.translate(-_gap, 0), paint);
      canvas.drawLine(c.translate(_gap, 0), Offset(size.width, c.dy), paint);
      canvas.drawLine(Offset(c.dx, 0), c.translate(0, -_gap), paint);
      canvas.drawLine(c.translate(0, _gap), Offset(c.dx, size.height), paint);
    }
    canvas.drawCircle(c, 1.5, Paint()..color = AppColors.mint);
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) => false;
}
