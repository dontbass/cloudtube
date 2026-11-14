import 'package:flutter/material.dart';

/// Собственный значок Shorts для CloudTube: вертикальный «экран телефона» с треугольником Play.
class CtShortsIcon extends StatelessWidget {
  final bool filled;
  final double size;

  const CtShortsIcon({super.key, this.filled = false, this.size = 24});

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _P(color, filled, Theme.of(context).colorScheme.surface)),
    );
  }
}

class _P extends CustomPainter {
  final Color color;
  final bool filled;
  final Color hole;

  _P(this.color, this.filled, this.hole);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.22, h * 0.06, w * 0.56, h * 0.88), Radius.circular(w * 0.14));
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.085;
    final fill = Paint()..color = color;
    if (filled) {
      canvas.drawRRect(r, fill);
    } else {
      canvas.drawRRect(r, stroke);
    }
    final tri = Path()
      ..moveTo(w * 0.42, h * 0.36)
      ..lineTo(w * 0.64, h * 0.5)
      ..lineTo(w * 0.42, h * 0.64)
      ..close();
    canvas.drawPath(tri, filled ? (Paint()..color = hole) : fill);
  }

  @override
  bool shouldRepaint(covariant _P o) => o.color != color || o.filled != filled || o.hole != hole;
}
