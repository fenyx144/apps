import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';

import '../utils/constants.dart';
import 'storage_service.dart';

class AvisosService {
  AvisosService(this._storage);

  final StorageService _storage;
  AudioPlayer? _player;
  FlutterTts? _tts;
  bool _audioOk = true;
  bool _vozOk = true;
  bool _vibra = false;

  Future<void> inicializar() async {
    _player = AudioPlayer();
    final tts = FlutterTts();
    _tts = tts;
    try {
      await tts.setLanguage('es');
      await tts.setSpeechRate(AppConstants.vozVelocidad);
    } catch (_) {
      _vozOk = false;
    }
    try {
      _vibra = await Vibration.hasVibrator() ?? false;
    } catch (_) {
      _vibra = false;
    }
  }

  Future<void> aprobado(String nombre) async {
    await _sonar('sounds/ok.wav');
    _vibrar();
    await _hablar('Acceso permitido, $nombre');
  }

  Future<void> rechazo() async {
    await _sonar('sounds/fail.wav');
    _vibrar();
    await _hablar('No coincide');
  }

  Future<void> _sonar(String asset) async {
    final p = _player;
    if (!_audioOk || p == null || !_storage.getSonido()) return;
    try {
      await p.stop();
      await p.play(AssetSource(asset));
    } catch (_) {
      _audioOk = false;
    }
  }

  Future<void> _hablar(String texto) async {
    final tts = _tts;
    if (!_vozOk || tts == null || !_storage.getVoz()) return;
    try {
      await tts.stop();
      // Algunos motores descartan la velocidad fijada al iniciar.
      await tts.setSpeechRate(AppConstants.vozVelocidad);
      await tts.speak(texto);
    } catch (_) {
      _vozOk = false;
    }
  }

  void _vibrar() {
    if (_vibra && _storage.getVibracion()) {
      Vibration.vibrate(duration: 40);
    }
  }

  Future<void> dispose() async {
    await _player?.dispose();
    await _tts?.stop();
    _player = null;
    _tts = null;
  }
}
