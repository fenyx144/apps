import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../services/placa_yolo_detector.dart';
import '../services/plan_visitas_service.dart';
import '../utils/camera_preview_layout.dart';
import '../utils/constants.dart';
import '../utils/placa_capture_crop.dart';
import '../utils/placa_ocr_parser.dart';
import '../utils/toast_helper.dart';
import '../widgets/placa_input_dialog.dart';
import '../widgets/section_app_bar.dart';

/// Lee la placa: marco azul YOLO dentro del marco OCR (fallback marco completo).
class PlacaCameraScreen extends StatefulWidget {
  const PlacaCameraScreen({super.key});

  static Future<String?> open(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const PlacaCameraScreen()),
    );
  }

  @override
  State<PlacaCameraScreen> createState() => _PlacaCameraScreenState();
}

class _PlacaCameraScreenState extends State<PlacaCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  bool _leyendo = false;
  bool _torch = false;
  String? _error;
  Rect _previewInBody = Rect.zero;
  Rect _guideInBody = Rect.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PlacaYoloDetector.instance.warmUp();
    _iniciarCamara();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _recognizer.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
      setState(() => _controller = null);
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _iniciarCamara();
    }
  }

  Future<void> _iniciarCamara() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      await controller.setFocusMode(FocusMode.auto);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Sin cámara');
      }
    }
  }

  Future<String?> _confirmarPlaca(String sugerida) async {
    return showDialog<String?>(
      context: context,
      builder: (ctx) => _PlacaConfirmDialog(sugerida: sugerida),
    );
  }

  Future<RecognizedText> _ocrEn(String path) async {
    return _recognizer.processImage(InputImage.fromFilePath(path));
  }

  Future<String?> _placaDesdePathOcr(String path) async {
    final recognized = await _ocrEn(path);
    return PlacaOcrParser.extraerDeReconocimiento(recognized) ??
        PlacaOcrParser.sugerirDesdeReconocimiento(recognized);
  }

  Future<String?> _ocrEnRecorte(String photoPath, String cropPath) async {
    if (cropPath == photoPath) return null;
    return reconocerPlacaEnRecorteOptimizado(
      rawCropPath: cropPath,
      leerPlacaEnImagen: _placaDesdePathOcr,
    );
  }

  /// YOLO en el marco azul; si falla, OCR en el marco (pocas pasadas = más rápido).
  Future<String?> _leerPlacaDesdeFoto({
    required String photoPath,
    required Rect guideInBody,
    required Rect previewInBody,
  }) async {
    final guideJpeg = await exportGuideRegionJpeg(
      sourcePath: photoPath,
      guideInBody: guideInBody,
      previewInBody: previewInBody,
      paddingFactor: 1.0,
    );
    if (guideJpeg != photoPath) {
      final hit = await PlacaYoloDetector.instance.detectBestHit(
        await File(guideJpeg).readAsBytes(),
      );
      if (hit != null) {
        final cropPath = await cropOcrFromYoloInGuideJpeg(
          guideJpegPath: guideJpeg,
          normalizedBoxInGuide: hit.normalizedBox,
          paddingFactor: 1.05,
        );
        final placa = await _ocrEnRecorte(photoPath, cropPath);
        if (placa != null) return placa;
      }
    }

    final cropPath = await cropPlacaGuideRegion(
      sourcePath: photoPath,
      guideInBody: guideInBody,
      previewInBody: previewInBody,
      paddingFactor: 1.0,
    );
    return _ocrEnRecorte(photoPath, cropPath);
  }

  Future<void> _capturarYLeer() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _leyendo) return;
    if (_previewInBody.isEmpty) return;
    setState(() => _leyendo = true);
    var cierraConPlaca = false;
    try {
      await c.pausePreview();
      final guide = _guideInBody.isEmpty
          ? PlacaCameraGuide.rectOnPreview(_previewInBody)
          : _guideInBody;

      final file = await c.takePicture();
      final placa = await _leerPlacaDesdeFoto(
        photoPath: file.path,
        guideInBody: guide,
        previewInBody: _previewInBody,
      );

      if (!mounted) return;
      if (placa == null) {
        showInfoToast(
          context,
          'No se leyó la placa. Encuadre mejor o use teclado.',
        );
        await c.resumePreview();
        return;
      }
      if (mounted) {
        setState(() => _leyendo = false);
      }
      final confirmada = await _confirmarPlaca(placa);
      if (!mounted) return;
      if (confirmada != null) {
        cierraConPlaca = true;
        Navigator.of(context).pop(confirmada);
        return;
      }
      await c.resumePreview();
    } catch (_) {
      if (mounted) {
        await _controller?.resumePreview();
      }
    } finally {
      if (!cierraConPlaca && mounted) {
        setState(() => _leyendo = false);
      }
    }
  }

  Future<void> _teclado() async {
    if (!mounted) return;
    final manual = await PlacaInputDialog.show(context);
    if (!mounted) return;
    if (manual != null) {
      Navigator.of(context).pop(manual);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: SectionAppBar(
        title: 'Leer placa',
        sectionIcon: Icons.directions_car_rounded,
        showDrawerButton: false,
        actions: [
          IconButton(
            tooltip: 'Teclado',
            onPressed: _teclado,
            icon: const Icon(Icons.keyboard_rounded),
            color: Colors.white,
          ),
          IconButton(
            tooltip: 'Linterna',
            onPressed: () async {
              final c = _controller;
              if (c == null) return;
              _torch = !_torch;
              await c.setFlashMode(
                _torch ? FlashMode.torch : FlashMode.off,
              );
              setState(() {});
            },
            icon: Icon(
              _torch ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
            ),
            color: Colors.white,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bodySize = constraints.biggest;
          final cam = _controller;
          if (cam != null && cam.value.isInitialized && bodySize.width > 0) {
            final preview = CameraPreviewLayout.previewRectInParent(
              parentSize: bodySize,
              controllerAspectRatio: cam.value.aspectRatio,
            );
            final guide = PlacaCameraGuide.rectOnPreview(preview);
            if (_previewInBody != preview || _guideInBody != guide) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _previewInBody = preview;
                    _guideInBody = guide;
                  });
                }
              });
            }
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              if (_error != null)
                Center(
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                )
              else if (cam?.value.isInitialized == true)
                CameraPreview(cam!),
              if (_guideInBody.width > 0) ...[
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _PlacaGuideDimPainter(
                        guide: _guideInBody,
                        borderRadius: 8,
                      ),
                    ),
                  ),
                ),
                Positioned.fromRect(
                  rect: _guideInBody,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppColors.primary,
                          width: 2.5,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
              if (_leyendo)
                Container(
                  color: Colors.black45,
                  child: const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 24 + MediaQuery.paddingOf(context).bottom,
                child: FilledButton(
                  onPressed: _leyendo ? null : _capturarYLeer,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: AppColors.primaryDark,
                  ),
                  child: const Text('Capturar y leer'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PlacaGuideDimPainter extends CustomPainter {
  _PlacaGuideDimPainter({
    required this.guide,
    required this.borderRadius,
  });

  final Rect guide;
  final double borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Path()..addRect(Offset.zero & size);
    final hole = Path()
      ..addRRect(
        RRect.fromRectAndRadius(guide, Radius.circular(borderRadius)),
      );
    final overlay = Path.combine(PathOperation.difference, outer, hole);
    canvas.drawPath(
      overlay,
      Paint()..color = const Color(0xAA000000),
    );
  }

  @override
  bool shouldRepaint(covariant _PlacaGuideDimPainter old) {
    return old.guide != guide;
  }
}

class _PlacaConfirmDialog extends StatefulWidget {
  const _PlacaConfirmDialog({required this.sugerida});

  final String sugerida;

  @override
  State<_PlacaConfirmDialog> createState() => _PlacaConfirmDialogState();
}

class _PlacaConfirmDialogState extends State<_PlacaConfirmDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: PlacaOcrParser.formatearLegible(widget.sugerida),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _aceptar() {
    final legible = PlacaOcrParser.paraCampo(_controller.text);
    if (PlanDescarga.normPlaca(legible).length <
        PlacaInputDialog.minCaracteres) {
      return;
    }
    Navigator.of(context).pop(legible);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('¿Es esta la placa?'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]')),
        ],
        decoration: const InputDecoration(
          labelText: 'Placa',
          hintText: 'ABC-123',
        ),
        onSubmitted: (_) => _aceptar(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('No'),
        ),
        FilledButton(
          onPressed: _aceptar,
          child: const Text('Sí, usar'),
        ),
      ],
    );
  }
}
