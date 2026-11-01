import 'dart:ui';

/// Cómo [CameraPreview] ocupa el cuerpo en portrait (AspectRatio + alineación arriba).
abstract final class CameraPreviewLayout {
  static Rect previewRectInParent({
    required Size parentSize,
    required double controllerAspectRatio,
  }) {
    if (controllerAspectRatio <= 0) {
      return Offset.zero & parentSize;
    }
    final ar = 1 / controllerAspectRatio;
    final parentAr = parentSize.width / parentSize.height;

    late double w;
    late double h;
    if (parentAr > ar) {
      h = parentSize.height;
      w = h * ar;
    } else {
      w = parentSize.width;
      h = w / ar;
    }
    return Rect.fromLTWH(0, 0, w, h);
  }
}
