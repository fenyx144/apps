import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import '../services/nomina_store.dart';
import 'face_constants.dart';

const List<List<double>> tpl112 = [
  [38.2946, 51.6963],
  [73.5318, 51.5014],
  [56.0252, 71.7366],
  [41.5493, 92.3655],
  [70.7299, 92.2041],
];

List<double> similarSrcDst(List<Offset> src, List<List<double>> dst) {
  final n = src.length;
  var sx = 0.0;
  var sy = 0.0;
  var dx = 0.0;
  var dy = 0.0;
  for (var i = 0; i < n; i++) {
    sx += src[i].dx;
    sy += src[i].dy;
    dx += dst[i][0];
    dy += dst[i][1];
  }
  sx /= n;
  sy /= n;
  dx /= n;
  dy /= n;
  var a = 0.0;
  var b = 0.0;
  var v = 0.0;
  for (var i = 0; i < n; i++) {
    final x = src[i].dx - sx;
    final y = src[i].dy - sy;
    final u = dst[i][0] - dx;
    final w = dst[i][1] - dy;
    a += x * u + y * w;
    b += x * w - y * u;
    v += x * x + y * y;
  }
  if (v == 0) return [1, 0, 0, 1, 0, 0];
  final ca = a / v;
  final sb = b / v;
  return [
    ca,
    sb,
    -sb,
    ca,
    dx - (ca * sx - sb * sy),
    dy - (sb * sx + ca * sy),
  ];
}

Float32List warp112(
  Uint8List rgb,
  int w,
  int h,
  List<Offset> src,
) {
  final m = similarSrcDst(src, tpl112);
  final a = m[0];
  final b = m[1];
  final c = m[2];
  final d = m[3];
  final tx = m[4];
  final ty = m[5];
  final det = a * d - b * c;
  const n = 112 * 112;
  final out = Float32List(3 * n);
  if (det == 0) return out;
  for (var yy = 0; yy < 112; yy++) {
    for (var xx = 0; xx < 112; xx++) {
      final x = (d * (xx - tx) - c * (yy - ty)) / det;
      final y = (-b * (xx - tx) + a * (yy - ty)) / det;
      final x0 = x.floor().clamp(0, w - 1);
      final y0 = y.floor().clamp(0, h - 1);
      final x1 = (x0 + 1).clamp(0, w - 1);
      final y1 = (y0 + 1).clamp(0, h - 1);
      final fx = (x - x.floor()).clamp(0.0, 1.0);
      final fy = (y - y.floor()).clamp(0.0, 1.0);
      final i = yy * 112 + xx;
      for (var ch = 0; ch < 3; ch++) {
        final p00 = rgb[(y0 * w + x0) * 3 + ch].toDouble();
        final p10 = rgb[(y0 * w + x1) * 3 + ch].toDouble();
        final p01 = rgb[(y1 * w + x0) * 3 + ch].toDouble();
        final p11 = rgb[(y1 * w + x1) * 3 + ch].toDouble();
        final v = p00 * (1 - fx) * (1 - fy) +
            p10 * fx * (1 - fy) +
            p01 * (1 - fx) * fy +
            p11 * fx * fy;
        out[ch * n + i] = (v - 127.5) / 127.5;
      }
    }
  }
  return out;
}

Float32List normalizar(List<double> v) {
  var s = 0.0;
  for (final x in v) {
    s += x * x;
  }
  final out = Float32List(v.length);
  final n = sqrt(s);
  if (n == 0) return out;
  for (var i = 0; i < v.length; i++) {
    out[i] = v[i] / n;
  }
  return out;
}

