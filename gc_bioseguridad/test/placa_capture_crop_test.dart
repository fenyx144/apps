import 'package:bioseguridad/utils/camera_preview_layout.dart';
import 'package:bioseguridad/utils/placa_capture_crop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('mapGuideRect queda dentro de la imagen', () {
    const body = Size(400, 700);
    const image = Size(4032, 3024);
    final preview = CameraPreviewLayout.previewRectInParent(
      parentSize: body,
      controllerAspectRatio: 1.777,
    );
    final guide = PlacaCameraGuide.rectOnPreview(preview);
    final mapped = mapGuideRectToImage(
      guideInBody: guide,
      previewInBody: preview,
      imageSize: image,
    );
    expect(mapped.left, greaterThanOrEqualTo(0));
    expect(mapped.top, greaterThanOrEqualTo(0));
    expect(mapped.right, lessThanOrEqualTo(image.width));
    expect(mapped.bottom, lessThanOrEqualTo(image.height));
    expect(mapped.width, greaterThan(50));
    expect(mapped.height, greaterThan(20));
  });

  test('sin contraste tipo placa no muestra sugerencia', () {
    final canvas = img.Image(width: 200, height: 80);
    img.fill(canvas, color: img.ColorRgb8(120, 120, 120));
    expect(PlacaCameraGuide.sugerenciaDesdeRecorte(canvas), isNull);
  });

  test('recorteParecePlaca exige banda de contraste', () {
    expect(PlacaCameraGuide.recorteParecePlaca([0.0, 0.0, 0.0]), isFalse);
    expect(
      PlacaCameraGuide.recorteParecePlaca([
        0.0, 0.0, 8.0, 9.0, 9.0, 9.0, 8.0, 0.0, 0.0,
      ]),
      isTrue,
    );
  });

  test('sugerenciaDistanciaDesdeFill solo fuera de rango', () {
    expect(
      PlacaCameraGuide.sugerenciaDistanciaDesdeFill(0.12),
      'Acérquese más a la placa',
    );
    expect(
      PlacaCameraGuide.sugerenciaDistanciaDesdeFill(0.70),
      'Aléjese un poco para encajar la placa',
    );
    expect(PlacaCameraGuide.sugerenciaDistanciaDesdeFill(0.35), isNull);
  });

  test('mapNormalizedBoxToBody queda dentro del preview', () {
    const body = Size(400, 700);
    const image = Size(1200, 900);
    final preview = CameraPreviewLayout.previewRectInParent(
      parentSize: body,
      controllerAspectRatio: 1.777,
    );
    const box = Rect.fromLTWH(0.25, 0.35, 0.5, 0.18);
    final onBody = mapNormalizedBoxToBody(
      normalizedBox: box,
      imageSize: image,
      previewInBody: preview,
    );
    expect(onBody.left, greaterThanOrEqualTo(preview.left - 1));
    expect(onBody.top, greaterThanOrEqualTo(preview.top - 1));
    expect(onBody.right, lessThanOrEqualTo(preview.right + 1));
    expect(onBody.bottom, lessThanOrEqualTo(preview.bottom + 1));
  });

  test('caja YOLO dentro del marco queda en píxeles válidos', () {
    const guideSize = Size(800, 280);
    const box = Rect.fromLTWH(0.1, 0.2, 0.75, 0.55);
    final px = normalizedBoxToImageRect(
      normalizedBox: box,
      imageSize: guideSize,
    );
    expect(px.width, greaterThan(40));
    expect(px.height, greaterThan(20));
    expect(px.right, lessThanOrEqualTo(800));
    expect(px.bottom, lessThanOrEqualTo(280));
  });

  test('normalizedBoxToImageRect respeta límites', () {
    const image = Size(1000, 800);
    const box = Rect.fromLTWH(0.2, 0.3, 0.5, 0.2);
    final px = normalizedBoxToImageRect(
      normalizedBox: box,
      imageSize: image,
    );
    expect(px.left, greaterThanOrEqualTo(0));
    expect(px.top, greaterThanOrEqualTo(0));
    expect(px.right, lessThanOrEqualTo(1000));
    expect(px.bottom, lessThanOrEqualTo(800));
  });
}
