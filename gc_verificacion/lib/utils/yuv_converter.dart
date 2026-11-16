import 'dart:typed_data';

import 'package:camera/camera.dart';

({int giro, bool espejo}) uprightPara(int sensor) {
  return (giro: sensor % 360, espejo: false);
}

({int ancho, int alto}) uprightSize(int camW, int camH, int giro) {
  if (giro == 90 || giro == 270) return (ancho: camH, alto: camW);
  return (ancho: camW, alto: camH);
}

Uint8List packNv21(CameraImage cam) {
  final w = cam.width;
  final h = cam.height;
  if (cam.planes.length == 1) {
    return Uint8List.fromList(cam.planes[0].bytes);
  }
  final yP = cam.planes[0];
  final uP = cam.planes[1];
  final vP = cam.planes[2];
  final out = Uint8List(w * h + (w * h) ~/ 2);
  final strideY = yP.bytesPerRow ?? w;
  final yB = yP.bytes;
  for (var y = 0; y < h; y++) {
    out.setRange(y * w, y * w + w, yB, y * strideY);
  }
  final strideU = uP.bytesPerRow ?? (w ~/ 2);
  final strideV = vP.bytesPerRow ?? (w ~/ 2);
  final pixU = uP.bytesPerPixel ?? 1;
  final pixV = vP.bytesPerPixel ?? 1;
  final uB = uP.bytes;
  final vB = vP.bytes;
  var o = w * h;
  for (var y = 0; y < h ~/ 2; y++) {
    for (var x = 0; x < w ~/ 2; x++) {
      out[o++] = vB[y * strideV + x * pixV];
      out[o++] = uB[y * strideU + x * pixU];
    }
  }
  return out;
}

({Uint8List rgb, int ancho, int alto, double dx, double dy})
    regionRgbUpright(
  CameraImage cam, {
  required double izq,
  required double arriba,
  required double ancho,
  required double alto,
  required int giro,
  required bool espejo,
}) {
  final up = uprightSize(cam.width, cam.height, giro);
  final x0 = izq.floor().clamp(0, up.ancho - 1);
  final y0 = arriba.floor().clamp(0, up.alto - 1);
  final x1 = (izq + ancho).ceil().clamp(1, up.ancho);
  final y1 = (arriba + alto).ceil().clamp(1, up.alto);
  final rw = (x1 - x0).clamp(1, up.ancho);
  final rh = (y1 - y0).clamp(1, up.alto);
  final rgb = Uint8List(rw * rh * 3);
  final sw = cam.width;
  final sh = cam.height;
  if (cam.planes.length == 1) {
    _regionNv21(cam.planes[0].bytes, rgb, rw, rh, x0, y0, sw, sh, giro, espejo);
  } else {
    _regionYuv(cam, rgb, rw, rh, x0, y0, sw, sh, giro, espejo);
  }
  return (
    rgb: rgb,
    ancho: rw,
    alto: rh,
    dx: x0.toDouble(),
    dy: y0.toDouble(),
  );
}

void _pixel(
  Uint8List rgb,
  int o,
  int y,
  int u,
  int v,
) {
  final r = (y + 1.402 * v).round().clamp(0, 255);
  final g = (y - 0.344136 * u - 0.714136 * v).round().clamp(0, 255);
  final b = (y + 1.772 * u).round().clamp(0, 255);
  rgb[o] = r;
  rgb[o + 1] = g;
  rgb[o + 2] = b;
}

void _regionYuv(
  CameraImage cam,
  Uint8List rgb,
  int rw,
  int rh,
  int x0,
  int y0,
  int sw,
  int sh,
  int giro,
  bool espejo,
) {
  final yP = cam.planes[0];
  final uP = cam.planes[1];
  final vP = cam.planes[2];
  final strideY = yP.bytesPerRow ?? sw;
  final strideU = uP.bytesPerRow ?? (sw ~/ 2);
  final strideV = vP.bytesPerRow ?? (sw ~/ 2);
  final pixU = uP.bytesPerPixel ?? 1;
  final pixV = vP.bytesPerPixel ?? 1;
  final yB = yP.bytes;
  final uB = uP.bytes;
  final vB = vP.bytes;
  for (var y = 0; y < rh; y++) {
    for (var x = 0; x < rw; x++) {
      var sx = 0;
      var sy = 0;
      _invMap(x0 + x, y0 + y, sw, sh, giro, espejo, (a, b) {
        sx = a;
        sy = b;
      });
      final yy = yB[sy * strideY + sx];
      final uu = uB[(sy >> 1) * strideU + (sx >> 1) * pixU] - 128;
      final vv = vB[(sy >> 1) * strideV + (sx >> 1) * pixV] - 128;
      _pixel(rgb, (y * rw + x) * 3, yy, uu, vv);
    }
  }
}

void _regionNv21(
  Uint8List nv21,
  Uint8List rgb,
  int rw,
  int rh,
  int x0,
  int y0,
  int sw,
  int sh,
  int giro,
  bool espejo,
) {
  final wh = sw * sh;
  for (var y = 0; y < rh; y++) {
    for (var x = 0; x < rw; x++) {
      var sx = 0;
      var sy = 0;
      _invMap(x0 + x, y0 + y, sw, sh, giro, espejo, (a, b) {
        sx = a;
        sy = b;
      });
      final yy = nv21[sy * sw + sx];
      final vu = wh + (sy >> 1) * sw + (sx >> 1) * 2;
      final vv = nv21[vu] - 128;
      final uu = nv21[vu + 1] - 128;
      _pixel(rgb, (y * rw + x) * 3, yy, uu, vv);
    }
  }
}

void _invMap(
  int ux,
  int uy,
  int sw,
  int sh,
  int giro,
  bool espejo,
  void Function(int sx, int sy) out,
) {
  var sx = 0;
  var sy = 0;
  switch (giro) {
    case 90:
      sx = uy;
      sy = sh - 1 - ux;
    case 180:
      sx = sw - 1 - ux;
      sy = sh - 1 - uy;
    case 270:
      sx = sw - 1 - uy;
      sy = ux;
    default:
      sx = ux;
      sy = uy;
  }
  if (espejo) sx = sw - 1 - sx;
  out(sx.clamp(0, sw - 1), sy.clamp(0, sh - 1));
}
