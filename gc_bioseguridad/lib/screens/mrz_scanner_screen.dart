import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../utils/camera_preview_layout.dart';
import '../utils/documento_persona.dart';
import '../utils/constants.dart';
import '../utils/mlkit_camera_input.dart';
import '../utils/mrz_camera_guide.dart';
import '../utils/mrz_ocr_parser.dart';
import '../utils/placa_capture_crop.dart';
import '../utils/toast_helper.dart';
import '../widgets/dni_input_dialog.dart';
import '../widgets/section_app_bar.dart';

/// MRZ del carné de extranjería (TD2, 2 líneas): cámara + OCR.
class MrzScannerScreen extends StatefulWidget {
  const MrzScannerScreen({super.key});

  static Future<String?> open(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const MrzScannerScreen()),
    );
  }

  @override
  State<MrzScannerScreen> createState() => _MrzScannerScreenState();
}

class _MrzScannerScreenState extends State<MrzScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  bool _leyendo = false;
  bool _torch = false;
  String? _error;
  Rect _previewInBody = Rect.zero;
  Rect _guideInBody = Rect.zero;
  bool _permisoOk = false;
  CameraDescription? _cameraDesc;
  bool _streamActivo = false;
  bool _ocrEnFrame = false;
  DateTime? _ultimoOcrFrame;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _iniciar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detenerAutoLectura();
    _controller?.dispose();
    _recognizer.close();
    super.dispose();
  }

  int _orientacionGrados(DeviceOrientation o) {
    return switch (o) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeRight => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeLeft => 270,
    };
  }

  Future<void> _detenerAutoLectura() async {
    final c = _controller;
    if (c == null || !_streamActivo) return;
    try {
      if (c.value.isStreamingImages) {
        await c.stopImageStream();
      }
    } catch (_) {}
    _streamActivo = false;
  }

  Future<void> _iniciarAutoLectura() async {
    final c = _controller;
    final cam = _cameraDesc;
    if (c == null || cam == null || !c.value.isInitialized || _streamActivo) {
      return;
    }
    if (c.value.isStreamingImages) return;
    try {
      await c.startImageStream(_onCameraFrame);
      _streamActivo = true;
    } catch (_) {}
  }

  Future<void> _onCameraFrame(CameraImage image) async {
    if (_leyendo || _ocrEnFrame || !mounted) return;
    final ahora = DateTime.now();
    if (_ultimoOcrFrame != null &&
        ahora.difference(_ultimoOcrFrame!) < const Duration(milliseconds: 1400)) {
      return;
    }
    final c = _controller;
    final cam = _cameraDesc;
    if (c == null || cam == null) return;

    _ocrEnFrame = true;
    _ultimoOcrFrame = ahora;
    try {
      final input = inputImageFromCameraImage(
        image,
        cam,
        _orientacionGrados(c.value.deviceOrientation),
      );
      if (input == null) return;
      final recognized = await _recognizer.processImage(input);
      final doc = MrzOcrParser.documentoDesdeReconocimiento(recognized);
      if (doc == null || !mounted) return;
      await _detenerAutoLectura();
      await _cerrarCon(doc.id);
    } catch (_) {
    } finally {
      _ocrEnFrame = false;
    }
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

  Future<void> _iniciar() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (!status.isGranted) {
      setState(() {
        _error = 'Permiso de cámara requerido.';
        _permisoOk = false;
      });
      return;
    }
    setState(() => _permisoOk = true);
    await _iniciarCamara();
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
        _cameraDesc = back;
        _error = null;
      });
      await _iniciarAutoLectura();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo abrir la cámara.');
      }
    }
  }

  Future<DocumentoPersona?> _ocrPath(String path) async {
    final recognized = await _recognizer.processImage(
      InputImage.fromFilePath(path),
    );
    return MrzOcrParser.documentoDesdeReconocimiento(recognized);
  }

  Future<void> _cerrarCon(String id) async {
    if (!mounted) return;
    Navigator.of(context).pop(id);
  }

  Future<void> _leerDesdePath(String path) async {
    final doc = await _ocrPath(path);
    if (doc != null) {
      await _cerrarCon(doc.id);
      return;
    }
    if (mounted) {
      showInfoToast(
        context,
        'No se leyó el documento.',
      );
    }
  }

  Future<void> _capturarYLeer() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _leyendo) return;
    if (_previewInBody.isEmpty) return;
    setState(() => _leyendo = true);
    var cierra = false;
    try {
      await _detenerAutoLectura();
      await c.pausePreview();
      final guide = _guideInBody.isEmpty
          ? MrzCameraGuide.rectOnPreview(_previewInBody)
          : _guideInBody;

      final file = await c.takePicture();
      final cropPath = await exportGuideRegionJpeg(
        sourcePath: file.path,
        guideInBody: guide,
        previewInBody: _previewInBody,
        paddingFactor: 1.05,
      );

      var doc = await _ocrPath(cropPath);
      doc ??= await _ocrPath(file.path);

      if (!mounted) return;
      if (doc == null) {
        showInfoToast(
          context,
          'Intente de nuevo.',
        );
        await c.resumePreview();
        await _iniciarAutoLectura();
        return;
      }
      cierra = true;
      await _cerrarCon(doc.id);
    } catch (_) {
      if (mounted) {
        await _controller?.resumePreview();
        await _iniciarAutoLectura();
      }
    } finally {
      if (!cierra && mounted) setState(() => _leyendo = false);
    }
  }

  Future<void> _desdeGaleria() async {
    if (_leyendo) return;
    setState(() => _leyendo = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
      );
      if (picked == null || !mounted) return;
      await _leerDesdePath(picked.path);
    } finally {
      if (mounted) setState(() => _leyendo = false);
    }
  }

  Future<void> _teclado() async {
    if (!mounted) return;
    final manual = await DniInputDialog.show(context);
    if (!mounted) return;
    if (manual != null) await _cerrarCon(manual);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: SectionAppBar(
        title: 'Carné',
        sectionIcon: Icons.badge_outlined,
        showDrawerButton: false,
        actions: [
          IconButton(
            tooltip: 'Escribir número',
            onPressed: _teclado,
            icon: const Icon(Icons.keyboard_rounded),
            color: Colors.white,
          ),
          IconButton(
            tooltip: 'Foto guardada',
            onPressed: _leyendo ? null : _desdeGaleria,
            icon: const Icon(Icons.photo_library_outlined),
            color: Colors.white,
          ),
          if (_permisoOk)
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
                _torch
                    ? Icons.flashlight_on_rounded
                    : Icons.flashlight_off_rounded,
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
            final guide = MrzCameraGuide.rectOnPreview(preview);
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
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                )
              else if (cam?.value.isInitialized == true)
                CameraPreview(cam!),
              if (_guideInBody.width > 0) ...[
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _MrzGuideDimPainter(
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
                  onPressed: _leyendo || cam == null ? null : _capturarYLeer,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: AppColors.primaryDark,
                  ),
                  child: Text(
                    _leyendo ? '…' : 'Capturar',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MrzGuideDimPainter extends CustomPainter {
  _MrzGuideDimPainter({
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
  bool shouldRepaint(covariant _MrzGuideDimPainter old) {
    return old.guide != guide;
  }
}
