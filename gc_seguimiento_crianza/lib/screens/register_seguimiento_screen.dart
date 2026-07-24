import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../services/api_service.dart';
import '../services/catalog_sync_service.dart';
import '../services/storage_service.dart';
import '../services/vosk_service.dart';
import '../utils/constants.dart';
import '../utils/galpones_resolver.dart';
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

class _RegisterSeguimientoScreenState extends State<RegisterSeguimientoScreen> {
  DateTime _fecha = DateTime.now();
  String _granja = '';
  String _granjaNombre = '';
  String _campania = '';
  String _galpon = '';
  String? _fechaInicio;
  String? _fechaFin;
  int? _edad;
  bool _campaniaActiva = false;
  final _obsController = TextEditingController();
  final List<String?> _imagePaths = [null, null, null];
  List<Map<String, dynamic>> _galpones = [];
  bool _cargandoProyeccion = false;
  bool _listening = false;
  String _baseTextBeforeDictation = '';
  StreamSubscription<String?>? _voskResultSub;
  StreamSubscription<String?>? _voskPartialSub;

  String _fmtDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _fmtDateDisplay(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

  String get _campaniaEfectiva {
    if (_campania.isNotEmpty) return _campania;
    if (_granja.isNotEmpty) {
      return GranjaCampaniaPicker.campaniaFromCodigo(_granja);
    }
    return '';
  }

  String get _granjaCampaniaLabel {
    if (_granja.isEmpty) return '';
    final codDisplay = _granja.contains('-')
        ? _granja
        : GranjaCampaniaPicker.formatCodigoCorrelativo(
            _granja,
            _campaniaEfectiva,
          );
    return GranjaCampaniaPicker.formatEtiqueta(
      codigo6: codDisplay,
      nombre: _granjaNombre,
      campania: _campaniaEfectiva,
    );
  }

  String get _edadLabel {
    if (_campaniaActiva && _edad != null && _edad! > 0) {
      return 'Día $_edad';
    }
    return '—';
  }

  List<String> get _galponCodes => _galpones
      .map((g) => (g['tcodint'] ?? '').toString())
      .where((s) => s.isNotEmpty)
      .toList();

  @override
  void initState() {
    super.initState();
    VoskService.instance.addListener(_onVoskStateChanged);
    VoskService.instance.init();
  }

  @override
  void dispose() {
    _stopListening();
    VoskService.instance.removeListener(_onVoskStateChanged);
    _obsController.dispose();
    super.dispose();
  }

  void _onVoskStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _reloadProyeccionPorFecha() async {
    if (_cargandoProyeccion) return;
    setState(() => _cargandoProyeccion = true);
    try {
      final storage = context.read<StorageService>();
      await CatalogSyncService().syncProyeccion(
        storage: storage,
        fecha: _fmtDate(_fecha),
      );
      if (mounted) {
        setState(() {
          _granja = '';
          _granjaNombre = '';
          _campania = '';
          _galpon = '';
          _galpones = [];
          _fechaInicio = null;
          _fechaFin = null;
          _edad = null;
          _campaniaActiva = false;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _cargandoProyeccion = false);
    }
  }

  void _loadGalpones(StorageService storage) {
    if (_granja.isEmpty) {
      setState(() => _galpones = []);
      return;
    }
    final gps = GalponesResolver.resolveOffline(
      granjaCodigo: _granja,
      campania: _campaniaEfectiva,
      galponesPorGranja: storage.getGalponesPorGranjaMapLocal(),
      galponesPorCenco: storage.getGalponesPorCencoLocal(),
      cencosLista: storage.getCencosListaLocal(),
    );
    setState(() => _galpones = gps);
  }

  int? _calcEdadLocal(String fechaYmd, String fechaInicioYmd) {
    final a = DateTime.tryParse(fechaYmd);
    final b = DateTime.tryParse(fechaInicioYmd);
    if (a == null || b == null) return null;
    final edad =
        DateTime(a.year, a.month, a.day)
            .difference(DateTime(b.year, b.month, b.day))
            .inDays +
        1;
    return edad > 0 ? edad : null;
  }

  bool _isActiva(String? fi, String? ff, String ref) {
    if (fi == null || fi.isEmpty) return false;
    if (fi.compareTo(ref) > 0) return false;
    if (ff == null || ff.isEmpty || ff == '0000-00-00') return true;
    return ff.compareTo(ref) >= 0;
  }

  Future<void> _refreshEdad() async {
    final campania = _campaniaEfectiva;
    final fecha = _fmtDate(_fecha);
    if (_granja.isEmpty || campania.isEmpty) {
      setState(() {
        _edad = null;
        _campaniaActiva = false;
        _fechaInicio = null;
        _fechaFin = null;
      });
      return;
    }

    final api = ApiService();
    final res = await api.getCampaniaInfo(
      granja: _granja.length >= 3 ? _granja.substring(0, 3) : _granja,
      campania: campania,
      galpon: _galpon,
      fecha: fecha,
    );
    if (!mounted) return;
    if (res['success'] == true && res['data'] is Map) {
      final d = Map<String, dynamic>.from(res['data'] as Map);
      final fi = d['fecha_inicio']?.toString();
      final ff = d['fecha_fin']?.toString();
      final activa = d['activa'] == true;
      final edadApi = d['edad'];
      setState(() {
        _fechaInicio = fi;
        _fechaFin = ff;
        _campaniaActiva = activa;
        _edad = activa && edadApi != null
            ? int.tryParse(edadApi.toString())
            : null;
      });
      return;
    }

    // Fallback local si no hay red
    final activa = _isActiva(_fechaInicio, _fechaFin, fecha);
    setState(() {
      _campaniaActiva = activa;
      _edad = activa && _fechaInicio != null
          ? _calcEdadLocal(fecha, _fechaInicio!)
          : null;
    });
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
      'edad': _campaniaActiva ? _edad : null,
      'campaniaActiva': _campaniaActiva,
      'granja': _granja.length >= 3 ? _granja.substring(0, 3) : _granja,
      'granjaNombre': _granjaNombre,
      'campania': campania,
      'galpon': _galpon,
      'obs': _obsController.text.trim(),
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
      _galpon = '';
      _galpones = [];
      _fechaInicio = null;
      _fechaFin = null;
      _edad = null;
      _campaniaActiva = false;
      _obsController.clear();
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
    try {
      await VoskService.instance.speechService?.stop();
    } catch (_) {}
    if (mounted) setState(() => _listening = false);
  }

  Future<void> _toggleDictation() async {
    if (_listening) {
      await _stopListening();
      return;
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
    _baseTextBeforeDictation = _obsController.text.trim();
    setState(() => _listening = true);
    final speech = vosk.speechService!;
    _voskResultSub = speech.onResult().listen((raw) {
      final text = (raw ?? '').trim();
      if (text.isEmpty) return;
      final combined = _baseTextBeforeDictation.isEmpty
          ? text
          : '$_baseTextBeforeDictation $text';
      _obsController.value = TextEditingValue(
        text: combined,
        selection: TextSelection.collapsed(offset: combined.length),
      );
      _baseTextBeforeDictation = combined;
    });
    _voskPartialSub = speech.onPartial().listen((partialRaw) {
      final partial = (partialRaw ?? '').trim();
      if (partial.isEmpty) return;
      final combined = _baseTextBeforeDictation.isEmpty
          ? partial
          : '$_baseTextBeforeDictation $partial';
      _obsController.value = TextEditingValue(
        text: combined,
        selection: TextSelection.collapsed(offset: combined.length),
      );
    });
    try {
      await speech.start();
    } catch (e) {
      await _stopListening();
      if (mounted) showErrorToast(context, 'No se pudo iniciar el dictado.');
    }
  }

  Future<bool> _hasInternet() async {
    try {
      final r = await InternetAddress.lookup('google.com');
      return r.isNotEmpty;
    } on SocketException {
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
    if (_galpon.isEmpty) {
      showErrorToast(context, 'Seleccione galpón.');
      return;
    }
    if (_obsController.text.trim().isEmpty) {
      showErrorToast(context, 'Ingrese la observación.');
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 100));
    await _stopListening();

    final storage = context.read<StorageService>();
    final record = _buildRecord(storage);

    final saved = await RegisterSummarySheet.show(
      context,
      record: record,
      onConfirm: () async {
        await storage.saveRecord(record);
        if (await _hasInternet()) {
          final api = ApiService();
          final result = await api.uploadSeguimiento(record);
          if (result['success'] == true) {
            await storage.markRecordAsSynced({
              ...record,
              'synced': true,
              'guardado_backend': true,
            });
            record['synced'] = true;
            record['guardado_backend'] = true;
          }
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
    final proyeccion = storage.getProyeccion();

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: SectionAppBar(
        title: AppStrings.menuRegistro,
        sectionIcon: Icons.edit_note_outlined,
        actions: [AppBarSaveButton(onPressed: _guardar)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EvidenciaSelectField(
              label: 'Fecha',
              value: _fmtDateDisplay(_fecha),
              placeholder: 'Seleccione fecha',
              icon: Icons.calendar_today_outlined,
              onTap: _cargandoProyeccion
                  ? null
                  : () async {
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
            if (_cargandoProyeccion) ...[
              const SizedBox(height: 6),
              const LinearProgressIndicator(minHeight: 2),
            ],
            const SizedBox(height: 12),
            EvidenciaSelectField(
              label: 'Edad del pollo',
              value: _edadLabel,
              placeholder: _campaniaActiva
                  ? 'Se calcula con la fecha de inicio'
                  : 'Campaña no activa — solo se usa la fecha',
              icon: Icons.cake_outlined,
              enabled: false,
              onTap: null,
            ),
            const SizedBox(height: 12),
            EvidenciaSelectField(
              label: 'Granja y campaña',
              value: _granjaCampaniaLabel,
              placeholder: 'Toca para seleccionar',
              icon: Icons.warehouse_outlined,
              enabled: !_cargandoProyeccion,
              onTap: () async {
                final sel = await GranjaCampaniaPicker.show(
                  context,
                  proyeccion: proyeccion,
                  cencosGalpones: storage.getCencosGalpones(),
                );
                if (sel != null) {
                  final codigo = sel['granja'] ?? sel['codigo'] ?? '';
                  var camp = sel['campania'] ?? '';
                  if (camp.isEmpty && codigo.isNotEmpty) {
                    camp = GranjaCampaniaPicker.campaniaFromCodigo(codigo);
                  }
                  setState(() {
                    _granja = codigo;
                    _granjaNombre = sel['granjaNombre'] ?? '';
                    _campania = camp;
                    _galpon = '';
                  });
                  _loadGalpones(storage);
                  await _refreshEdad();
                }
              },
            ),
            const SizedBox(height: 12),
            EvidenciaGalponField(
              value: _galpon,
              options: _galponCodes,
              enabled: _granja.isNotEmpty,
              onSelected: (v) async {
                setState(() => _galpon = v);
                await _refreshEdad();
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _obsController,
              decoration: InputDecoration(
                labelText: 'Observación / seguimiento',
                alignLabelWithHint: true,
                suffixIcon: IconButton(
                  tooltip: _listening ? 'Detener dictado' : 'Dictar',
                  icon: Icon(
                    _listening ? Icons.mic : Icons.mic_none,
                    color: _listening ? Colors.red : AppColors.primary,
                  ),
                  onPressed: _toggleDictation,
                ),
              ),
              maxLines: 4,
            ),
            if (_listening)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Escuchando… toque el micrófono para detener',
                  style: TextStyle(fontSize: 12, color: Colors.redAccent),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'Imágenes (máx. 3)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ImageSlotRow(
              paths: _imagePaths,
              onChanged: (i, path) => setState(() => _imagePaths[i] = path),
            ),
          ],
        ),
      ),
    );
  }
}
