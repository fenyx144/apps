import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as im;

import '../services/api_service.dart';
import '../services/rostro_detector.dart';
import '../utils/constants.dart';
import '../utils/documento_scan_flow.dart';
import '../utils/yuv_converter.dart';

class VerificacionFacialResult {
  const VerificacionFacialResult({
    required this.dni,
    required this.nombre,
    required this.verificado,
    this.empresa = '',
  });

  final String dni;
  final String nombre;
  final String empresa;
  final bool verificado;
}

/// Toma la foto y el servidor dice quién es. El DNI solo se pide si no reconoce.
class VerificacionFacialScreen extends StatefulWidget {
  const VerificacionFacialScreen({super.key});

  @override
  State<VerificacionFacialScreen> createState() =>
      _VerificacionFacialScreenState();
}

class _VerificacionFacialScreenState extends State<VerificacionFacialScreen> {
  final _dniCtrl = TextEditingController();
  final _detector = RostroDetector();
  CameraController? _cam;
  bool _ocupado = false;
  bool _manual = false;
  int _giro = 0;
  bool _espejo = true;
  int _rostros = 0;
  String _estado = 'Buscando';

  @override
  void initState() {
    super.initState();
    _abrirCamara();
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

  Future<void> _abrirCamara() async {
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
      _rostros = 0;
      setState(() {
        _cam = cam;
        _manual = false;
        _estado = 'Buscando';
      });
      await cam.startImageStream(_onFrame);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _manual = true;
        _estado = 'Sin cámara';
      });
    }
  }

  Future<void> _onFrame(CameraImage img) async {
    if (_ocupado || _manual || _cam == null) return;
    _ocupado = true;
    try {
      final caras = await _detector.detectar(
        nv21: packNv21(img),
        anchoBuffer: img.width,
        altoBuffer: img.height,
        giro: _giro,
        espejo: _espejo,
      );
      if (!mounted || _cam == null || _manual) return;
      if (caras.length != 1) {
        _rostros = 0;
        final texto = caras.isEmpty ? 'Buscando' : 'Una sola persona';
        if (texto != _estado) setState(() => _estado = texto);
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
      await _cerrarCamara();
      if (!mounted) return;
      setState(() => _estado = 'Enviando');
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

  Future<void> _cerrarCamara() async {
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
  }

  Future<void> _enviar(Uint8List jpeg) async {
    if (jpeg.length < 32) {
      setState(() {
        _manual = true;
        _estado = 'No coincide';
      });
      return;
    }
    final res = await ApiService().verificarRostro(jpeg: jpeg);
    if (!mounted) return;
    final data = res['data'];
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    if (res['success'] == true && map['verificado'] == true) {
      final dni = (map['dni'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      if (dni.isNotEmpty) {
        Navigator.of(context).pop(
          VerificacionFacialResult(
            dni: dni,
            nombre: (map['nombre'] ?? '').toString().trim(),
            empresa: (map['empresa'] ?? '').toString().trim(),
            verificado: true,
          ),
        );
        return;
      }
    }
    setState(() {
      _manual = true;
      _estado = 'No coincide';
    });
  }

  Future<void> _escanear() async {
    final doc = await escanearDocumentoPersona(context);
    if (doc == null || !mounted) return;
    setState(() => _dniCtrl.text = doc.replaceAll(RegExp(r'\D'), ''));
  }

  void _continuarDni() {
    final dni = _dniCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (dni.length < 6) return;
    Navigator.of(context).pop(
      VerificacionFacialResult(
        dni: dni,
        nombre: '',
        verificado: false,
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
      body: _manual || cam == null || !cam.value.isInitialized
          ? _dniManual()
          : Stack(
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
            ),
    );
  }

  Widget _dniManual() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_estado, textAlign: TextAlign.center),
          const SizedBox(height: 12),
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
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                onPressed: _escanear,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                color: AppColors.primaryDark,
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _continuarDni,
            child: const Text('DNI'),
          ),
          TextButton(
            onPressed: _abrirCamara,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}
