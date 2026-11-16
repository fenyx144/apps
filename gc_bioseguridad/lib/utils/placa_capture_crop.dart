import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'placa_ocr_parser.dart';

/// Marco visible en [PlacaCameraScreen] (sobre el preview; el OCR solo usa esta zona).
abstract final class PlacaCameraGuide {
  static const double width = 300;
  /// Más alto que antes para cubrir placa + marco sin leer el entorno.
  static const double height = 112;
  /// Centro un poco arriba del preview (evita botón inferior y mejora encuadre).
  static const double centerVerticalFactor = 0.40;

  /// Sugerencia de distancia según el tamaño del recuadro en la foto.
  static String? sugerenciaEncuadre({
    required Rect guideInBody,
    required Rect previewInBody,
    required Size imageSize,
  }) {
    final mapped = mapGuideRectToImage(
      guideInBody: guideInBody,
      previewInBody: previewInBody,
      imageSize: imageSize,
      paddingFactor: 1.0,
    );
    if (mapped.height < 55) return 'Acérquese más: la placa se ve muy pequeña';
    if (mapped.height > imageSize.height * 0.55) {
      return 'Aléjese un poco: encaje toda la placa en el recuadro';
    }
    if (mapped.width > imageSize.width * 0.92) {
      return 'Aléjese un poco para que la placa no quede cortada';
    }
    return null;
  }

  static Rect rectOnPreview(Rect previewInBody) {
    final w = math.min(width, previewInBody.width * 0.92);
    final h = w * (height / width);
    final center = Offset(
      previewInBody.center.dx,
      previewInBody.top + previewInBody.height * centerVerticalFactor,
    );
    return Rect.fromCenter(center: center, width: w, height: h);
  }

