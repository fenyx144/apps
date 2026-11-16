import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as im;

import '../services/api_service.dart';
import '../services/bio_empresa_api.dart';
import '../services/rostro_detector.dart';
import '../utils/constants.dart';
import '../utils/documento_scan_flow.dart';
import '../utils/yuv_converter.dart';

class VerificacionFacialResult {
  const VerificacionFacialResult({
    required this.dni,
    required this.nombre,
    required this.verificado,
  });

  final String dni;
  final String nombre;

  /// false: seguir el ingreso marcado como sin verificación facial.
  final bool verificado;
}

class _Sugerencia {
  const _Sugerencia({required this.dni, required this.nombre});

  final String dni;
  final String nombre;
}

/// Captura la foto y la envía al servidor. La lista de personal solo
/// autocompleta el DNI; no hace falta para verificar.
class VerificacionFacialScreen extends StatefulWidget {
  const VerificacionFacialScreen({super.key});

  @override
  State<VerificacionFacialScreen> createState() =>
      _VerificacionFacialScreenState();
}

class _VerificacionFacialScreenState extends State<VerificacionFacialScreen> {
  final _dniCtrl = TextEditingController();
  final _detector = RostroDetector();
  List<_Sugerencia> _sugerencias = const [];
  String _estado = '';
  bool _enviando = false;
  CameraController? _cam;
  bool _ocupado = false;
  int _giro = 0;
  bool _espejo = true;
  int _rostros = 0;

  @override
  void initState() {
    super.initState();
    _sugerir();
  }

  @override
  void dispose() {
    _dniCtrl.dispose();
    final cam = _cam;
    _cam = null;
    if (cam != null) unawaited(cam.dispose());
    unawaited(_detector.cerrar());
    super.dispose();
  }

  Future<void> _sugerir() async {
    try {
      final filas = await BioEmpresaApi().listarPersonalActivo();
      if (!mounted) return;
      setState(() {
        _sugerencias = [
          for (final e in filas)
            if (_dniDe(e).isNotEmpty)
              _Sugerencia(dni: _dniDe(e), nombre: _nombreDe(e)),
        ];
      });
    } catch (_) {}
  }

  String _dniDe(Map<String, dynamic> e) =>
      (e['dni'] ?? '').toString().replaceAll(RegExp(r'\D'), '');

  String _nombreDe(Map<String, dynamic> e) {
    final nombre = (e['nombre'] ?? '').toString().trim();
    if (nombre.isNotEmpty) return nombre;
    return '${e['nombres'] ?? ''} ${e['apellidos'] ?? ''}'.trim();
  }

  String get _dni => _dniCtrl.text.replaceAll(RegExp(r'\D'), '');

  List<_Sugerencia> get _filtradas {
    final q = _dniCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _sugerencias.take(8).toList();
    return [
      for (final s in _sugerencias)
        if (s.dni.contains(q) || s.nombre.toLowerCase().contains(q)) s,
    ].take(8).toList();
  }

  Future<void> _escanear() async {
    final doc = await escanearDocumentoPersona(context);
    if (doc == null || !mounted) return;
    setState(() => _dniCtrl.text = doc.replaceAll(RegExp(r'\D'), ''));
  }

  Future<void> _verificar() async {
    final dni = _dni;
    if (dni.length < 6) {
      setState(() => _estado = 'DNI');
      return;
    }
    setState(() {
      _enviando = true;
      _estado = 'Buscando';
      _rostros = 0;
    });
    try {
      await _detector.inicializar();
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
      _giro = u.giro;
      _espejo = u.espejo;
      setState(() => _cam = cam);
      await cam.startImageStream(_onFrame);
    } catch (_) {
      if (!mounted) return;
      _terminar(
        verificado: false,
        nombre: _nombreLocal(dni),
      );
    }
  }

  String _nombreLocal(String dni) {
    for (final s in _sugerencias) {
      if (s.dni == dni && s.nombre.isNotEmpty) return s.nombre;
    }
    return '';
  }