double coseno(Float32List a, Float32List b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

enum DecisionEstado { ok, ambiguo, no }

({PersonaFace? persona, double sim, double segundo, DecisionEstado estado})
    decidir({
  required Float32List emb,
  required List<PersonaFace> todas,
  String? doc,
  required double umbral,
  required double margen,
}) {
  const vacio =
      (persona: null, sim: 0.0, segundo: 0.0, estado: DecisionEstado.no);
  if (todas.isEmpty) return vacio;
  final base =
      doc == null ? todas : todas.where((p) => p.dni == doc).toList();
  if (base.isEmpty) return vacio;
  PersonaFace? best;
  var bs = -2.0;
  for (final p in base) {
    final s = coseno(emb, p.vector);
    if (s > bs) {
      bs = s;
      best = p;
    }
  }
  var second = 0.0;
  if (doc == null) {
    var s2 = -2.0;
    for (final p in todas) {
      if (p.dni == best!.dni) continue;
      final s = coseno(emb, p.vector);
      if (s > s2) s2 = s;
    }
    if (s2 > -1) second = s2;
  } else {
    for (final p in todas) {
      if (p.dni == doc) continue;
      final s = coseno(emb, p.vector);
      if (s > second) second = s;
    }
  }
  final estado = bs >= umbral && bs - second >= margen
      ? DecisionEstado.ok
      : bs >= umbral
          ? DecisionEstado.ambiguo
          : DecisionEstado.no;
  return (persona: best, sim: bs, segundo: second, estado: estado);
}

String? guiaEnrolar({
  required Rect caja,
  required double yaw,
  required double pitch,
  required int ancho,
  required int alto,
  required bool exigirCentro,
}) {
  if (yaw.abs() > FaceConstants.giroMaxGrados ||
      pitch.abs() > FaceConstants.giroMaxGrados) {
    return 'Mire de frente';
  }
  if (caja.width < ancho * FaceConstants.boxMinFrac) {
    return 'Acérquese';
  }
  if (exigirCentro) {
    final cx = (caja.left + caja.width / 2) / ancho;
    final cy = (caja.top + caja.height / 2) / alto;
    if ((cx - 0.5).abs() > FaceConstants.centroXTol ||
        (cy - 0.5).abs() > FaceConstants.centroYTol) {
      return 'Centre el rostro';
    }
  }
  return null;
}

class Votos {
  final _h = <String?>[];

  void push(String? doc) {
    _h.add(doc);
    if (_h.length > FaceConstants.ventanaVotos) _h.removeAt(0);
  }

  int contar(String doc) => _h.where((e) => e == doc).length;

  void limpiar() => _h.clear();
}

class TiemposMotor {
  final _ms = <String, List<double>>{};

  void add(String etapa, double ms) {
    final l = _ms.putIfAbsent(etapa, () => []);
    l.add(ms);
    if (l.length > 120) l.removeAt(0);
  }

  double mediana(String etapa) => _cuantil(etapa, 0.5);

  double p95(String etapa) => _cuantil(etapa, 0.95);

  int n(String etapa) => _ms[etapa]?.length ?? 0;

  double _cuantil(String etapa, double q) {
    final l = _ms[etapa];
    if (l == null || l.isEmpty) return 0;
    final s = List<double>.from(l)..sort();
    final pos = (q * (s.length - 1)).round().clamp(0, s.length - 1);
    return s[pos];
  }

  void limpiar() => _ms.clear();
}

({double brillo, double nitidez}) statsRegion(
  Uint8List rgb,
  int w,
  int h,
) {
  final n = w * h;
  final g = Float32List(n);
  var sum = 0.0;
  for (var i = 0; i < n; i++) {
    final v = 0.299 * rgb[i * 3] +
        0.587 * rgb[i * 3 + 1] +
        0.114 * rgb[i * 3 + 2];
    g[i] = v;
    sum += v;
  }
  var ls = 0.0;
  var ls2 = 0.0;
  var c = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final l = g[i - 1] + g[i + 1] + g[i - w] + g[i + w] - 4 * g[i];
      ls += l;
      ls2 += l * l;
      c++;
    }
  }
  if (c == 0) return (brillo: sum / n, nitidez: 0);
  final media = ls / c;
  return (brillo: sum / n, nitidez: ls2 / c - media * media);
}
