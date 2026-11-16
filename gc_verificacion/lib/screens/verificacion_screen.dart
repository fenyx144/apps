import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/avisos_service.dart';
import '../services/eventos_sync_service.dart';
import '../services/face_engine.dart';
import '../services/nomina_store.dart';
import '../services/nomina_sync_service.dart';
import '../services/storage_service.dart';
import '../services/sync_scheduler.dart';
import '../utils/constants.dart';
import '../utils/route_observer.dart';
import '../utils/toast_helper.dart';
import '../utils/yuv_converter.dart';
import '../widgets/scan_overlay.dart';
import '../widgets/screen_status_bar.dart';
import 'dni_scanner_screen.dart';
import 'inicio_screen.dart';

class VerificacionScreen extends StatefulWidget {
  const VerificacionScreen({super.key});

  @override
  State<VerificacionScreen> createState() => _VerificacionScreenState();
}

class _VerificacionScreenState extends State<VerificacionScreen>
    with TickerProviderStateMixin, RouteAware {
  CameraController? _cam;
  FaceEngine? _engine;
  AvisosService? _avisos;
  bool _listo = false;
  bool _ocupado = false;
  bool _enPausa = false;
  bool _suscrito = false;
  int _fallos = 0;
  int _giro = 0;
  bool _espejo = true;

  String _pill = 'Iniciando';
  Color _pillColor = AppColors.textMuted;
  double _progreso = 0;
  String _guia = '';
  FaceFrame? _resultado;
  String? _doc11;
  String _horaResultado = '';
  int _resultadoId = 0;

  DateTime _ahora = DateTime.now();
  Timer? _reloj;
  Timer? _idle;
  bool _atenuado = false;

  late final AnimationController _scan;
  late final AnimationController _cuenta;

  @override
  void initState() {
    super.initState();
    _scan = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _cuenta = AnimationController(
      vsync: this,
      duration: const Duration(seconds: AppConstants.resultadoSegundos),
    );
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _ahora = DateTime.now());
    });
    _arrancar();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_suscrito) return;
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
      _suscrito = true;
    }
  }

  // Otra pantalla encima (login, eventos, etc.): no escanear.
  @override
  void didPushNext() {
    _enPausa = true;
    _engine?.reset();
  }

  @override
  void didPopNext() {
    _enPausa = false;
    _engine?.reset();
  }

  Future<void> _arrancar() async {
    final storage = context.read<StorageService>();
    final store = context.read<NominaStore>();
    try {
      await store.load(clave: NominaSyncService.clavePara(storage));
      final engine = context.read<FaceEngine>();
      engine.umbral = storage.getUmbral();
      engine.margen = storage.getMargen();
      await engine.inicializar();
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
      final avisos = AvisosService(storage);
      await avisos.inicializar();
      if (!mounted) {
        await cam.dispose();
        await avisos.dispose();
        return;
      }
      setState(() {
        _cam = cam;
        _engine = engine;
        _avisos = avisos;
        _giro = u.giro;
        _espejo = u.espejo;
      });
      await WakelockPlus.enable();
      SyncScheduler.start(storage: storage, store: store);
      unawaited(SyncScheduler.syncOnce(storage: storage, store: store));
      await cam.startImageStream(_onFrame);
      if (!mounted) return;
      setState(() {
        _listo = true;
        _pill = 'Buscando';
        _pillColor = AppColors.buscando;
      });
      _tocarIdle();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pill = 'Sin cámara';
        _pillColor = AppColors.rechazado;
      });
    }
  }

  Future<void> _onFrame(CameraImage img) async {
    final eng = _engine;
    if (!_listo || _ocupado || _enPausa || eng == null) return;
    if (_resultado != null) return;
    _ocupado = true;
    try {
      final f = await eng.procesar(img, giro: _giro, espejo: _espejo);
      if (!mounted) return;
      _fallos = 0;
      _aplicar(f);
    } catch (_) {
      _fallos++;
      if (_fallos >= 20 && mounted) {
        setState(() {
          _pill = 'Reintentando';
          _pillColor = AppColors.warning;
        });
        _fallos = 0;
      }
    } finally {
      _ocupado = false;
    }
  }

  void _aplicar(FaceFrame f) {
    if (f.estado != EstadoFrame.sinRostro) _tocarIdle();
    switch (f.estado) {
      case EstadoFrame.sinRostro:
        setState(() {
          _pill = 'Buscando';
          _pillColor = AppColors.buscando;
          _progreso = 0;
          _guia = '';
        });
      case EstadoFrame.multiples:
      case EstadoFrame.guia:
        setState(() {
          _pill = 'Buscando';
          _pillColor = AppColors.buscando;
          _progreso = 0;
          _guia = f.guia;
        });
      case EstadoFrame.candidato:
        setState(() {
          _pill = 'Analizando ${f.votos}/${AppConstants.votosRequeridos}';
          _pillColor = AppColors.analizando;
          _progreso = f.votos / AppConstants.votosRequeridos;
          _guia = '';
        });
      case EstadoFrame.ambiguo:
        setState(() {
          _pill = 'Analizando';
          _pillColor = AppColors.analizando;
          _progreso = 0;
          _guia = '';
        });
      case EstadoFrame.confirmado:
        _mostrarResultado(f, true);
      case EstadoFrame.noCoincide:
        if (f.rechazoFinal) {
          _mostrarResultado(f, false);
        } else {
          setState(() {
            _pill = 'No reconocido';
            _pillColor = AppColors.rechazado;
            _progreso = 0;
            _guia = '';
          });
        }
    }
  }

  String _fecha(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _mostrarResultado(FaceFrame f, bool ok) async {
    final storage = context.read<StorageService>();
    final id = ++_resultadoId;
    final ahora = DateTime.now();
    _horaResultado =
        '${ahora.hour.toString().padLeft(2, '0')}:${ahora.minute.toString().padLeft(2, '0')}:${ahora.second.toString().padLeft(2, '0')}';
    setState(() {
      _resultado = f;
      _pill = ok ? 'Acceso permitido' : 'No coincide';
      _pillColor = ok ? AppColors.aprobado : AppColors.rechazado;
      _progreso = ok ? 1 : 0;
      _guia = '';
    });
    _cuenta.forward(from: 0);
    final p = f.persona;
    if (ok && p != null) {
      await _avisos?.aprobado(p.nombre);
      await storage.addEvento({
        'dni': p.dni,
        'nombre': p.nombre,
        'fecha': _fecha(ahora),
        'hora': _horaResultado,
        'resultado': 'A',
        'similitud': f.similitud,
        'modo': '1N',
        'tidandroid': storage.getDeviceId() ?? '',
      });
      unawaited(EventosSyncService.enviar(storage));
    } else {
      await _avisos?.rechazo();
      if (p != null) {
        await storage.addEvento({
          'dni': p.dni,
          'nombre': p.nombre,
          'fecha': _fecha(ahora),
          'hora': _horaResultado,
          'resultado': 'R',
          'similitud': f.similitud,
          'modo': '1N',
          'tidandroid': storage.getDeviceId() ?? '',
        });
        unawaited(EventosSyncService.enviar(storage));
      }
    }
    await Future.delayed(
      const Duration(seconds: AppConstants.resultadoSegundos),
    );
    if (!mounted || id != _resultadoId) return;
    setState(() => _resultado = null);
    _engine?.reset();
  }

  void _cerrarResultado() {
    _resultadoId++;
    _cuenta.stop();
    if (!mounted) return;
    setState(() => _resultado = null);
    _engine?.reset();
  }

  void _tocarIdle() {
    _idle?.cancel();
    if (_atenuado) _atenuar(false);
    _idle = Timer(
      const Duration(seconds: AppConstants.idleDimSeconds),
      () => _atenuar(true),
    );
  }

  Future<void> _atenuar(bool v) async {
    if (v == _atenuado) return;
    try {
      if (v) {
        await ScreenBrightness().setApplicationScreenBrightness(
          AppConstants.dimLevel,
        );
      } else {
        await ScreenBrightness().resetApplicationScreenBrightness();
      }
      _atenuado = v;
    } catch (_) {
      _atenuado = false;
    }
  }

  @override
  void dispose() {
    if (_suscrito) routeObserver.unsubscribe(this);
    _reloj?.cancel();
    _idle?.cancel();
    _scan.dispose();
    _cuenta.dispose();
    SyncScheduler.stop();
    final cam = _cam;
    final avisos = _avisos;
    _cam = null;
    _engine = null;
    _avisos = null;
    unawaited(WakelockPlus.disable());
    unawaited(ScreenBrightness().resetApplicationScreenBrightness());
    unawaited(() async {
      try {
        if (cam != null && cam.value.isStreamingImages) {
          await cam.stopImageStream();
        }
        await cam?.dispose();
        await avisos?.dispose();
      } catch (_) {
        _fallos++;
      }
    }());
    super.dispose();
  }

  void _volver() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Get.offAll(() => const InicioScreen(), routeName: '/inicio');
    }
  }

  String get _hora => DateFormat('HH:mm:ss').format(_ahora);

  String get _fechaLarga {
    final s = DateFormat("EEEE, d 'de' MMMM", 'es_ES').format(_ahora);
    return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  }

  Widget _botonDni() {
    return IconButton(
      onPressed: _listo ? _hojaDni : null,
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _doc11 == null
              ? Colors.white.withValues(alpha: 0.14)
              : AppColors.primary.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _doc11 == null
                ? Colors.white.withValues(alpha: 0.2)
                : AppColors.primary,
            width: 1.5,
          ),
        ),
        child: const Icon(Icons.badge_rounded, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _chipDni() {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: _limpiarDni,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary, width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '1:1 · $_doc11',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _hojaDni() async {
    final dni = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DniSheet(inicial: _doc11),
    );
    if (!mounted) return;
    if (dni == null) return;
    if (dni.isEmpty) {
      _limpiarDni();
      return;
    }
    final store = context.read<NominaStore>();
    if (store.find(dni) == null) {
      showInfoToast(context, 'DNI no registrado');
      return;
    }
    _engine?.doc11 = dni;
    _engine?.reset();
    setState(() => _doc11 = dni);
  }

  void _limpiarDni() {
    _engine?.doc11 = null;
    _engine?.reset();
    if (mounted) setState(() => _doc11 = null);
  }

  Widget _vista(CameraController cam) {
    final size = MediaQuery.sizeOf(context);
    var scale = size.aspectRatio * cam.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;
    return Transform.scale(
      scale: scale,
      child: Center(child: CameraPreview(cam)),
    );
  }

  Widget _tarjeta(FaceFrame f) {
    final ok = f.estado == EstadoFrame.confirmado;
    final color = ok ? AppColors.aprobado : AppColors.rechazado;
    final p = f.persona;
    Uint8List? foto;
    final mini = p?.miniatura ?? '';
    if (mini.isNotEmpty) {
      try {
        foto = base64Decode(mini);
      } catch (_) {
        foto = null;
      }
    }
    return Positioned.fill(
      child: GestureDetector(
        onTap: _cerrarResultado,
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          alignment: Alignment.center,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(AppColors.radiusXl),
              border: Border.all(
                color: color.withValues(alpha: 0.5),
                width: 1.5,
              ),
              boxShadow: AppColors.strongShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Icon(
                    ok ? Icons.check_rounded : Icons.close_rounded,
                    color: color,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  ok ? 'ACCESO PERMITIDO' : 'NO COINCIDE',
                  style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: color, width: 2),
                        image: foto != null
                            ? DecorationImage(
                                image: MemoryImage(foto),
                                fit: BoxFit.cover,
                              )
                            : null,
                        color: AppColors.surface,
                      ),
                      child: foto == null
                          ? const Icon(
                              Icons.person_rounded,
                              color: AppColors.textMuted,
                              size: 40,
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p?.nombre ?? 'No identificado',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            p == null ? '—' : 'DNI ${p.dni}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${(f.similitud * 100).toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: color,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _horaResultado,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                AnimatedBuilder(
                  animation: _cuenta,
                  builder: (_, __) => ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: 1 - _cuenta.value,
                      minHeight: 4,
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cam = _cam;
    final previewReady = cam != null && cam.value.isInitialized;
    return ScreenStatusBar(
      color: Colors.black,
      iconBrightness: Brightness.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: previewReady
                  ? _vista(cam)
                  : Container(color: Colors.black),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.72),
                      Colors.black.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.78),
                    ],
                    stops: const [0, 0.32, 0.62, 1],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _scan,
                builder: (context, _) => ScanOverlay(
                  scanT: _scan.value,
                  progreso: _progreso,
                  color: _pillColor,
                  activo: _listo && _resultado == null,
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: _volver,
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                      _botonDni(),
                      const Spacer(),
                      _Pildora(texto: _pill, color: _pillColor),
                      const SizedBox(width: 16),
                    ],
                  ),
                  if (_doc11 != null) _chipDni(),
                  const SizedBox(height: 8),
                  Text(
                    _hora,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 56,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _fechaLarga,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _guia.isEmpty
                        ? const SizedBox(height: 28, key: ValueKey('vacio'))
                        : Text(
                            _guia,
                            key: ValueKey(_guia),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),
            if (_resultado != null) _tarjeta(_resultado!),
          ],
        ),
      ),
    );
  }
}

class _Pildora extends StatelessWidget {
  const _Pildora({required this.texto, required this.color});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 8),
          Text(
            texto,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DniSheet extends StatefulWidget {
  const _DniSheet({this.inicial});

  final String? inicial;

  @override
  State<_DniSheet> createState() => _DniSheetState();
}

class _DniSheetState extends State<_DniSheet> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.inicial ?? '');
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: 24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Verificar DNI',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _c,
            keyboardType: TextInputType.number,
            maxLength: 8,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
            decoration: InputDecoration(
              hintText: 'DNI',
              counterText: '',
              suffixIcon: IconButton(
                onPressed: () async {
                  final dni = await DniScannerScreen.open(context);
                  if (dni != null && mounted) {
                    setState(() => _c.text = dni);
                  }
                },
                icon: const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, ''),
                  child: const Text('Limpiar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    final dni = _c.text.trim();
                    if (!RegExp(r'^\d{8}$').hasMatch(dni)) return;
                    Navigator.pop(context, dni);
                  },
                  child: const Text('Aplicar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
