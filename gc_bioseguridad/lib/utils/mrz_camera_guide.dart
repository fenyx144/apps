import 'dart:math' as math;
import 'dart:ui';

/// Recuadro para las 2 líneas MRZ (reverso del carné), no todo el documento.
abstract final class MrzCameraGuide {
  static Rect rectOnPreview(Rect previewInBody) {
    final w = previewInBody.width * 0.92;
    final h = math.max(88.0, previewInBody.height * 0.24);
    final center = Offset(
      previewInBody.center.dx,
      previewInBody.top + previewInBody.height * 0.70,
    );
    return Rect.fromCenter(center: center, width: w, height: h);
  }
}
