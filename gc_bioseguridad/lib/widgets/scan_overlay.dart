import 'dart:math';

import 'package:flutter/material.dart';

/// Óvalo de encuadre, el mismo de la verificación facial de gc_verificacion.
class ScanOverlay extends StatelessWidget {
  const ScanOverlay({
    super.key,
    required this.scanT,
    required this.progreso,
    required this.color,
    required this.activo,
  });

  final double scanT;
  final double progreso;
  final Color color;
  final bool activo;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ScanPainter(
        scanT: scanT,
        progreso: progreso,
        color: color,
        activo: activo,
      ),
    );
  }
}

class _ScanPainter extends CustomPainter {
  _ScanPainter({
    required this.scanT,
    required this.progreso,
    required this.color,
    required this.activo,
  });

  final double scanT;
  final double progreso;
  final Color color;
  final bool activo;

  @override
  void paint(Canvas canvas, Size size) {
    final ow = (size.width * 0.62).clamp(0.0, 400.0);
    final oh = ow * 1.3;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.54),
      width: ow,
      height: oh,
    );
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white.withValues(alpha: 0.18);
    canvas.drawOval(rect, track);
    if (progreso > 0) {
      final prog = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawArc(rect, -pi / 2, progreso * 2 * pi, false, prog);
    }
    if (activo) {
      final y = rect.top + scanT * rect.height;
      canvas.save();
      canvas.clipPath(Path()..addOval(rect));
      final grad = Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            color.withValues(alpha: 0.9),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(rect.left, y - 1, rect.width, 2));
      canvas.drawRect(Rect.fromLTWH(rect.left, y - 1, rect.width, 2), grad);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ScanPainter old) =>
      old.scanT != scanT ||
      old.progreso != progreso ||
      old.color != color ||
      old.activo != activo;
}
