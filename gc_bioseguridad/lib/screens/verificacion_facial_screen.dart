import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as im;

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

/// Foto ya recortada, o pedido de DNI porque no hubo cámara.
class RostroCaptura {
  const RostroCaptura.foto(this.rgb, this.ancho, this.alto) : manual = false;

  const RostroCaptura.manual()
      : rgb = null,
        ancho = 0,
        alto = 0,
        manual = true;

  final Uint8List? rgb;
  final int ancho;
  final int alto;
  final bool manual;
}

Uint8List jpegRostro(Uint8List rgb, int w, int h) {
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

/// Encuadra el rostro y vuelve enseguida. La identificación ocurre en la pantalla anterior.
class VerificacionFacialScreen extends StatefulWidget {
  const VerificacionFacialScreen({super.key});

  @override
  State<VerificacionFacialScreen> createState() =>
      _VerificacionFacialScreenState();
}

class _VerificacionFacialScreenState extends State<VerificacionFacialScreen> {
  final _detector = RostroDetector();
  CameraController? _cam;
  bool _ocupado = false;
  bool _listo = false;
  int _giro = 0;
  bool _espejo = true;

  @override
  void initState() {
    super.initState();
    _abrirCamara();
  }

  @override
  void dispose() {
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
      setState(() => _cam = cam);
      await cam.startImageStream(_onFrame);
    } catch (e) {
      debugPrint('[BioVerif] cámara $e');
      if (!mounted) return;
      Navigator.of(context).pop(const RostroCaptura.manual());
    }
  }

  Future<void> _onFrame(CameraImage img) async {
    if (_ocupado || _listo || _cam == null) return;
    _ocupado = true;
    try {
      final caras = await _detector.detectar(
        nv21: packNv21(img),
        anchoBuffer: img.width,
        altoBuffer: img.height,
        giro: _giro,
        espejo: _espejo,
      );
      if (!mounted || _listo || _cam == null) return;
      if (caras.length != 1) return;
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
      _listo = true;
      final rgb = Uint8List.fromList(reg.rgb);
      final ancho = reg.ancho;
      final alto = reg.alto;
      final cam = _cam;
      _cam = null;
      unawaited(Future<void>(() async {
        if (cam != null) {
          if (cam.value.isStreamingImages) {
            try {
              await cam.stopImageStream();
            } catch (_) {}
          }
          await cam.dispose();
        }
        if (!mounted) return;
        Navigator.of(context).pop(RostroCaptura.foto(rgb, ancho, alto));
      }));
    } catch (e) {
      debugPrint('[BioVerif] captura error $e');
      if (mounted && !_listo) {
        _listo = true;
        Navigator.of(context).pop(const RostroCaptura.manual());
      }
    } finally {
      _ocupado = false;
    }
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
      body: cam != null && cam.value.isInitialized
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
                const Positioned.fill(
                  child: ScanOverlay(
                    scanT: 0,
                    progreso: 0,
                    color: AppColors.primaryLight,
                    activo: false,
                  ),
                ),
              ],
            )
          : const ColoredBox(color: Colors.black),
    );
  }
}

Future<VerificacionFacialResult?> dniManualFacial(BuildContext context) {
  final ctrl = TextEditingController();
  return showDialog<VerificacionFacialResult>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'DNI',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () async {
              final doc = await escanearDocumentoPersona(ctx);
              if (doc == null) return;
              ctrl.text = doc.replaceAll(RegExp(r'\D'), '');
            },
            icon: const Icon(Icons.qr_code_scanner_rounded),
            color: AppColors.primaryDark,
          ),
          FilledButton(
            onPressed: () {
              final dni = ctrl.text.replaceAll(RegExp(r'\D'), '');
              if (dni.length < 6) return;
              Navigator.of(ctx).pop(
                VerificacionFacialResult(
                  dni: dni,
                  nombre: '',
                  verificado: false,
                ),
              );
            },
            child: const Text('DNI'),
          ),
        ],
      );
    },
  ).whenComplete(ctrl.dispose);
}
