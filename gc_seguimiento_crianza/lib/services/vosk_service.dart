import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

/// Servicio global para dictado por voz (VOSK). Inicializar desde Splash o Login
/// para tener el modelo listo al abrir el registro de necropsia.
class VoskService {
  static VoskService? _instance;
  static VoskService get instance => _instance ??= VoskService._();

  VoskService._();

  static const String _modelName = 'vosk-model-small-es-0.42';
  static const String _modelUrl =
      'https://alphacephei.com/vosk/models/vosk-model-small-es-0.42.zip';
  static const int _sampleRate = 16000;

  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  final ModelLoader _modelLoader = ModelLoader();
  final ValueNotifier<int> _notify = ValueNotifier(0);

  bool _isReady = false;
  bool _isLoading = false;
  String? _error;
  SpeechService? _speechService;
  // Retenidos para que no se liberen mientras _speechService esté activo
  // ignore: unused_field
  Model? _model;
  // ignore: unused_field
  Recognizer? _recognizer;

  bool get isReady => _isReady;
  bool get isLoading => _isLoading;
  String? get error => _error;
  SpeechService? get speechService => _speechService;

  void addListener(VoidCallback listener) => _notify.addListener(listener);
  void removeListener(VoidCallback listener) => _notify.removeListener(listener);

  /// Una sola ejecución de init por proceso; varias llamadas esperan el mismo Future.
  Future<void>? _initFuture;

  /// Carga el modelo de voz en español. Solo se ejecuta una vez; llamadas posteriores esperan el mismo resultado.
  Future<void> init() async {
    if (_isReady) return Future.value();
    if (_initFuture != null) return _initFuture!;
    _initFuture = _doInit();
    return _initFuture!;
  }

  /// Destruye el SpeechService nativo si quedó vivo de un hot restart anterior.
  Future<void> _destroySpeechService() async {
    try {
      await const MethodChannel('vosk_flutter')
          .invokeMethod('speechService.destroy');
    } catch (_) {
      // No existía (primera ejecución) o ya fue destruido: es esperado.
    }
  }

  Future<void> _doInit() async {
    if (_isLoading || _isReady) return;
    _isLoading = true;
    _error = null;
    _notify.value++;

    if (!Platform.isAndroid) {
      _isLoading = false;
      _error = 'Dictado por voz disponible solo en Android.';
      _notify.value++;
      return;
    }

    try {
      // Hot restart: el nativo conserva el SpeechService del arranque previo.
      // Destruirlo permite re-crearlo sin reiniciar la app.
      await _destroySpeechService();

      String modelPath;
      try {
        final list = await _modelLoader.loadModelsList();
        final candidates = list.where((m) => m.name == _modelName).toList();
        if (candidates.isEmpty) {
          modelPath = await _modelLoader.loadFromNetwork(_modelUrl);
        } else {
          modelPath = await _modelLoader.loadFromNetwork(candidates.first.url);
        }
      } catch (_) {
        modelPath = await _modelLoader.loadFromNetwork(_modelUrl);
      }
      final model = await _vosk.createModel(modelPath);
      final recognizer = await _vosk.createRecognizer(
        model: model,
        sampleRate: _sampleRate,
      );
      final speechService = await _vosk.initSpeechService(recognizer);

      _model = model;
      _recognizer = recognizer;
      _speechService = speechService;
      _isReady = true;
      _isLoading = false;
      _error = null;
      _notify.value++;
    } catch (e, st) {
      final isAlreadyExist = e is PlatformException &&
          (e.message?.contains('already exist') ?? false);
      _isLoading = false;
      if (isAlreadyExist) {
        // Caso límite: el destroy no llegó a ejecutarse o hubo una carrera.
        // Destruir de nuevo y reintentar una sola vez.
        await _destroySpeechService();
        _initFuture = null;
        try {
          await init();
        } catch (_) {}
      } else {
        _initFuture = null;
        // ignore: avoid_print
        print('VoskService init error: $e\n$st');
        _error = e.toString();
        _notify.value++;
      }
    }
  }
}