  /// ¿Hay una franja horizontal de contraste (texto) dentro del recorte?
  static bool recorteParecePlaca(List<double> rowScore) {
    if (rowScore.isEmpty) return false;
    final peak = rowScore.reduce(math.max);
    if (peak < 4) return false;
    final threshold = peak * 0.32;
    var activas = 0;
    var top = rowScore.length;
    var bottom = 0;
    for (var y = 0; y < rowScore.length; y++) {
      if (rowScore[y] >= threshold) {
        activas++;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
    return activas >= 3 && bottom > top;
  }

  /// Distancia solo si ya se ve algo tipo placa; si no, null (sin mensaje).
  static String? sugerenciaDistanciaDesdeFill(double fill) {
    if (fill < 0.20) return 'Acérquese más a la placa';
    if (fill > 0.62) return 'Aléjese un poco para encajar la placa';
    return null;
  }

  /// Distancia según cuánto ocupa la placa (texto/contraste) dentro del recorte.
  static String? sugerenciaDesdeRecorte(img.Image crop) {
    if (crop.width < 24 || crop.height < 24) return null;
    final g = img.grayscale(crop);
    final w = g.width;
    final h = g.height;
    final rowScore = List<double>.filled(h, 0);
    for (var y = 1; y < h; y++) {
      var sum = 0.0;
      for (var x = 0; x < w; x++) {
        final a = img.getLuminance(g.getPixel(x, y));
        final b = img.getLuminance(g.getPixel(x, y - 1));
        sum += (a - b).abs();
      }
      rowScore[y] = sum / w;
    }
    if (!recorteParecePlaca(rowScore)) return null;
    final threshold = rowScore.reduce(math.max) * 0.32;
    var top = h;
    var bottom = 0;
    for (var y = 0; y < h; y++) {
      if (rowScore[y] >= threshold) {
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
    final fill = (bottom - top + 1) / h;
    return sugerenciaDistanciaDesdeFill(fill);
  }

  /// Analiza la zona del marco en una foto (misma geometría que el OCR).
  static Future<String?> sugerenciaDesdeFoto({
    required String sourcePath,
    required Rect guideInBody,
    required Rect previewInBody,
  }) async {
    final bytes = await File(sourcePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final upright = img.bakeOrientation(decoded);
    final imageSize = Size(upright.width.toDouble(), upright.height.toDouble());
    final guide = mapGuideRectToImage(
      guideInBody: guideInBody,
      previewInBody: previewInBody,
      imageSize: imageSize,
      paddingFactor: 1.0,
    );
    if (guide.width < 8 || guide.height < 8) return null;
    final x = guide.left.round().clamp(0, upright.width - 1);
    final y = guide.top.round().clamp(0, upright.height - 1);
    final maxW = upright.width - x;
    final maxH = upright.height - y;
    final w = guide.width.round().clamp(1, maxW);
    final h = guide.height.round().clamp(1, maxH);
    final crop = img.copyCrop(upright, x: x, y: y, width: w, height: h);
    return sugerenciaDesdeRecorte(crop);
  }

  /// Vista previa (stream): muestra de la zona Y del marco, sin decodificar JPEG.
  static String? sugerenciaDesdePlanoY({
    required List<int> yBytes,
    required int bytesPerRow,
    required int imageWidth,
    required int imageHeight,
    required Rect guideInBody,
    required Rect previewInBody,
  }) {
    if (imageWidth < 8 || imageHeight < 8) return null;
    final imageSize = Size(imageWidth.toDouble(), imageHeight.toDouble());
    final guide = mapGuideRectToImage(
      guideInBody: guideInBody,
      previewInBody: previewInBody,
      imageSize: imageSize,
      paddingFactor: 1.0,
    );
    final left = guide.left.round().clamp(0, imageWidth - 1);
    final top = guide.top.round().clamp(0, imageHeight - 1);
    final right = guide.right.round().clamp(left + 1, imageWidth);
    final bottom = guide.bottom.round().clamp(top + 1, imageHeight);
    final h = bottom - top;
    final w = right - left;
    if (w < 12 || h < 12) return null;

    final rowScore = List<double>.filled(h, 0);
    for (var row = 0; row < h; row++) {
      final y = top + row;
      var sum = 0.0;
      for (var col = 1; col < w; col++) {
        final x = left + col;
        final i = y * bytesPerRow + x;
        final j = y * bytesPerRow + (x - 1);
        if (i >= yBytes.length || j >= yBytes.length) continue;
        sum += (yBytes[i] - yBytes[j]).abs();
      }
      rowScore[row] = sum / (w - 1);
    }
    if (!recorteParecePlaca(rowScore)) return null;
    final threshold = rowScore.reduce(math.max) * 0.32;
    var bandTop = h;
    var bandBottom = 0;
    for (var row = 0; row < h; row++) {
      if (rowScore[row] >= threshold) {
        if (row < bandTop) bandTop = row;
        if (row > bandBottom) bandBottom = row;
      }
    }
    final fill = (bandBottom - bandTop + 1) / h;
    return sugerenciaDistanciaDesdeFill(fill);
  }
}

/// Mapea el recuadro guía (coordenadas del cuerpo) a píxeles de la foto.
@visibleForTesting
Rect mapGuideRectToImage({
  required Rect guideInBody,
  required Rect previewInBody,
  required Size imageSize,
  double paddingFactor = 1.0,
}) {
  if (previewInBody.width <= 0 || previewInBody.height <= 0) {
    return Offset.zero & imageSize;
  }

  var rel = Rect.fromLTRB(
    (guideInBody.left - previewInBody.left) / previewInBody.width,
    (guideInBody.top - previewInBody.top) / previewInBody.height,
    (guideInBody.right - previewInBody.left) / previewInBody.width,
    (guideInBody.bottom - previewInBody.top) / previewInBody.height,
  );

  if (paddingFactor != 1) {
    final cx = rel.center.dx;
    final cy = rel.center.dy;
    rel = Rect.fromCenter(
      center: Offset(cx, cy),
      width: rel.width * paddingFactor,
      height: rel.height * paddingFactor,
    );
  }

  rel = rel.intersect(const Rect.fromLTWH(0, 0, 1, 1));

  final onImage = Rect.fromLTRB(
    rel.left * imageSize.width,
    rel.top * imageSize.height,
    rel.right * imageSize.width,
    rel.bottom * imageSize.height,
  );

  return onImage.intersect(
    Rect.fromLTWH(0, 0, imageSize.width, imageSize.height),
  );
}

/// Caja YOLO (normalizada sobre [imageSize]) coordenadas del cuerpo/preview.
Rect mapNormalizedBoxToBody({
  required Rect normalizedBox,
  required Size imageSize,
  required Rect previewInBody,
}) {
  if (previewInBody.width <= 0 || previewInBody.height <= 0) {
    return Rect.zero;
  }
  final onImage = normalizedBoxToImageRect(
    normalizedBox: normalizedBox,
    imageSize: imageSize,
    paddingFactor: 1.0,
  );
  final rel = Rect.fromLTRB(
    onImage.left / imageSize.width,
    onImage.top / imageSize.height,
    onImage.right / imageSize.width,
    onImage.bottom / imageSize.height,
  );
  return Rect.fromLTRB(
    previewInBody.left + rel.left * previewInBody.width,
    previewInBody.top + rel.top * previewInBody.height,
    previewInBody.left + rel.right * previewInBody.width,
    previewInBody.top + rel.bottom * previewInBody.height,
  );
}

/// Convierte una caja YOLO normalizada (0–1) a píxeles con margen opcional.
@visibleForTesting
Rect normalizedBoxToImageRect({
  required Rect normalizedBox,
  required Size imageSize,
  double paddingFactor = 1.1,
}) {
  var rel = normalizedBox.intersect(const Rect.fromLTWH(0, 0, 1, 1));
  if (paddingFactor != 1) {
    final cx = rel.center.dx;
    final cy = rel.center.dy;
    rel = Rect.fromCenter(
      center: Offset(cx, cy),
      width: (rel.width * paddingFactor).clamp(0.0, 1.0),
      height: (rel.height * paddingFactor).clamp(0.0, 1.0),
    ).intersect(const Rect.fromLTWH(0, 0, 1, 1));
  }
  return Rect.fromLTRB(
    rel.left * imageSize.width,
    rel.top * imageSize.height,
    rel.right * imageSize.width,
    rel.bottom * imageSize.height,
  ).intersect(Rect.fromLTWH(0, 0, imageSize.width, imageSize.height));
}

/// Recorte del marco azul en JPEG (sin preproceso OCR) para inferencia YOLO.
Future<String> exportGuideRegionJpeg({
  required String sourcePath,
  required Rect guideInBody,
  required Rect previewInBody,
  double paddingFactor = 1.0,
}) async {
  final bytes = await File(sourcePath).readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return sourcePath;

  final upright = img.bakeOrientation(decoded);
  final imageSize = Size(upright.width.toDouble(), upright.height.toDouble());
  final guide = mapGuideRectToImage(
    guideInBody: guideInBody,
    previewInBody: previewInBody,
    imageSize: imageSize,
    paddingFactor: paddingFactor,
  );

  if (guide.width < 8 || guide.height < 8) return sourcePath;

  final x = guide.left.round().clamp(0, upright.width - 1);
  final y = guide.top.round().clamp(0, upright.height - 1);
  final maxW = upright.width - x;
  final maxH = upright.height - y;
  final w = guide.width.round().clamp(1, maxW);
  final h = guide.height.round().clamp(1, maxH);

  final cropped = img.copyCrop(upright, x: x, y: y, width: w, height: h);
  final outBytes = Uint8List.fromList(img.encodeJpg(cropped, quality: 92));
  final dir = await getTemporaryDirectory();
  final outPath = p.join(
    dir.path,
    'placa_guide_yolo_${DateTime.now().millisecondsSinceEpoch}.jpg',
  );
  await File(outPath).writeAsBytes(outBytes, flush: true);
  return outPath;
}

/// Caja YOLO (0–1 sobre el JPEG del marco) recorte OCR preprocesado.
Future<String> cropOcrFromYoloInGuideJpeg({
  required String guideJpegPath,
  required Rect normalizedBoxInGuide,
  double paddingFactor = 1.1,
}) async {
  final bytes = await File(guideJpegPath).readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return guideJpegPath;

  final imageSize = Size(decoded.width.toDouble(), decoded.height.toDouble());
  final box = normalizedBoxToImageRect(
    normalizedBox: normalizedBoxInGuide,
    imageSize: imageSize,
    paddingFactor: paddingFactor,
  );

  if (box.width < 8 || box.height < 8) return guideJpegPath;

  final x = box.left.round().clamp(0, decoded.width - 1);
  final y = box.top.round().clamp(0, decoded.height - 1);
  final maxW = decoded.width - x;
  final maxH = decoded.height - y;
  final w = box.width.round().clamp(1, maxW);
  final h = box.height.round().clamp(1, maxH);

  final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
  return _guardarRecorteRaw(cropped, 'placa_guide_yolo_ocr');
}

/// Recorta según detección YOLO (caja normalizada) y guarda JPEG para OCR.
Future<String> cropPlacaYoloRegion({
  required String sourcePath,
  required Rect normalizedBox,
  double paddingFactor = 1.1,
}) async {
  final bytes = await File(sourcePath).readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return sourcePath;

  final upright = img.bakeOrientation(decoded);
  final imageSize = Size(upright.width.toDouble(), upright.height.toDouble());
  final guide = normalizedBoxToImageRect(
    normalizedBox: normalizedBox,
    imageSize: imageSize,
    paddingFactor: paddingFactor,
  );

  if (guide.width < 8 || guide.height < 8) return sourcePath;

  final x = guide.left.round().clamp(0, upright.width - 1);
  final y = guide.top.round().clamp(0, upright.height - 1);
  final maxW = upright.width - x;
  final maxH = upright.height - y;
  final w = guide.width.round().clamp(1, maxW);
  final h = guide.height.round().clamp(1, maxH);

  final cropped = img.copyCrop(upright, x: x, y: y, width: w, height: h);
  return _guardarRecorteRaw(cropped, 'placa_yolo');
}

/// Recorta la zona del marco y guarda un JPEG temporal para OCR.
Future<String> cropPlacaGuideRegion({
  required String sourcePath,
  required Rect guideInBody,
  required Rect previewInBody,
  double paddingFactor = 1.0,
}) async {
  final bytes = await File(sourcePath).readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return sourcePath;

  final upright = img.bakeOrientation(decoded);
  final imageSize = Size(upright.width.toDouble(), upright.height.toDouble());
  final guide = mapGuideRectToImage(
    guideInBody: guideInBody,
    previewInBody: previewInBody,
    imageSize: imageSize,
    paddingFactor: paddingFactor,
  );

  if (guide.width < 8 || guide.height < 8) return sourcePath;

  final x = guide.left.round().clamp(0, upright.width - 1);
  final y = guide.top.round().clamp(0, upright.height - 1);
  final maxW = upright.width - x;
  final maxH = upright.height - y;
  final w = guide.width.round().clamp(1, maxW);
  final h = guide.height.round().clamp(1, maxH);

  final cropped = img.copyCrop(upright, x: x, y: y, width: w, height: h);
  return _guardarRecorteRaw(cropped, 'placa_crop');
}

Future<String> _guardarRecorteRaw(img.Image cropped, String prefix) async {
  final outBytes = Uint8List.fromList(img.encodeJpg(cropped, quality: 96));
  final dir = await getTemporaryDirectory();
  final outPath = p.join(
    dir.path,
    '${prefix}_${DateTime.now().millisecondsSinceEpoch}.jpg',
  );
  await File(outPath).writeAsBytes(outBytes, flush: true);
  return outPath;
}

/// OCR en orden rápidoexhaustivo; para si la placa ya es confiable.
Future<String?> reconocerPlacaEnRecorteOptimizado({
  required String rawCropPath,
  required Future<String?> Function(String imagePath) leerPlacaEnImagen,
}) async {
  if (rawCropPath.isEmpty || !File(rawCropPath).existsSync()) return null;
  final decoded = img.decodeImage(await File(rawCropPath).readAsBytes());
  if (decoded == null) return null;

  final dir = await getTemporaryDirectory();
  final ts = DateTime.now().millisecondsSinceEpoch;
  final debiles = <String>[];

  Future<String?> probar(String tag, img.Image im, {bool png = false}) async {
    final bytes = png
        ? Uint8List.fromList(img.encodePng(im))
        : Uint8List.fromList(img.encodeJpg(im, quality: 94));
    final ext = png ? 'png' : 'jpg';
    final path = p.join(dir.path, 'placa_ocr_${tag}_$ts.$ext');
    await File(path).writeAsBytes(bytes, flush: true);
    final placa = await leerPlacaEnImagen(path);
    if (placa == null) return null;
    if (PlacaOcrParser.esLecturaConfiable(placa)) return placa;
    debiles.add(placa);
    return null;
  }

  final raw = await probar(
    'raw',
    _escalarMinAncho(img.grayscale(decoded), 1200),
  );
  if (raw != null) return raw;

  final rapido = await probar('std', _preprocesarParaOcr(decoded));
  if (rapido != null) return rapido;

  final fuerte = await probar('hi', _preprocesarParaOcrFuerte(decoded));
  if (fuerte != null) return fuerte;

  final bin = await probar(
    'bin',
    _preprocesarParaOcrBinario(decoded, textoOscuro: true),
    png: true,
  );
  if (bin != null) return bin;

  return PlacaOcrParser.elegirPorVotos(debiles);
}

img.Image _escalarMinAncho(img.Image src, int minAncho) {
  if (src.width >= minAncho) return src;
  return img.copyResize(
    src,
    width: minAncho,
    interpolation: img.Interpolation.cubic,
  );
}

double _umbralLuminancia(img.Image gray) {
  var sum = 0.0;
  for (var y = 0; y < gray.height; y++) {
    for (var x = 0; x < gray.width; x++) {
      sum += img.getLuminance(gray.getPixel(x, y));
    }
  }
  return sum / (gray.width * gray.height);
}

img.Image _preprocesarParaOcr(img.Image src) {
  var out = img.grayscale(src);
  out = img.adjustColor(
    out,
    contrast: 1.55,
    brightness: 1.03,
    gamma: 0.85,
  );
  return _escalarMinAncho(out, 1280);
}

img.Image _preprocesarParaOcrFuerte(img.Image src) {
  var out = img.grayscale(src);
  out = img.adjustColor(
    out,
    contrast: 2.0,
    brightness: 1.06,
    gamma: 0.72,
  );
  return _escalarMinAncho(out, 1400);
}

/// Binariza para resaltar trazos (mejor separación 4/A en ML Kit).
img.Image _preprocesarParaOcrBinario(
  img.Image src, {
  required bool textoOscuro,
}) {
  var gray = _escalarMinAncho(img.grayscale(src), 1280);
  final umbral = _umbralLuminancia(gray) * 0.92;
  final out = img.Image(width: gray.width, height: gray.height);
  for (var y = 0; y < gray.height; y++) {
    for (var x = 0; x < gray.width; x++) {
      final l = img.getLuminance(gray.getPixel(x, y));
      final oscuro = l < umbral;
      final negro = textoOscuro ? oscuro : !oscuro;
      final v = negro ? 0 : 255;
      out.setPixelRgb(x, y, v, v, v);
    }
  }
  return out;
}
