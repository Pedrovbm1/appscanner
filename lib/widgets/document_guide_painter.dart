import 'package:flutter/material.dart';

class DocumentGuidePainter extends CustomPainter {
  const DocumentGuidePainter({this.ratio = 210 / 297});

  final double ratio;

  @override
  void paint(Canvas canvas, Size size) {
    final double maxWidth = size.width * 0.84;
    final double maxHeight = size.height * 0.72;
    double guideWidth = maxWidth;
    double guideHeight = guideWidth / ratio;
    if (guideHeight > maxHeight) {
      guideHeight = maxHeight;
      guideWidth = guideHeight * ratio;
    }
    final double centerY = ratio > 1 ? size.height / 2 : size.height * 0.44;
    final Rect guide = Rect.fromCenter(
      center: Offset(size.width / 2, centerY),
      width: guideWidth,
      height: guideHeight,
    );
    final RRect guideRRect = RRect.fromRectAndRadius(guide, const Radius.circular(14));

    final Path dimPath = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(guideRRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dimPath, Paint()..color = Colors.black.withValues(alpha: 0.45));

    canvas.drawRRect(
      guideRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.85),
    );

    final bracket = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF69F0AE);
    const double len = 26;

    canvas.drawPath(
      Path()
        ..moveTo(guide.left, guide.top + len)
        ..lineTo(guide.left, guide.top)
        ..lineTo(guide.left + len, guide.top),
      bracket,
    );
    canvas.drawPath(
      Path()
        ..moveTo(guide.right - len, guide.top)
        ..lineTo(guide.right, guide.top)
        ..lineTo(guide.right, guide.top + len),
      bracket,
    );
    canvas.drawPath(
      Path()
        ..moveTo(guide.right, guide.bottom - len)
        ..lineTo(guide.right, guide.bottom)
        ..lineTo(guide.right - len, guide.bottom),
      bracket,
    );
    canvas.drawPath(
      Path()
        ..moveTo(guide.left + len, guide.bottom)
        ..lineTo(guide.left, guide.bottom)
        ..lineTo(guide.left, guide.bottom - len),
      bracket,
    );
  }

  @override
  bool shouldRepaint(covariant DocumentGuidePainter oldDelegate) =>
      oldDelegate.ratio != ratio;
}
