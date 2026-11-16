import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';

import '../utils/face_constants.dart';
import '../utils/face_math.dart';
import '../utils/yuv_converter.dart';
import 'rostro_detector.dart';
import 'rostro_embedder.dart';

class CapturaRostro {
  CapturaRostro({required this.detector, required this.embedder});

  final RostroDetector detector;
  final RostroEmbedder embedder;

  Future<
      ({
        Float32List? emb,
        Uint8List rgb,
        int ancho,
        int alto,
        Rect caja,
        int n,
        String guia
      })> tiro(
    CameraImage cam, {
    required int giro,
    required bool espejo,
    required bool exigirCentro,
    TiemposMotor? tiempos,
  }) async {
    Uint8List vacio() => Uint8List(0);
    final up = uprightSize(cam.width, cam.height, giro);
    final det = Stopwatch()..start();
    final nv21 = packNv21(cam);
    final rostros = await detector.detectar(
      nv21: nv21,
      anchoBuffer: cam.width,
      altoBuffer: cam.height,
      giro: giro,
      espejo: espejo,
    );
    det.stop();
    tiempos?.add('deteccion', det.elapsedMicroseconds / 1000);
    if (rostros.isEmpty) {
      return (
        emb: null,
        rgb: vacio(),
        ancho: 0,
        alto: 0,
        caja: Rect.zero,
        n: 0,
        guia: 'Buscando rostro'
      );
    }
    if (rostros.length > 1) {
      return (
        emb: null,
        rgb: vacio(),
        ancho: 0,
        alto: 0,
        caja: Rect.zero,
        n: rostros.length,
        guia: 'Una sola persona'
      );
    }
    final r = rostros.first;
    final guia = guiaEnrolar(
      caja: r.caja,
      yaw: r.yaw,
      pitch: r.pitch,
      ancho: up.ancho,
      alto: up.alto,
      exigirCentro: exigirCentro,
    );
    if (guia != null) {
      return (
        emb: null,
        rgb: vacio(),
        ancho: 0,
        alto: 0,
        caja: r.caja,
        n: 1,
        guia: guia
      );
    }
    final ali = Stopwatch()..start();
    final m = r.caja.width * 0.3;
    final reg = regionRgbUpright(
      cam,
      izq: r.caja.left - m,
      arriba: r.caja.top - m,
      ancho: r.caja.width + m * 2,
      alto: r.caja.height + m * 2,
      giro: giro,
      espejo: espejo,
    );
    final st = statsRegion(reg.rgb, reg.ancho, reg.alto);
    if (st.brillo < FaceConstants.brilloMin) {
      return (
        emb: null,
        rgb: vacio(),
        ancho: 0,
        alto: 0,
        caja: r.caja,
        n: 1,
        guia: 'Más luz'
      );
    }
    if (st.brillo > FaceConstants.brilloMax) {
      return (
        emb: null,
        rgb: vacio(),
        ancho: 0,
        alto: 0,
        caja: r.caja,
        n: 1,
        guia: 'Mucha luz'
      );
    }
    if (st.nitidez < FaceConstants.nitidezMin) {
      return (
        emb: null,
        rgb: vacio(),
        ancho: 0,
        alto: 0,
        caja: r.caja,
        n: 1,
        guia: 'Quédese quieto'
      );
    }
    final pts = [
      Offset(r.ojoIzq.dx - reg.dx, r.ojoIzq.dy - reg.dy),
      Offset(r.ojoDer.dx - reg.dx, r.ojoDer.dy - reg.dy),
      Offset(r.nariz.dx - reg.dx, r.nariz.dy - reg.dy),
      Offset(r.bocaIzq.dx - reg.dx, r.bocaIzq.dy - reg.dy),
      Offset(r.bocaDer.dx - reg.dx, r.bocaDer.dy - reg.dy),
    ];
    final entrada = warp112(reg.rgb, reg.ancho, reg.alto, pts);
    ali.stop();
    tiempos?.add('alineacion', ali.elapsedMicroseconds / 1000);
    final vec = Stopwatch()..start();
    final emb = await embedder.vector(entrada);
    vec.stop();
    tiempos?.add('vector', vec.elapsedMicroseconds / 1000);
    return (
      emb: emb,
      rgb: reg.rgb,
      ancho: reg.ancho,
      alto: reg.alto,
      caja: r.caja,
      n: 1,
      guia: ''
    );
  }
}
