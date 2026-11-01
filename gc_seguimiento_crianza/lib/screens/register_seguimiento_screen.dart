import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../services/api_service.dart';
import '../services/app_version_service.dart';
import '../services/catalog_service.dart';
import '../services/catalog_sync_service.dart';
import '../services/edad_catalog_service.dart';
import '../services/storage_service.dart';
import '../services/vosk_service.dart';
import '../utils/constants.dart';
import '../utils/dialog_helper.dart';
import '../utils/galpones_resolver.dart';
import '../utils/record_id.dart';
import '../utils/theme_colors.dart';
import '../utils/toast_helper.dart';
import '../widgets/app_drawer.dart';
import '../widgets/evidencia_select_field.dart';
import '../widgets/granja_campania_picker.dart';
import '../widgets/image_slot_row.dart';
import '../widgets/section_app_bar.dart';
import 'register_summary_screen.dart';

class RegisterSeguimientoScreen extends StatefulWidget {
  const RegisterSeguimientoScreen({super.key});

  @override
  State<RegisterSeguimientoScreen> createState() =>
      _RegisterSeguimientoScreenState();
}

class _RegisterSeguimientoScreenState extends State<RegisterSeguimientoScreen>
    with TickerProviderStateMixin {
  DateTime _fecha = DateTime.now();
  String _granja = '';
  String _granjaNombre = '';
  String _campania = '';
  List<String> _campaniasDeGranja = [];
  List<String> _galponesSeleccionados = [];
  int? _edad;
  bool _campaniaActiva = false;
  final _obsController = TextEditingController();
  final _agenteCausalController = TextEditingController();
  final List<String?> _imagePaths = [null, null, null];
  List<Map<String, dynamic>> _galpones = [];
  final _catalogSync = CatalogSyncService();
  final _edadCatalog = EdadCatalogService();
  bool _listening = false;
  TextEditingController? _dictationController;
  String _baseTextBeforeDictation = '';
  StreamSubscription<String?>? _voskResultSub;
  StreamSubscription<String?>? _voskPartialSub;
  late final AnimationController _micPulseController;
  late final Animation<double> _micPulseAnimation;

  String _fmtDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _fmtDateDisplay(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

  String get _campaniaEfectiva {
    if (_campania.isNotEmpty) return _campania;
    // Legado: cuando la granja se almacena como código de 6 dígitos
    // (granja+campaña), la campaña se deduce del propio código.
    if (_granja.length >= 6) {
      return GranjaCampaniaPicker.campaniaFromCodigo(_granja);
    }
    return '';
  }

  String get _granja3 {
    if (_granja.isEmpty) return '';
    final n = GranjaCampaniaPicker.normalizarCodigoCenco(_granja);
    if (n.length >= 3) return GranjaCampaniaPicker.normGranja(n.substring(0, 3));
    return GranjaCampaniaPicker.normGranja(_granja);
  }

  String get _granjaLabel {
    if (_granja3.isEmpty) return '';
    return GranjaCampaniaPicker.formatGranjaLabel(_granja3, _granjaNombre);
  }

  String get _campaniaDisplay {
    final c = _campaniaEfectiva;
    return c.isEmpty ? '' : GranjaCampaniaPicker.padCampania(c);
  }

  bool get _mostrarEdad =>
      _campaniaActiva && _edad != null && _edad! > 0;

  List<String> get _galponCodes => _galpones
      .map((g) => (g['tcodint'] ?? '').toString())
      .where((s) => s.isNotEmpty)
      .toList();

  @override
  void initState() {
    super.initState();
    _micPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0,
      upperBound: 1,
    )..addListener(() {
        if (mounted) setState(() {});
      });
    _micPulseAnimation = Tween<double>(begin: 0.8, end: 1.15).animate(
      CurvedAnimation(
        parent: _micPulseController,
        curve: Curves.easeInOut,
      ),
    );
    VoskService.instance.addListener(_onVoskStateChanged);
    VoskService.instance.init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureCatalogos();
    });
  }

  Future<void> _ensureCatalogos() async {
    if (!mounted) return;
    await context.read<CatalogService>().loadFromPrefs();
  }

  void _aplicarGranjaYCampania(
    StorageService storage, {
    required String granja3,
    required String granjaNombre,
    bool limpiarGalpones = true,
  }) {
    final proyeccion = storage.getProyeccion();
    final fechaYmd = _fmtDate(_fecha);
    final cencosGalpones = storage.getCencosGalpones() ??
        {'cencos': storage.getCencosListaLocal()};
    final pool = GranjaCampaniaPicker.campaniasDisponiblesGranja(
      proyeccion,
      granja3,
    );
    final listaCamps = GranjaCampaniaPicker.campaniasPoolParaFecha(
      proyeccion: proyeccion,
      granja3: granja3,
      fechaYmd: fechaYmd,
      campaniasDisponibles: pool,
    );
    final campDef = GranjaCampaniaPicker.resolveCampaniaDefaultForFecha(
      proyeccion: proyeccion,
      granja3: granja3,
      fechaYmd: fechaYmd,
      campaniasDisponibles: listaCamps.isNotEmpty ? listaCamps : pool,
      cencosGalpones: cencosGalpones,
    );
    final campDefPad = campDef != null
        ? GranjaCampaniaPicker.padCampania(campDef)
        : '';
    final campFinal = listaCamps.length == 1
        ? listaCamps.first
        : (campDefPad.isNotEmpty && listaCamps.contains(campDefPad)
            ? campDefPad
            : (listaCamps.isNotEmpty ? listaCamps.last : ''));
    setState(() {
      _granja = granja3;
      _granjaNombre = granjaNombre;
      _campaniasDeGranja = listaCamps;
      _campania = campFinal;
      if (limpiarGalpones) _galponesSeleccionados = [];
      _galpones = [];
      _edad = null;
      _campaniaActiva = false;
    });
    _loadGalpones(storage);
  }

  void _restaurarGalponesPrevios(List<String> previos) {
    if (previos.isEmpty) return;
    final restaurados = <String>[];
    for (final sel in previos) {
      for (final opt in _galponCodes) {
        if (GranjaCampaniaPicker.galponCodigoCoincide(opt, sel)) {
          restaurados.add(opt);
          break;
        }
      }
    }
    if (restaurados.isEmpty) return;
    setState(() => _galponesSeleccionados = restaurados);
  }

  @override
  void dispose() {
    _stopListening();
    _micPulseController.dispose();
    VoskService.instance.removeListener(_onVoskStateChanged);
    _obsController.dispose();
    _agenteCausalController.dispose();
    super.dispose();
  }

  void _onVoskStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _reloadProyeccionPorFecha() async {
    final granjaPrev = _granja3;
    final nombrePrev = _granjaNombre;
    final storage = context.read<StorageService>();
    final fechaYmd = _fmtDate(_fecha);

    await _edadCatalog.refreshProyeccionPorFecha(
      storage: storage,
      fechaYmd: fechaYmd,
    );

    if (granjaPrev.isEmpty) {
      setState(() {
        _campania = '';
        _campaniasDeGranja = [];
        _galponesSeleccionados = [];
        _galpones = [];
        _edad = null;
        _campaniaActiva = false;
      });
    } else {
      final galponesPrev = List<String>.from(_galponesSeleccionados);
      _aplicarGranjaYCampania(
        storage,
        granja3: granjaPrev,
        granjaNombre: nombrePrev,
        limpiarGalpones: false,
      );
      _restaurarGalponesPrevios(galponesPrev);
      if (_galponesSeleccionados.isNotEmpty) {
        await _refreshEdad();
      }
    }

  }

  void _aplicarSeleccionGranja(
    StorageService storage,
    Map<String, dynamic> sel,
  ) {
    final g3 = (sel['granja3'] ?? '').toString();
    final nombre = GranjaCampaniaPicker.cleanNombreGranja(
      (sel['granjaNombre'] ?? '').toString(),
    );
    _aplicarGranjaYCampania(
      storage,
      granja3: g3,
      granjaNombre: nombre,
    );
  }

  void _loadGalpones(StorageService storage) {
    if (_granja.isEmpty) {
      setState(() {
        _galpones = [];
      });
      return;
    }
    final gps = GalponesResolver.resolveOffline(
      granjaCodigo: _granja,
      campania: _campaniaEfectiva,
      galponesPorGranja: storage.getGalponesPorGranjaMapLocal(),
      galponesPorCenco: storage.getGalponesPorCencoLocal(),
      cencosLista: storage.getCencosListaLocal(),
    );
    setState(() {
      _galpones = gps;
    });
  }

  void _applyCampaniaEdad({required bool activa, required int? edad}) {
    setState(() {
      _campaniaActiva = activa;
      _edad = edad;
    });
  }

  Future<void> _refreshEdad() async {
    final fecha = _fmtDate(_fecha);
    final campania = _campaniaEfectiva;

    if (_granja.isEmpty ||
        campania.isEmpty ||
        _galponesSeleccionados.isEmpty) {
      setState(() {
        _edad = null;
        _campaniaActiva = false;
      });
      return;
    }

    final galponCsv = _galponesSeleccionados.join(',');
    final storage = context.read<StorageService>();

    final local = _edadCatalog.edadDesdeCatalogo(
      storage: storage,
      granja3: _granja3,
      campania: campania,
      fechaYmd: fecha,
      galponesSel: _galponesSeleccionados,
      galponesUi: _galpones,
    );
    var activa = local.activa;
    var edad = local.edad;

    if (mounted) {
      _applyCampaniaEdad(activa: activa, edad: edad);
    }
    debugPrint(
      '[Edad] granja=$_granja3 camp=$campania cenco=${local.cenco} '
      'fecha=$fecha activa=$activa meta=${local.metaCount} '
      'conFecIng=${local.conFecIng} edad=$edad fuente=local',
    );

    final online = await _edadCatalog.fetchEdadOnline(
      storage: storage,
      granja3: _granja3,
      campania: campania,
      galponCsv: galponCsv,
      fechaYmd: fecha,
    );
    if (!mounted || online == null) return;

    activa = online.activa || activa;
    if (online.fromCp00 && online.edad != null) {
      edad = online.edad;
      debugPrint('[Edad] fuente=cp00 edad=$edad');
    } else if (edad == null && online.edad != null) {
      edad = online.edad;
    }
    _applyCampaniaEdad(activa: activa, edad: edad);
  }

  Map<String, dynamic> _buildRecord(StorageService storage) {
    final campania = _campaniaEfectiva;
    final imagenes =
        _imagePaths.whereType<String>().where((p) => p.isNotEmpty).toList();
    final usuario = storage.getUserCodeSync() ?? '';
    final recordId = const Uuid().v4();
    return {
      'id': recordId,
      'fecha': _fmtDate(_fecha),
      'edad': _edad,
      'campaniaActiva': _campaniaActiva,
      'granja': _granja3,
      'granjaNombre': _granjaNombre,
      'campania': campania,
      'galpon': _galponesSeleccionados.join(','),
      'galpones': List<String>.from(_galponesSeleccionados),
      'galpones_todos': _galpones.isNotEmpty &&
          _galponesSeleccionados.length == _galpones.length,
      'obs': _obsController.text.trim(),
      'agente_causal': _agenteCausalController.text.trim(),
      'imagenes': imagenes,
      'synced': false,
      'guardado_backend': false,
      'usuario': usuario,
      'createdAt': DateTime.now().toIso8601String(),
    };
  }

  void _clearForm() {
    setState(() {
      _fecha = DateTime.now();
      _granja = '';
      _granjaNombre = '';
      _campania = '';
      _campaniasDeGranja = [];
      _galponesSeleccionados = [];
      _galpones = [];
      _edad = null;
      _campaniaActiva = false;
      _obsController.clear();
      _agenteCausalController.clear();
      _imagePaths[0] = null;
      _imagePaths[1] = null;
      _imagePaths[2] = null;
    });
  }

  Future<void> _stopListening() async {
    _voskResultSub?.cancel();
    _voskPartialSub?.cancel();
    _voskResultSub = null;
    _voskPartialSub = null;
    _micPulseController.stop();
    _micPulseController.value = 0;
    try {
      await VoskService.instance.speechService?.stop();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _listening = false;
        _dictationController = null;
      });
    }
  }

  Future<void> _toggleDictation(TextEditingController controller) async {
    if (_listening && _dictationController == controller) {
      await _stopListening();
      return;
    }
    if (_listening) {
      await _stopListening();
    }
    final vosk = VoskService.instance;
    if (!vosk.isReady || vosk.speechService == null) {
      if (vosk.isLoading) {
        showInfoToast(context, 'Cargando modelo de voz…');
      } else if (vosk.error != null) {
        showErrorToast(context, vosk.error!);
      } else {
        showInfoToast(context, 'Inicializando dictado…');
        vosk.init();
      }
      return;
    }
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      if (mounted) {
        showErrorToast(context, 'Se necesita permiso de micrófono.');
      }
      return;
    }

    String extractTextFromJson(String? raw) {
      if (raw == null || raw.trim().isEmpty) return '';
      final s = raw.trim();
      try {
        final decoded = jsonDecode(s);
        if (decoded is Map) {
          final t = decoded['text'] ?? decoded['partial'];
          if (t != null) return t.toString().trim();
        }
      } catch (_) {}
      return s;
    }

    String capitalizeSentences(String text) {
      if (text.isEmpty) return text;
      final buffer = StringBuffer();
      var capitalizeNext = true;
      for (final rune in text.runes) {
        final ch = String.fromCharCode(rune);
        if (capitalizeNext && ch.trim().isNotEmpty) {
          buffer.write(ch.toUpperCase());
          capitalizeNext = false;
        } else {
          buffer.write(ch);
        }
        if (ch == '.' || ch == '!' || ch == '?') {
          capitalizeNext = true;
        }
      }
      return buffer.toString();
    }

    _baseTextBeforeDictation = controller.text.trim();
    setState(() {
      _listening = true;
      _dictationController = controller;
    });
    _micPulseController.repeat(reverse: true);
    final speech = vosk.speechService!;
    _voskResultSub = speech.onResult().listen((raw) {
      final text = extractTextFromJson(raw);
      if (text.isEmpty || _dictationController == null) return;
      final combined = _baseTextBeforeDictation.isEmpty
          ? text
          : '$_baseTextBeforeDictation $text';
      final capitalized = capitalizeSentences(combined);
      _dictationController!.value = TextEditingValue(
        text: capitalized,
        selection: TextSelection.collapsed(offset: capitalized.length),
      );
      _baseTextBeforeDictation = capitalized;
    });
    _voskPartialSub = speech.onPartial().listen((partialRaw) {
      final partial = extractTextFromJson(partialRaw);
      if (partial.isEmpty || _dictationController == null) return;
      final combined = _baseTextBeforeDictation.isEmpty
          ? partial
          : '$_baseTextBeforeDictation $partial';
      final capitalized = capitalizeSentences(combined);
      _dictationController!.value = TextEditingValue(
        text: capitalized,
        selection: TextSelection.collapsed(offset: capitalized.length),
      );
    });
    try {
      await speech.start();
    } catch (e) {
      await _stopListening();
      if (mounted) showErrorToast(context, 'No se pudo iniciar el dictado.');
    }
  }

  /// Comprueba si el servidor Sanidad responde (no basta con Wi‑Fi / google.com).
  Future<bool> _hasServerReachable() async {
    try {
      final host = Uri.parse(AppConstants.baseUrl).host;
      final r = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 4));
      return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _guardar() async {
    if (_granja.isEmpty) {
      showErrorToast(context, 'Seleccione granja y campaña.');
      return;
    }
    final campania = _campaniaEfectiva;
    if (campania.isEmpty) {
      showErrorToast(context, 'Seleccione granja y campaña.');
      return;
    }
    if (_galponesSeleccionados.isEmpty) {
      showErrorToast(context, 'Seleccione al menos un galpón.');
      return;
    }
    if (_obsController.text.trim().isEmpty &&
        _agenteCausalController.text.trim().isEmpty) {
      showErrorToast(
        context,
        'Ingrese seguimiento o agente causal.',
      );
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 100));
    await _stopListening();

    final storage = context.read<StorageService>();
    final verSt = AppVersionService.fromStorage(storage);
    if (verSt.mustUpdate) {
      await AppVersionService.showStatusDialog(
        context,
        verSt,
        barrierDismissible: false,
      );
      return;
    }
    await AppVersionService.notifyIfNeeded(context, storage);

    final record = _buildRecord(storage);

    final saved = await RegisterSummarySheet.show(
      context,
      record: record,
      onConfirm: () async {
        // Siempre guardar en local primero
        await storage.saveRecord(record);
        record['synced'] = false;

        // Si no hay conexión, el registro ya quedó guardado en local
        if (!await _hasServerReachable()) return;

        if (!mounted) return;

        // Hay internet: mostrar feedback mientras se intenta subir
        final close = showChickenLoadingDialog(context, 'Enviando registro…');
        try {
          final api = ApiService();
          final result = await api.uploadSeguimiento(
            record,
            timeout: const Duration(seconds: 45),
          );
          debugPrint(
            '[guardar_seguimiento] respuesta: $result '
            '(id=${EvidenciaRecordId.of(record)})',
          );
          if (result['success'] == true) {
            await storage.markRecordAsSynced({
              ...record,
              'synced': true,
              'guardado_backend': true,
            });
            await storage.setLastSyncDate();
            record['synced'] = true;
            record['guardado_backend'] = true;
          }
        } catch (_) {
          // Falló el envío; el registro ya está guardado localmente
        } finally {
          close();
        }
      },
    );

    if (!mounted || !saved) return;
    if (record['synced'] == true) {
      showSuccessToast(context, 'Registro guardado y enviado');
    } else {
      showSuccessToast(
        context,
        'Registro guardado localmente (pendiente de subir)',
      );
    }
    _clearForm();
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();

    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? null
          : AppColors.background,
      drawer: const AppDrawer(),
      appBar: SectionAppBar(
        title: 'Registro de Seg.',
        sectionIcon: Icons.edit_note_outlined,
        actions: [AppBarSaveButton(onPressed: _guardar)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EvidenciaSelectField(
              label: 'Fecha',
              value: _fmtDateDisplay(_fecha),
              placeholder: 'Seleccione fecha',
              icon: Icons.calendar_today_outlined,
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _fecha,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null && d != _fecha) {
                  setState(() => _fecha = d);
                  await _reloadProyeccionPorFecha();
                }
              },
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: EvidenciaSelectField(
                    label: 'Granja',
                    value: _granjaLabel,
                    placeholder: 'Seleccione',
                    icon: Icons.warehouse_outlined,
                    onTap: () async {
                      if (!_catalogSync.hasUsableLocalCatalogs(storage)) {
                        showWarningToast(
                          context,
                          AppStrings.sinCatalogosLocales,
                        );
                        return;
                      }
                      final cencos = storage.getCencosGalpones() ??
                          {'cencos': storage.getCencosListaLocal()};
                      final proyeccion = storage.getProyeccion();
                      if (!mounted) return;
                      final sel = await GranjaCampaniaPicker.show(
                        context,
                        proyeccion: proyeccion,
                        cencosGalpones: cencos,
                        fechaYmd: _fmtDate(_fecha),
                      );
                      if (sel != null) {
                        _aplicarSeleccionGranja(storage, sel);
                        if (_galponesSeleccionados.isNotEmpty) {
                          await _refreshEdad();
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: EvidenciaSelectField(
                    label: 'CAMP',
                    value: _campaniaDisplay,
                    placeholder: _granja3.isEmpty
                        ? ''
                        : (_campania.isEmpty ? 'Elegir' : ''),
                    icon: Icons.tag,
                    showIcon: false,
                    enabled:
                        _granja3.isNotEmpty && _campaniasDeGranja.length > 1,
                    onTap: _granja3.isNotEmpty && _campaniasDeGranja.length > 1
                        ? () async {
                            final c = await GranjaCampaniaPicker.showCampania(
                              context,
                              campanias: _campaniasDeGranja,
                              selected: _campania,
                            );
                            if (c != null && c.isNotEmpty) {
                              setState(() {
                                _campania = c;
                                _galponesSeleccionados = [];
                                _edad = null;
                                _campaniaActiva = false;
                              });
                              _loadGalpones(storage);
                              if (_galponesSeleccionados.isNotEmpty) {
                                await _refreshEdad();
                              }
                            }
                          }
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            EvidenciaGalponField(
              value: _galponesSeleccionados,
              options: _galponCodes,
              enabled: _granja.isNotEmpty,
              onSelected: (v) async {
                setState(() => _galponesSeleccionados = v);
                await _refreshEdad();
              },
            ),
            if (_galponesSeleccionados.isNotEmpty && _mostrarEdad) ...[
              const SizedBox(height: 10),
              _EdadPolloLabel(edad: _edad!),
            ],
            const SizedBox(height: 14),
            _buildDictationTextField(
              controller: _obsController,
              label: 'Seguimiento',
            ),
            const SizedBox(height: 14),
            _buildDictationTextField(
              controller: _agenteCausalController,
              label: 'Agente causal',
            ),
            const SizedBox(height: 20),
            Text(
              'Imágenes (máx. 3)',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 10),
            ImageSlotRow(
              paths: _imagePaths,
              onChanged: (i, path) => setState(() => _imagePaths[i] = path),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDictationTextField({
    required TextEditingController controller,
    required String label,
  }) {
    final isActive = _listening && _dictationController == controller;

    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.sentences,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: context.textThemePrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
          borderSide: BorderSide(color: context.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
          borderSide: BorderSide(color: context.borderSubtle),
        ),
        suffixIcon: IconButton(
          tooltip: isActive ? 'Detener dictado' : 'Dictar',
          icon: isActive
              ? ScaleTransition(
                  scale: _micPulseAnimation,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.5),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.mic,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                )
              : Icon(
                  Icons.mic_none_outlined,
                  color: AppColors.iconAccent.withValues(alpha: 0.85),
                ),
          onPressed: () => _toggleDictation(controller),
        ),
      ),
      maxLines: 4,
    );
  }
}

class _EdadPolloLabel extends StatelessWidget {
  const _EdadPolloLabel({required this.edad});

  final int edad;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [
          Text(
            'Edad del pollo',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
          const Spacer(),
          Text(
            'Día $edad',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
