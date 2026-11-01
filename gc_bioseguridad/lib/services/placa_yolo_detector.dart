import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

/// Detección con confianza (caja normalizada 0–1).
class PlacaYoloHit {
  const PlacaYoloHit({
    required this.normalizedBox,
    required this.confidence,
  });

  final Rect normalizedBox;
  final double confidence;
}

/// Detección de la placa con YOLO (TFLite) antes del OCR con ML Kit.
///
/// Modelo: [assetPath] (export Ultralytics → LiteRT/TFLite). Si falla la carga,
/// la pantalla de cámara sigue con el recorte del marco guía.
class PlacaYoloDetector {
  PlacaYoloDetector._();

  static final PlacaYoloDetector instance = PlacaYoloDetector._();

  static const String assetPath = 'assets/models/placa_yolo.tflite';

  YOLO? _yolo;
  bool _ready = false;
  bool _failed = false;

  bool get isReady => _ready;

  /// Precarga el modelo (Android: LiteRT). En iOS hace falta Core ML aparte.
  Future<bool> warmUp() async {
    if (_ready) return true;
    if (_failed) return false;
    try {
      _yolo ??= YOLO(
        modelPath: assetPath,
        task: YOLOTask.detect,
        useGpu: false,
      );
      _ready = await _yolo!.loadModel();
      if (!_ready) _failed = true;
      return _ready;
    } catch (e, st) {
      debugPrint('[placa-yolo] carga fallida: $e\n$st');
      _failed = true;
      return false;
    }
  }

  Future<PlacaYoloHit?> detectBestHit(
    Uint8List jpegBytes, {
    double minConfidence = 0.35,
  }) async {
    if (!await warmUp()) return null;
    final yolo = _yolo;
    if (yolo == null) return null;
    try {
      final out = await yolo.predict(
        jpegBytes,
        confidenceThreshold: minConfidence,
        iouThreshold: 0.45,
      );
      final list = out['detections'];
      if (list is! List || list.isEmpty) return null;

      YOLOResult? best;
      for (final item in list) {
        if (item is! Map) continue;
        final d = YOLOResult.fromMap(item);
        final box = d.normalizedBox;
        if (box.width <= 0 || box.height <= 0) continue;
        if (best == null || d.confidence > best.confidence) {
          best = d;
        }
      }
      if (best == null) return null;
      return PlacaYoloHit(
        normalizedBox: best.normalizedBox,
        confidence: best.confidence,
      );
    } catch (e, st) {
      debugPrint('[placa-yolo] inferencia: $e\n$st');
      return null;
    }
  }

  /// Caja normalizada (0–1) de la detección más confiable.
  Future<Rect?> detectBestBox(
    Uint8List jpegBytes, {
    double minConfidence = 0.35,
  }) async {
    final hit = await detectBestHit(
      jpegBytes,
      minConfidence: minConfidence,
    );
    return hit?.normalizedBox;
  }
}
