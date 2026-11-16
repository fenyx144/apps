import 'dart:typed_data';
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class RostroDetectado {
  const RostroDetectado({
    required this.caja,
    required this.ojoIzq,
    required this.ojoDer,
    required this.nariz,
    required this.bocaIzq,
    required this.bocaDer,
    required this.yaw,
    required this.pitch,
  });

  final Rect caja;
  final Offset ojoIzq;
  final Offset ojoDer;
  final Offset nariz;
  final Offset bocaIzq;
  final Offset bocaDer;
  final double yaw;
  final double pitch;
}

class RostroDetector {
  FaceDetector? _detector;

  Future<void> inicializar() async {
    await cerrar();
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableClassification: false,
        enableTracking: true,
        minFaceSize: 0.1,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
  }

  /// Foto ya guardada (alta de personal). Las coordenadas salen en el
  /// espacio de la imagen, sin giro de cámara.
  Future<List<RostroDetectado>> detectarArchivo(String path) async {
    final d = _detector;
    if (d == null) return [];
    final input = InputImage.fromFilePath(path);
    final caras = await d.processImage(input);
    final out = <RostroDetectado>[];
    for (final f in caras) {
      final r = _mapear(f, 1, 1, 0, false);
      if (r != null) out.add(r);
    }
    return out;
  }

  Future<List<RostroDetectado>> detectar({
    required Uint8List nv21,
    required int anchoBuffer,
    required int altoBuffer,
    required int giro,
    required bool espejo,
  }) async {
    final d = _detector;
    if (d == null) return [];
    final rot = switch (giro) {
      90 => InputImageRotation.rotation90deg,
      180 => InputImageRotation.rotation180deg,
      270 => InputImageRotation.rotation270deg,
      _ => InputImageRotation.rotation0deg,
    };
    final input = InputImage.fromBytes(
      bytes: nv21,
      metadata: InputImageMetadata(
        size: Size(anchoBuffer.toDouble(), altoBuffer.toDouble()),
        rotation: rot,
        format: InputImageFormat.nv21,
        bytesPerRow: anchoBuffer,
      ),
    );
    final caras = await d.processImage(input);
    final out = <RostroDetectado>[];
    for (final f in caras) {
      final r = _mapear(f, anchoBuffer, altoBuffer, giro, espejo);
      if (r != null) out.add(r);
    }
    return out;
  }

  Offset _punto(
    double x,
    double y,
    int sw,
    int sh,
    int giro,
    bool espejo,
  ) {
    final sx = espejo ? sw - 1 - x : x;
    switch (giro) {
      case 90:
        return Offset(sh - 1 - y, sx);
      case 180:
        return Offset(sw - 1 - sx, sh - 1 - y);
      case 270:
        return Offset(y, sw - 1 - sx);
      default:
        return Offset(sx, y);
    }
  }

  RostroDetectado? _mapear(
    Face f,
    int sw,
    int sh,
    int giro,
    bool espejo,
  ) {
    Offset mapPoint(double x, double y) =>
        _punto(x, y, sw, sh, giro, espejo);
    final b = f.boundingBox;
    final p1 = mapPoint(b.left, b.top);
    final p2 = mapPoint(b.right, b.bottom);
    final ojoA = f.landmarks[FaceLandmarkType.leftEye]?.position;
    final ojoB = f.landmarks[FaceLandmarkType.rightEye]?.position;
    final nariz = f.landmarks[FaceLandmarkType.noseBase]?.position;
    final bocaA = f.landmarks[FaceLandmarkType.leftMouth]?.position;
    final bocaB = f.landmarks[FaceLandmarkType.rightMouth]?.position;
    if (ojoA == null ||
        ojoB == null ||
        nariz == null ||
        bocaA == null ||
        bocaB == null) {
      return null;
    }
    final ojos = [
      mapPoint(ojoA.x.toDouble(), ojoA.y.toDouble()),
      mapPoint(ojoB.x.toDouble(), ojoB.y.toDouble()),
    ]..sort((a, b) => a.dx.compareTo(b.dx));
    final bocas = [
      mapPoint(bocaA.x.toDouble(), bocaA.y.toDouble()),
      mapPoint(bocaB.x.toDouble(), bocaB.y.toDouble()),
    ]..sort((a, b) => a.dx.compareTo(b.dx));
    return RostroDetectado(
      caja: Rect.fromPoints(p1, p2),
      ojoIzq: ojos[0],
      ojoDer: ojos[1],
      nariz: mapPoint(nariz.x.toDouble(), nariz.y.toDouble()),
      bocaIzq: bocas[0],
      bocaDer: bocas[1],
      yaw: f.headEulerAngleY ?? 0,
      pitch: f.headEulerAngleX ?? 0,
    );
  }

  Future<void> cerrar() async {
    await _detector?.close();
    _detector = null;
  }
}
