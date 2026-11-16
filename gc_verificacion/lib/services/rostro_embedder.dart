import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../utils/face_math.dart';

abstract class RostroEmbedder {
  Future<void> cargar();
  Future<Float32List> vector(Float32List entrada);
  Future<void> cerrar();
}

class OnnxRostroEmbedder implements RostroEmbedder {
  OnnxRostroEmbedder({this.asset = 'assets/models/w600k_mbf.onnx'});

  final String asset;
  OrtSession? _sesion;

  @override
  Future<void> cargar() async {
    await cerrar();
    _sesion = await OnnxRuntime().createSessionFromAsset(asset);
  }

  @override
  Future<Float32List> vector(Float32List entrada) async {
    final s = _sesion;
    if (s == null) throw StateError('modelo no cargado');
    final input = await OrtValue.fromList(entrada.toList(), [1, 3, 112, 112]);
    try {
      final salidas = await s.run({s.inputNames.first: input});
      final v = await salidas[s.outputNames.first]!.asFlattenedList();
      final nums = [for (final e in v) (e as num).toDouble()];
      for (final o in salidas.values) {
        await o.dispose();
      }
      return normalizar(nums);
    } finally {
      await input.dispose();
    }
  }

  @override
  Future<void> cerrar() async {
    await _sesion?.close();
    _sesion = null;
  }
}
