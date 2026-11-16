import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/face_engine.dart';
import '../services/nomina_facial_sync.dart';
import '../services/nomina_store.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/documento_scan_flow.dart';
import '../utils/face_constants.dart';
import '../utils/yuv_converter.dart';

class VerificacionFacialResult {
  const VerificacionFacialResult({required this.dni, required this.nombre});

  final String dni;
  final String nombre;
}

/// Identifica a cualquier persona de la nómina: lista, DNI o rostro
/// contra la foto ya registrada. Sin foto, sigue solo con el documento.
class VerificacionFacialScreen extends StatefulWidget {
  const VerificacionFacialScreen({super.key});

  @override
  State<VerificacionFacialScreen> createState() =>
      _VerificacionFacialScreenState();
}

class _VerificacionFacialScreenState extends State<VerificacionFacialScreen> {
  final _busqueda = TextEditingController();
  List<PersonaReferencia> _todos = const [];
  String _q = '';
  bool _cargando = true;
  PersonaReferencia? _cara;

  CameraController? _cam;
  FaceEngine? _engine;
  bool _listo = false;
  bool _ocupado = false;
  bool _saliendo = false;
  int _fallos = 0;
  int _giro = 0;
  bool _espejo = true;
  String _estado = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    final cam = _cam;
    _cam = null;
    if (cam != null) unawaited(cam.dispose());
    super.dispose();
  }

  Future<void> _cargar() async {
    final storage = context.read<StorageService>();
    var lista = NominaFacialSync().locales(storage);
    if (lista.isEmpty) {
      await NominaFacialSync().descargarLista(storage);
      if (!mounted) return;
      lista = NominaFacialSync().locales(storage);
    } else {
      unawaited(NominaFacialSync().descargarLista(storage).then((_) {
        if (!mounted) return;
        setState(() => _todos = NominaFacialSync().locales(storage));
      }));
    }
    if (!mounted) return;
    setState(() {
      _todos = lista;
      _cargando = false;
    });
  }

  List<PersonaReferencia> get _filtrados {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return _todos;
    return [
      for (final p in _todos)
        if (p.nombre.toLowerCase().contains(q) || p.dni.contains(q)) p,
    ];
  }

  Future<void> _escanear() async {
    final doc = await escanearDocumentoPersona(context);
    if (doc == null || !mounted) return;
    final dni = doc.replaceAll(RegExp(r'\D'), '');
    PersonaReferencia? persona;
    for (final p in _todos) {
      if (p.dni == dni) {
        persona = p;
        break;
      }
    }
    if (persona == null) {
      Navigator.of(context).pop(
        VerificacionFacialResult(dni: dni, nombre: ''),
      );
      return;
    }
    await _elegir(persona);
  }

  Future<void> _elegir(PersonaReferencia persona) async {
    if (!persona.tieneFoto) {
      Navigator.of(context).pop(
        VerificacionFacialResult(dni: persona.dni, nombre: persona.nombre),
      );
      return;
    }
    final storage = context.read<StorageService>();
    final store = context.read<NominaStore>();
    final engine = context.read<FaceEngine>();
    setState(() {
      _cara = persona;
      _estado = 'Foto';
    });
    var lista = false;
    try {
      lista = await NominaFacialSync().prepararRostro(
        storage: storage,
        store: store,
        engine: engine,
        persona: persona,
      );
    } catch (_) {
      lista = false;
    }
    if (!mounted) return;
    if (!lista) {
      setState(() => _estado = 'Sin foto');
      return;
    }
    await _abrirCamara(engine, persona.dni);
  }

  Future<void> _abrirCamara(FaceEngine engine, String dni) async {
    try {
      engine.umbral = FaceConstants.umbralDefecto;
      engine.margen = FaceConstants.margenDefecto;
      engine.doc11 = dni;
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
    final persona = _cara;
    if (!_listo || _ocupado || _saliendo || eng == null || persona == null) {
      return;
    }
    _ocupado = true;
    try {
      final f = await eng.procesar(img, giro: _giro, espejo: _espejo);
      if (!mounted || _saliendo) return;
      _fallos = 0;
      if (f.estado == EstadoFrame.confirmado && f.persona != null) {
        await _salir(
          VerificacionFacialResult(
            dni: f.persona!.dni,
            nombre: f.persona!.nombre.isNotEmpty
                ? f.persona!.nombre
                : persona.nombre,
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

  void _continuarDocumento() {
    final p = _cara;
    if (p == null) return;
    unawaited(
      _salir(VerificacionFacialResult(dni: p.dni, nombre: p.nombre)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cara != null) return _camara();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verificación facial'),
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _busqueda,
                    decoration: const InputDecoration(
                      labelText: 'DNI o nombre',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _q = v),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _escanear,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  color: AppColors.primaryDark,
                ),
              ],
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _filtrados.length,
                    itemBuilder: (context, i) {
                      final p = _filtrados[i];
                      return ListTile(
                        title: Text(p.nombre),
                        subtitle: Text(p.dni),
                        trailing: Icon(
                          p.tieneFoto
                              ? Icons.face_retouching_natural
                              : Icons.badge_outlined,
                          color: AppColors.primaryDark,
                        ),
                        onTap: () => _elegir(p),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _camara() {
    final cam = _cam;
    final sinFoto = _estado == 'Sin foto';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_cara?.nombre ?? 'Verificación facial'),
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            final cam = _cam;
            if (cam != null && cam.value.isStreamingImages) {
              try {
                await cam.stopImageStream();
              } catch (_) {}
            }
            _engine?.doc11 = null;
            setState(() {
              _cara = null;
              _listo = false;
              _cam = null;
              _estado = '';
            });
            if (cam != null) unawaited(cam.dispose());
          },
        ),
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
                    if (_estado.isNotEmpty)
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
                          _estado,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (sinFoto) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _continuarDocumento,
                          child: const Text('DNI'),
                        ),
                      ),
                    ],
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
