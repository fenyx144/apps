import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/api_service.dart';
import '../services/face_capture.dart';
import '../utils/face_math.dart';
import '../services/nomina_store.dart';
import '../services/nomina_sync_service.dart';
import '../services/rostro_detector.dart';
import '../services/rostro_embedder.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/dialog_utils.dart';
import '../utils/theme_colors.dart';
import '../utils/toast_helper.dart';
import '../utils/yuv_converter.dart';
import '../widgets/app_drawer.dart';
import '../widgets/screen_status_bar.dart';
import '../widgets/section_app_bar.dart';
import 'dni_scanner_screen.dart';

class EnrolarScreen extends StatefulWidget {
  const EnrolarScreen({super.key});

  @override
  State<EnrolarScreen> createState() => _EnrolarScreenState();
}

class _EnrolarScreenState extends State<EnrolarScreen> {
  final _nombre = TextEditingController();
  final _dni = TextEditingController();
  bool _consentimiento = false;
  CameraController? _cam;
  CapturaRostro? _capturaSvc;
  RostroDetector? _detector;
  RostroEmbedder? _embedder;
  bool _listo = false;
  bool _ocupado = false;
  bool _capturando = false;
  bool _guardando = false;
  int _fallos = 0;
  int _giro = 0;
  bool _espejo = true;
  String _calidad = 'Iniciando';
  bool _calidadOk = false;

  ({Float32List emb, Uint8List mini})? _captura;

