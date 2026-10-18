import 'dart:io';

import 'package:flutter/material.dart';

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
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: ClipOval(
        child: ColoredBox(
          color: Colors.black,
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

  static const double _arm = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outline = Paint()
      ..strokeWidth = 3
      ..color = Colors.black.withValues(alpha: 0.6);
    final line = Paint()
      ..strokeWidth = 1
      ..color = const Color(0xFF69F0AE);
    for (final paint in [outline, line]) {
      canvas.drawLine(c.translate(-_arm, 0), c.translate(_arm, 0), paint);
      canvas.drawLine(c.translate(0, -_arm), c.translate(0, _arm), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) => false;
}
