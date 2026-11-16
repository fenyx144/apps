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
import '../widgets/scan_overlay.dart';

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

class _VerificacionFacialScreenState extends State<VerificacionFacialScreen>
    with SingleTickerProviderStateMixin {
  final _dniCtrl = TextEditingController();
  final _detector = RostroDetector();
  late final AnimationController _scan;
  CameraController? _cam;
  bool _ocupado = false;
  bool _manual = false;
  bool _enviando = false;
  int _giro = 0;
  bool _espejo = true;
  int _rostros = 0;

  @override
  void initState() {
    super.initState();
    _scan = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _abrirCamara();
  }

  @override
  void dispose() {
    _scan.dispose();
    _dniCtrl.dispose();
    final cam = _cam;
    _cam = null;
    if (cam != null) unawaited(cam.dispose());
    unawaited(_detector.cerrar());
    super.dispose();
  }

  Future<void> _abrirCamara() async {
    _enviando = false;
    await _cerrarCamara();
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
        _enviando = false;
      });
      await cam.startImageStream(_onFrame);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _manual = true;
        _enviando = false;
      });
    }
  }

  Future<void> _onFrame(CameraImage img) async {
    if (_ocupado || _manual || _enviando || _cam == null) return;
    _ocupado = true;
    try {
      final caras = await _detector.detectar(
        nv21: packNv21(img),
        anchoBuffer: img.width,
        altoBuffer: img.height,
        giro: _giro,
        espejo: _espejo,
      );
      if (!mounted || _cam == null || _manual || _enviando) return;
      if (caras.length != 1) {
        _rostros = 0;
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
      final rgb = Uint8List.fromList(reg.rgb);
      final ancho = reg.ancho;
      final alto = reg.alto;
      _enviando = true;
      if (mounted) setState(() {});
      final cam = _cam;
      unawaited(Future<void>(() async {
        if (cam != null && cam.value.isStreamingImages) {
          try {
            await cam.stopImageStream();
          } catch (_) {}
        }
        if (!mounted) return;
        final jpeg = _jpeg(rgb, ancho, alto);
        await _enviar(jpeg);
      }));
    } catch (e) {
      debugPrint('[BioVerif] captura error $e');
      if (mounted) _aDniManual();
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

  void _aDniManual() {
    if (!mounted) return;
    setState(() {
      _enviando = false;
      _manual = true;
    });
    unawaited(_cerrarCamara());
  }

  Future<void> _enviar(Uint8List jpeg) async {
    if (jpeg.length < 32) {
      debugPrint('[BioVerif] foto vacía, DNI manual');
      _aDniManual();
      return;
    }
    try {
      final res = await ApiService()
          .verificarRostro(jpeg: jpeg)
          .timeout(const Duration(seconds: 90));
      if (!mounted) return;
      final data = res['data'];
      final map =
          data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
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
      debugPrint('[BioVerif] sin coincidencia ${res['message']}');
    } on TimeoutException {
      debugPrint('[BioVerif] timeout en pantalla');
    } catch (e) {
      debugPrint('[BioVerif] error en pantalla $e');
    }
    _aDniManual();
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
      body: _manual
          ? _dniManual()
          : cam != null && cam.value.isInitialized
              ? Stack(
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
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _scan,
                        builder: (context, _) => ScanOverlay(
                          scanT: _scan.value,
                          progreso: _enviando ? _scan.value : 0,
                          color: AppColors.primaryLight,
                          activo: true,
                        ),
                      ),
                    ),
                  ],
                )
              : const ColoredBox(color: Colors.black),
    );
  }

  Widget _dniManual() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