  @override
  void initState() {
    super.initState();
    _nombre.addListener(_refrescar);
    _dni.addListener(_refrescar);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.read<StorageService>().getPuedeEnrolar()) {
        showWarningToast(context, 'No autorizado');
        Navigator.of(context).pop();
        return;
      }
      _arrancar();
    });
  }

  void _refrescar() {
    if (mounted) setState(() {});
  }

  bool get _formularioOk =>
      _nombre.text.trim().length >= 2 &&
      RegExp(r'^\d{8}$').hasMatch(_dni.text.trim()) &&
      _consentimiento;

  Future<void> _arrancar() async {
    try {
      final detector = RostroDetector();
      final embedder = OnnxRostroEmbedder();
      await detector.inicializar();
      await embedder.cargar();
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
        await detector.cerrar();
        await embedder.cerrar();
        return;
      }
      setState(() {
        _cam = cam;
        _capturaSvc =
            CapturaRostro(detector: detector, embedder: embedder);
        _detector = detector;
        _embedder = embedder;
        _giro = u.giro;
        _espejo = u.espejo;
      });
      await WakelockPlus.enable();
      await cam.startImageStream(_onFrame);
      if (!mounted) return;
      setState(() {
        _listo = true;
        _calidad = 'Buscando rostro';
        _calidadOk = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _calidad = 'Sin cámara';
        _calidadOk = false;
      });
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    final cap = _capturaSvc;
    if (!_listo || _ocupado || cap == null || _captura != null) return;
    _ocupado = true;
    try {
      final t = await cap.tiro(
        image,
        giro: _giro,
        espejo: _espejo,
        exigirCentro: true,
      );
      if (!mounted) return;
      _fallos = 0;
      if (_capturando) {
        await _resolverCaptura(
          t.emb,
          t.rgb,
          t.ancho,
          t.alto,
          t.guia,
        );
      } else {
        setState(() {
          _calidad = t.guia.isEmpty ? 'Calidad OK' : t.guia;
          _calidadOk = t.guia.isEmpty;
        });
      }
    } catch (_) {
      _fallos++;
      if (_fallos >= 20 && mounted) {
        setState(() {
          _calidad = 'Reintentando';
          _calidadOk = false;
        });
        _fallos = 0;
      }
    } finally {
      _ocupado = false;
    }
  }

  Future<void> _resolverCaptura(
    Float32List? emb,
    Uint8List rgb,
    int ancho,
    int alto,
    String guia,
  ) async {
    _capturando = false;
    if (emb == null) {
      if (mounted) {
        setState(() {
          _calidad = guia.isEmpty ? 'Reintente' : guia;
          _calidadOk = false;
        });
        showWarningToast(context, guia.isEmpty ? 'Reintente' : guia);
      }
      return;
    }
    final foto = img.Image.fromBytes(
      width: ancho,
      height: alto,
      bytes: rgb.buffer,
      numChannels: 3,
      order: img.ChannelOrder.rgb,
    );
    final small = img.copyResize(foto, width: 96, height: 96);
    final jpg = img.encodeJpg(small, quality: 80);
    final store = context.read<NominaStore>();
    final dni = _dni.text.trim();
    final d = decidir(
      emb: emb,
      todas: store.personas,
      umbral: 0.4,
      margen: 0,
    );
    final parecido = d.persona;
    if (d.estado == DecisionEstado.ok &&
        parecido != null &&
        parecido.dni != dni) {
      if (!mounted) return;
      final pct = (d.sim * 100).toStringAsFixed(1);
      final sigue = await showAppDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            'Se parece a ${parecido.nombre}',
            style: TextStyle(color: ctx.textThemePrimary),
          ),
          content: Text(
            'Similitud $pct%. ¿Guardar igual?',
            style: TextStyle(color: ctx.textThemeMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      );
      if (sigue != true || !mounted) return;
    }
    if (!mounted) return;
    setState(() {
      _captura = (emb: emb, mini: jpg);
      _calidad = 'Capturado';
      _calidadOk = true;
    });
  }

  Future<void> _guardar() async {
    final cap = _captura;
    if (cap == null || _guardando) return;
    final nombre = _nombre.text.trim();
    final dni = _dni.text.trim();
    if (nombre.length < 2 || !RegExp(r'^\d{8}$').hasMatch(dni)) return;
    final storage = context.read<StorageService>();
    final store = context.read<NominaStore>();
    if (store.find(dni) != null) {
      final sigue = await showAppDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            'DNI ya enrolado',
            style: TextStyle(color: ctx.textThemePrimary),
          ),
          content: Text(
            '¿Reemplazar?',
            style: TextStyle(color: ctx.textThemeMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reemplazar'),
            ),
          ],
        ),
      );
      if (sigue != true || !mounted) return;
    }
    setState(() => _guardando = true);
    try {
      final persona = PersonaFace(
        dni: dni,
        nombre: nombre,
        vector: cap.emb,
        miniatura: base64Encode(cap.mini),
        updatedAt: DateTime.now().toIso8601String(),
      );
      await store.upsert(
        persona,
        clave: NominaSyncService.clavePara(storage),
      );
      var subido = false;
      if (await NominaSyncService().hasInternet()) {
        final res = await ApiService().uploadPlantilla(
          dni: dni,
          nombre: nombre,
          vector: cap.emb.toList(),
          miniatura: base64Encode(cap.mini),
          modelo: AppConstants.faceModel,
          usuario: storage.getUserCodeSync() ?? '',
          tidandroid: storage.getDeviceId() ?? '',
        );
        subido = res['success'] == true;
        if (res['denegado'] == true) {
          await store.remove(
            dni,
            clave: NominaSyncService.clavePara(storage),
          );
          if (!mounted) return;
          showErrorToast(context, 'No autorizado para enrolar');
          setState(() => _captura = null);
          return;
        }
      }
      if (subido) {
        await storage.removePlantillaPendiente(dni);
      } else {
        await storage.addPlantillaPendiente(dni);
      }
      if (!mounted) return;
      showSuccessToast(
        context,
        subido ? 'Enrolado' : 'Enrolado (pendiente de subir)',
      );
      setState(() {
        _captura = null;
        _nombre.clear();
        _dni.clear();
        _calidad = 'Buscando rostro';
        _calidadOk = false;
      });
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    _dni.dispose();
    final cam = _cam;
    final det = _detector;
    final emb = _embedder;
    _cam = null;
    unawaited(WakelockPlus.disable());
    unawaited(() async {
      try {
        if (cam != null && cam.value.isStreamingImages) {
          await cam.stopImageStream();
        }
        await cam?.dispose();
        await det?.cerrar();
        await emb?.cerrar();
      } catch (_) {
        _fallos++;
      }
    }());
    super.dispose();
  }

  Widget _vista(CameraController cam) {
    return LayoutBuilder(
      builder: (context, box) {
        var scale =
            box.maxWidth / box.maxHeight * cam.value.aspectRatio;
        if (scale < 1) scale = 1 / scale;
        return Transform.scale(
          scale: scale,
          child: Center(child: CameraPreview(cam)),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cam = _cam;
    final previewReady = cam != null && cam.value.isInitialized;
    final cap = _captura;
    return ScreenStatusBar(
      color: context.scaffoldMuted,
      child: Scaffold(
        drawer: const AppDrawer(),
        appBar: const SectionAppBar(
          title: AppStrings.menuEnrolar,
          sectionIcon: Icons.person_add_rounded,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nombre,
                textCapitalization: TextCapitalization.words,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: context.textThemePrimary,
                ),
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dni,
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: context.textThemePrimary,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'DNI',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: context.surfaceCard,
                      borderRadius:
                          BorderRadius.circular(AppColors.radiusMd),
                      border: Border.all(color: context.borderSubtle),
                    ),
                    child: IconButton(
                      onPressed: () async {
                        final dni = await DniScannerScreen.open(context);
                        if (dni != null && mounted) _dni.text = dni;
                      },
                      icon: const Icon(
                        Icons.qr_code_scanner_rounded,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Checkbox(
                    value: _consentimiento,
                    onChanged: (v) => setState(
                      () => _consentimiento = v ?? false,
                    ),
                    activeColor: AppColors.primary,
                  ),
                  Expanded(
                    child: Text(
                      'Consentimiento firmado (Ley N.° 29733)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: context.textThemeSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppColors.radiusLg),
                child: Container(
                  height: 340,
                  color: Colors.black,
                  child: previewReady
                      ? _vista(cam)
                      : const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: (_calidadOk
                            ? AppColors.aprobado
                            : AppColors.analizando)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: (_calidadOk
                              ? AppColors.aprobado
                              : AppColors.analizando)
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    _calidad,
                    style: TextStyle(
                      color: _calidadOk
                          ? AppColors.aprobado
                          : AppColors.analizando,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (cap == null)
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: (_formularioOk && _listo && !_capturando)
                        ? () => setState(() => _capturando = true)
                        : null,
                    child: Text(
                      _capturando ? 'Capturando...' : 'Capturar',
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(
                        AppColors.radiusMd,
                      ),
                      child: Image.memory(
                        cap.mini,
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed:
                                  _guardando ? null : _guardar,
                              child: _guardando
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Guardar'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 44,
                            child: OutlinedButton(
                              onPressed: _guardando
                                  ? null
                                  : () => setState(
                                        () => _captura = null,
                                      ),
                              child: const Text('Repetir'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
