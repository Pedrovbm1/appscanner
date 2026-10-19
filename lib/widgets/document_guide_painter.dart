import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class DocumentGuidePainter extends CustomPainter {
  const DocumentGuidePainter({
    required this.previewRect,
    this.ratio = 210 / 297,
  });

  final Rect previewRect;
  final double ratio;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect area = previewRect;
    if (area.isEmpty) {
      return;
    }
    final double maxWidth = area.width * 0.84;
    final double maxHeight = area.height * 0.72;
    double guideWidth = maxWidth;
    double guideHeight = guideWidth / ratio;
    if (guideHeight > maxHeight) {
      guideHeight = maxHeight;
      guideWidth = guideHeight * ratio;
    }
    final double centerY =
        area.top + area.height / 2;
    final Rect guide = Rect.fromCenter(
      center: Offset(area.center.dx, centerY),
      width: guideWidth,
      height: guideHeight,
    );
    final RRect guideRRect = RRect.fromRectAndRadius(guide, const Radius.circular(14));

    final Path dimPath = Path()
      ..addRect(area)
      ..addRRect(guideRRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dimPath, Paint()..color = AppColors.camBg.withValues(alpha: 0.4));

    canvas.drawRRect(
      guideRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppColors.camText.withValues(alpha: 0.7),
    );

    final bracket = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = AppColors.mint;
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
      oldDelegate.ratio != ratio || oldDelegate.previewRect != previewRect;
}
