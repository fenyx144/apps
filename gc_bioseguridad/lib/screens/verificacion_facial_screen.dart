import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/face_engine.dart';
import '../services/nomina_facial_sync.dart';
import '../services/nomina_store.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/face_constants.dart';
import '../utils/yuv_converter.dart';

class VerificacionFacialResult {
  const VerificacionFacialResult({required this.dni, required this.nombre});

  final String dni;
  final String nombre;
}

/// Escaneo facial de ingreso. Devuelve la persona o `null` si se cancela
/// o se elige identificar por documento.
class VerificacionFacialScreen extends StatefulWidget {
  const VerificacionFacialScreen({super.key});

  @override
  State<VerificacionFacialScreen> createState() =>
      _VerificacionFacialScreenState();
}

class _VerificacionFacialScreenState extends State<VerificacionFacialScreen> {
  CameraController? _cam;
  FaceEngine? _engine;
  bool _listo = false;
  bool _ocupado = false;
  bool _saliendo = false;
  int _fallos = 0;
  int _giro = 0;
  bool _espejo = true;
  String _estado = 'Iniciando';
  bool _sincronizando = false;

  @override
  void initState() {
    super.initState();
    _arrancar();
  }

  @override
  void dispose() {
    final cam = _cam;
    _cam = null;
    if (cam != null) {
      unawaited(cam.dispose());
    }
    super.dispose();
  }

  Future<void> _arrancar() async {
    final storage = context.read<StorageService>();
    final store = context.read<NominaStore>();
    final engine = context.read<FaceEngine>();
    try {
      await store.load(clave: NominaFacialSync.clavePara(storage));
      setState(() => _sincronizando = true);
      await NominaFacialSync().sync(
        storage: storage,
        store: store,
        engine: engine,
      );
      if (!mounted) return;
      setState(() => _sincronizando = false);
      if (store.total == 0) {
        setState(() => _estado = 'Sin nómina');
        return;
      }
      engine.umbral = FaceConstants.umbralDefecto;
      engine.margen = FaceConstants.margenDefecto;
      await engine.inicializar();
      engine.reset();
      final cams = await availableCameras();
      if (cams.isEmpty) throw CameraException('sin_camara', 'Sin cámara');
      final frontal = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      final cam = CameraController(
        frontal,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await cam.initialize();
      final u = uprightPara(frontal.sensorOrientation);
      if (!mounted) {
        await cam.dispose();
        return;
      }
      setState(() {
        _cam = cam;
        _engine = engine;
        _giro = u.giro;
        _espejo = u.espejo;
        _listo = true;
        _estado = 'Buscando';
      });
      await cam.startImageStream(_onFrame);
    } catch (_) {
      if (!mounted) return;
      setState(() => _estado = 'Sin cámara');
    }
  }

  Future<void> _onFrame(CameraImage img) async {
    final eng = _engine;
    if (!_listo || _ocupado || _saliendo || eng == null) return;
    _ocupado = true;
    try {
      final f = await eng.procesar(img, giro: _giro, espejo: _espejo);
      if (!mounted || _saliendo) return;
      _fallos = 0;
      if (f.estado == EstadoFrame.confirmado && f.persona != null) {
        _salir(
          VerificacionFacialResult(
            dni: f.persona!.dni,
            nombre: f.persona!.nombre,
          ),
        );
        return;
      }
      final texto = switch (f.estado) {
        EstadoFrame.sinRostro => 'Buscando',
        EstadoFrame.multiples || EstadoFrame.guia =>
          f.guia.isEmpty ? 'Buscando' : f.guia,
        EstadoFrame.candidato => f.persona?.nombre ?? 'Analizando',
        EstadoFrame.ambiguo || EstadoFrame.noCoincide => 'Sin coincidencia',
        EstadoFrame.confirmado => f.persona?.nombre ?? '',
      };
      if (texto != _estado) setState(() => _estado = texto);
    } catch (_) {
      _fallos++;
      if (_fallos >= 20 && mounted && _estado != 'Reintentando') {
        setState(() => _estado = 'Reintentando');
        _fallos = 0;
      }
    } finally {
      _ocupado = false;
    }
  }

  Future<void> _salir(VerificacionFacialResult? r) async {
    if (_saliendo) return;
    _saliendo = true;
    final cam = _cam;
    if (cam != null && cam.value.isStreamingImages) {
      try {
        await cam.stopImageStream();
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.of(context).pop(r);
  }

  @override
  Widget build(BuildContext context) {
    final cam = _cam;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Verificación facial'),
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (cam != null && cam.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: cam.value.previewSize?.height ?? 1,
                height: cam.value.previewSize?.width ?? 1,
                child: CameraPreview(cam),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _sincronizando ? 'Actualizando' : _estado,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => _salir(null),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white70),
                        ),
                        child: const Text('Documento'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
