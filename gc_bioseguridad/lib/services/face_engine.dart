import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as im;
import 'package:path_provider/path_provider.dart';

import '../utils/face_constants.dart';
import '../utils/face_math.dart';
import 'face_capture.dart';
import 'nomina_store.dart';
import 'rostro_detector.dart';
import 'rostro_embedder.dart';

enum EstadoFrame {
  sinRostro,
  multiples,
  guia,
  candidato,
  confirmado,
  ambiguo,
  noCoincide,
}

class FaceFrame {
  const FaceFrame({
    required this.estado,
    this.persona,
    this.similitud = 0,
    this.guia = '',
    this.votos = 0,
    this.rechazoFinal = false,
  });

  final EstadoFrame estado;
  final PersonaFace? persona;
  final double similitud;
  final String guia;
  final int votos;
  final bool rechazoFinal;
}

class FaceEngine {
  FaceEngine({
    required this.detector,
    required this.embedder,
    required this.nominas,
  }) : _captura = CapturaRostro(detector: detector, embedder: embedder);

  final RostroDetector detector;
  final RostroEmbedder embedder;
  final NominaStore nominas;
  final CapturaRostro _captura;

  double umbral = FaceConstants.umbralDefecto;
  double margen = FaceConstants.margenDefecto;
  String? doc11;
  bool _listo = false;

  bool get listo => _listo;

  final Votos _votos = Votos();
  int _rechazos = 0;
  final TiemposMotor tiempos = TiemposMotor();

  Future<void> inicializar() async {
    if (_listo) return;
    await detector.inicializar();
    await embedder.cargar();
    _listo = true;
  }

  void reset() {
    _votos.limpiar();
    _rechazos = 0;
  }

  Future<FaceFrame> procesar(
    CameraImage cam, {
    required int giro,
    required bool espejo,
  }) async {
    final t = await _captura.tiro(
      cam,
      giro: giro,
      espejo: espejo,
      exigirCentro: false,
      tiempos: tiempos,
    );
    final emb = t.emb;
    if (emb == null) {
      _votos.push(null);
      if (t.n == 0) {
        return const FaceFrame(
          estado: EstadoFrame.sinRostro,
          guia: 'Buscando rostro',
        );
      }
      if (t.n > 1) {
        return const FaceFrame(
          estado: EstadoFrame.multiples,
          guia: 'Una sola persona',
        );
      }
      return FaceFrame(estado: EstadoFrame.guia, guia: t.guia);
    }
    final cmp = Stopwatch()..start();
    final d = decidir(
      emb: emb,
      todas: nominas.personas,
      doc: doc11,
      umbral: umbral,
      margen: margen,
    );
    cmp.stop();
    tiempos.add('comparacion', cmp.elapsedMicroseconds / 1000);
    if (d.estado == DecisionEstado.ok && d.persona != null) {
      _votos.push(d.persona!.dni);
      _rechazos = 0;
      final n = _votos.contar(d.persona!.dni);
      if (n >= FaceConstants.votosRequeridos) {
        return FaceFrame(
          estado: EstadoFrame.confirmado,
          persona: d.persona,
          similitud: d.sim,
          votos: n,
        );
      }
      return FaceFrame(
        estado: EstadoFrame.candidato,
        persona: d.persona,
        similitud: d.sim,
        votos: n,
      );
    }
    _votos.push(null);
    if (d.estado == DecisionEstado.ambiguo) {
      _rechazos = 0;
      return FaceFrame(
        estado: EstadoFrame.ambiguo,
        persona: d.persona,
        similitud: d.sim,
      );
    }
    if (doc11 != null) {
      _rechazos++;
      if (_rechazos >= FaceConstants.rechazosFinal11) {
        return FaceFrame(
          estado: EstadoFrame.noCoincide,
          persona: d.persona,
          similitud: d.sim,
          rechazoFinal: true,
        );
      }
    }
    return FaceFrame(
      estado: EstadoFrame.noCoincide,
      persona: d.persona,
      similitud: d.sim,
    );
  }

  /// Vector de la foto de referencia (alta del personal). No guarda la foto.
  Future<Float32List?> vectorDeFoto(Uint8List bytes) async {
    if (!_listo) await inicializar();
    final decoded = im.decodeImage(bytes);
    if (decoded == null || decoded.width < 2 || decoded.height < 2) {
      return null;
    }
    final dir = await getTemporaryDirectory();
    final archivo = File(
      '${dir.path}/rostro_ref_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await archivo.writeAsBytes(bytes, flush: true);
    try {
      final caras = await detector.detectarArchivo(archivo.path);
      if (caras.isEmpty) return null;
      caras.sort((a, b) => b.caja.width.compareTo(a.caja.width));
      final r = caras.first;
      final rgb = Uint8List(decoded.width * decoded.height * 3);
      var i = 0;
      for (var y = 0; y < decoded.height; y++) {
        for (var x = 0; x < decoded.width; x++) {
          final p = decoded.getPixel(x, y);
          rgb[i++] = p.r.toInt();
          rgb[i++] = p.g.toInt();
          rgb[i++] = p.b.toInt();
        }
      }
      final entrada = warp112(rgb, decoded.width, decoded.height, [
        r.ojoIzq,
        r.ojoDer,
        r.nariz,
        r.bocaIzq,
        r.bocaDer,
      ]);
      final vector = await embedder.vector(entrada);
      return vector;
    } finally {
      if (await archivo.exists()) {
        await archivo.delete();
      }
    }
  }

  Future<void> cerrar() async {
    await detector.cerrar();
    await embedder.cerrar();
    _listo = false;
  }
}