  Future<void> _onFrame(CameraImage img) async {
    if (_ocupado || _cam == null) return;
    _ocupado = true;
    try {
      final nv21 = packNv21(img);
      final caras = await _detector.detectar(
        nv21: nv21,
        anchoBuffer: img.width,
        altoBuffer: img.height,
        giro: _giro,
        espejo: _espejo,
      );
      if (!mounted || _cam == null) return;
      if (caras.length != 1) {
        _rostros = 0;
        setState(() => _estado = caras.isEmpty ? 'Buscando' : 'Una sola persona');
        return;
      }
      _rostros++;
      if (_rostros < 3) return;
      final caja = caras.first.caja;
      final m = caja.width * 0.25;
      final reg = regionRgbUpright(
        img,
        izq: caja.left - m,
        arriba: caja.top - m,
        ancho: caja.width + m * 2,
        alto: caja.height + m * 2,
        giro: _giro,
        espejo: _espejo,
      );
      final jpeg = _jpeg(reg.rgb, reg.ancho, reg.alto);
      final cam = _cam;
      _cam = null;
      if (cam != null) {
        if (cam.value.isStreamingImages) {
          try {
            await cam.stopImageStream();
          } catch (_) {}
        }
        await cam.dispose();
      }
      await _enviar(jpeg);
    } catch (_) {
      if (mounted && _estado != 'Reintentando') {
        setState(() => _estado = 'Reintentando');
      }
    } finally {
      _ocupado = false;
    }
  }

  Uint8List _jpeg(Uint8List rgb, int w, int h) {
    if (w < 2 || h < 2) return Uint8List(0);
    final foto = im.Image(width: w, height: h);
    var i = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        foto.setPixelRgb(x, y, rgb[i], rgb[i + 1], rgb[i + 2]);
        i += 3;
      }
    }
    return Uint8List.fromList(im.encodeJpg(foto, quality: 75));
  }

  Future<void> _enviar(Uint8List jpeg) async {
    final dni = _dni;
    if (jpeg.length < 32) {
      _terminar(verificado: false, nombre: _nombreLocal(dni));
      return;
    }
    setState(() => _estado = 'Enviando');
    final res = await ApiService().verificarRostro(dni: dni, jpeg: jpeg);
    if (!mounted) return;
    if (res['success'] != true) {
      _terminar(verificado: false, nombre: _nombreLocal(dni));
      return;
    }
    final data = res['data'];
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final motivo = (map['motivo'] ?? '').toString();
    final nombre = (map['nombre'] ?? '').toString().trim();
    final verificado = map['verificado'] == true;
    if (verificado) {
      _terminar(
        verificado: true,
        nombre: nombre.isNotEmpty ? nombre : _nombreLocal(dni),
      );
      return;
    }
    if (motivo == 'sin_foto' || motivo == 'sin_senal') {
      _terminar(
        verificado: false,
        nombre: nombre.isNotEmpty ? nombre : _nombreLocal(dni),
      );
      return;
    }
    setState(() {
      _enviando = false;
      _estado = 'No coincide';
      _rostros = 0;
    });
  }

  void _terminar({required bool verificado, required String nombre}) {
    Navigator.of(context).pop(
      VerificacionFacialResult(
        dni: _dni,
        nombre: nombre,
        verificado: verificado,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cam = _cam;
    return Scaffold(
      backgroundColor: cam == null ? null : Colors.black,
      appBar: AppBar(
        title: const Text('Verificación facial'),
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
      ),
      body: cam != null && cam.value.isInitialized
          ? _visor(cam)
          : _formulario(),
    );
  }

  Widget _formulario() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _dniCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'DNI',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() => _estado = ''),
              ),
            ),
            IconButton(
              onPressed: _escanear,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              color: AppColors.primaryDark,
            ),
          ],
        ),
        for (final s in _filtradas)
          ListTile(
            dense: true,
            title: Text(s.nombre.isEmpty ? s.dni : s.nombre),
            subtitle: Text(s.dni),
            onTap: () => setState(() => _dniCtrl.text = s.dni),
          ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _enviando ? null : _verificar,
          child: const Text('Verificar'),
        ),
        if (_estado == 'No coincide') ...[
          const SizedBox(height: 12),
          Text(_estado, textAlign: TextAlign.center),
          TextButton(
            onPressed: () => _terminar(
              verificado: false,
              nombre: _nombreLocal(_dni),
            ),
            child: const Text('DNI'),
          ),
        ] else if (_estado.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_estado, textAlign: TextAlign.center),
          ),
      ],
    );
  }

  Widget _visor(CameraController cam) {
    return Stack(
      fit: StackFit.expand,
      children: [
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
              padding: const EdgeInsets.all(16),
              child: Text(
                _estado,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
