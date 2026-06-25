import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../models/cenco.dart';
import '../models/galpon.dart';
import '../utils/dialog_helper.dart';
import '../utils/constants.dart';
import '../utils/theme_extensions.dart';
import '../utils/toast_helper.dart';
import '../widgets/app_bar.dart';
import '../widgets/app_drawer.dart';
import '../widgets/dashed_photo_slot.dart';
import '../widgets/auditoria_summary_sheet.dart';
import '../widgets/searchable_select_dialog.dart';
import '../widgets/styled_select_field.dart';
import '../screens/image_editor_screen.dart';

// ─── Registro individual para la tabla de auditoria ───
class _RegistroAuditable {
  final String cabUuid;
  final String tipoMortalidad;
  final String? subtipoTransporte;
  final String? subtipoProduccion;
  final String granja;
  final String? granjaNombre;
  final String? campania;
  final String galpon;
  final String fechaRegistro;
  final int cantMachos;
  final int cantHembras;
  final int totalAves;

  bool aprobado = false;
  final TextEditingController obsController;
  final List<String> fotos;

  _RegistroAuditable({
    required this.cabUuid,
    required this.tipoMortalidad,
    this.subtipoTransporte,
    this.subtipoProduccion,
    required this.granja,
    this.granjaNombre,
    this.campania,
    required this.galpon,
    required this.fechaRegistro,
    required this.cantMachos,
    required this.cantHembras,
    required this.totalAves,
    TextEditingController? obsController,
    List<String>? fotos,
  })  : obsController = obsController ?? TextEditingController(),
        fotos = fotos ?? [];

  String get tipoLabel {
    final t = tipoMortalidad.toLowerCase();
    if (t == 'incubacion') return 'Planta Incubacion';
    if (t == 'despacho') return 'Despacho';
    if (t == 'transporte') return 'Transporte';
    if (t == 'produccion') return 'Produccion';
    return t;
  }

  String get clave {
    final t = tipoMortalidad.toLowerCase();
    if (t == 'incubacion' || t == 'despacho') return t;
    if (t == 'transporte') {
      final st = (subtipoTransporte ?? '').toLowerCase();
      return 'transporte:' + (st != 'evento' ? 'transporte' : 'evento');
    }
    if (t == 'produccion') {
      final valid = {'crianza', 'necropsia', 'laboratorio', 'cuarentena'};
      final st = (subtipoProduccion ?? '').toLowerCase();
      return 'produccion:' + (st.isNotEmpty && valid.contains(st) ? st : 'crianza');
    }
    return t;
  }

  void dispose() {
    obsController.dispose();
  }
}

// ─── Screen principal ───
class AuditoriaScreen extends StatefulWidget {
  const AuditoriaScreen({super.key});

  @override
  State<AuditoriaScreen> createState() => _AuditoriaScreenState();
}

class _AuditoriaScreenState extends State<AuditoriaScreen> {
  final _api = ApiService();
  final _picker = ImagePicker();
  static const int _maxPhotos = 5;
  static const double _photoSize = 60;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  final List<_RegistroAuditable> _registros = [];
  bool _seleccionarTodos = false;

  // Filtros de granja / galpon
  List<Cenco> _cencos = [];
  List<Galpon> _galpones = [];
  Cenco? _selectedCenco;
  Galpon? _selectedGalpon;
  List<Map<String, dynamic>> _cantidadPollos = [];
  bool _loadingCantidad = false;

  @override
  void initState() {
    super.initState();
    _loadCencos();
    _cargar();
  }

  @override
  void dispose() {
    for (final r in _registros) {
      r.dispose();
    }
    super.dispose();
  }

  // ─── Utilidades ───
  Future<bool> _checkInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    }
  }

  String _subtipoLabel(String tipo, String? subtipo) {
    final t = tipo.toLowerCase();
    if (t == 'incubacion') return 'Laboratorio';
    if (t == 'despacho') return 'Despacho';
    if (t == 'transporte') {
      final st = (subtipo ?? '').toLowerCase();
      return st == 'evento' ? 'Evento' : 'Traslado';
    }
    if (t == 'produccion') {
      final st = (subtipo ?? '').toLowerCase();
      final map = {'crianza': 'Crianza', 'necropsia': 'Necropsia', 'laboratorio': 'Laboratorio', 'cuarentena': 'Cuarentena'};
      return map[st] ?? 'Crianza';
    }
    return t;
  }

  IconData _iconoParaTipo(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'incubacion': return Icons.egg_outlined;
      case 'transporte': return Icons.local_shipping_outlined;
      case 'produccion': return Icons.egg_alt_rounded;
      case 'despacho': return Icons.inventory_2_outlined;
      default: return Icons.help_outline;
    }
  }

  Color _colorParaTipo(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'incubacion': return const Color(0xFFFFB300);
      case 'transporte': return const Color(0xFF42A5F5);
      case 'produccion': return const Color(0xFF66BB6A);
      case 'despacho': return const Color(0xFFFF7043);
      default: return AppColors.primary;
    }
  }

  List<_RegistroAuditable> get _selected => _registros.where((r) => r.aprobado).toList();

  int get _selectedMachos => _selected.fold(0, (s, r) => s + r.cantMachos);
  int get _selectedHembras => _selected.fold(0, (s, r) => s + r.cantHembras);
  int get _selectedTotalAves => _selected.fold(0, (s, r) => s + r.totalAves);
  int get _selectedCount => _selected.length;

  int get _totalMachos => _registros.fold(0, (s, r) => s + r.cantMachos);
  int get _totalHembras => _registros.fold(0, (s, r) => s + r.cantHembras);

  // ─── Carga catalogos ───
  void _loadCencos() {
    final storage = context.read<StorageService>();
    final raw = storage.getCencosLocal();
    debugPrint('[CENCOS_LOAD] auditoria_screen: getCencosLocal().length=${raw.length}');
    _cencos = raw
        .map((e) => Cenco.fromJson(e))
        .toList()
      ..sort((a, b) => a.codigo.compareTo(b.codigo));
    debugPrint('[CENCOS_LOAD] auditoria_screen: _cencos.length=${_cencos.length}');
    // Auto-seleccionar granja por defecto si esta configurada
    final defaultGranja = storage.getDefaultGranja();
    if (defaultGranja != null && defaultGranja.isNotEmpty && _selectedCenco == null) {
      _selectedCenco = _cencos.cast<Cenco?>().firstWhere(
            (c) => c?.granjaCodigo == defaultGranja,
            orElse: () => null,
          );
      if (_selectedCenco != null) {
        _loadGalpones(_selectedCenco!.codigo);
      }
    }
  }

  void _loadGalpones(String cencoCode) {
    final storage = context.read<StorageService>();
    final raw = storage.getGalponesPorCenco(cencoCode);
    _galpones = raw.map((e) => Galpon.fromJson(e)).toList();
  }

  Future<void> _loadCantidadPollos() async {
    final cenco = _selectedCenco;
    final galpon = _selectedGalpon;
    if (cenco == null || galpon == null) {
      setState(() => _cantidadPollos = []);
      return;
    }
    setState(() => _loadingCantidad = true);

    // Intentar desde cache primero
    final storage = context.read<StorageService>();
    final cached = storage.getCantidadPollosPorGalpon(cenco.codigo, galpon.tcodint);
    if (cached.isNotEmpty) {
      setState(() {
        _cantidadPollos = cached;
      });
    }

    // Refrescar desde API y guardar en cache
    try {
      final res = await _api.downloadCantidadPollos(
        tcencos: cenco.codigo,
        galpon: galpon.tcodint,
      );
      if (res['success'] == true && mounted) {
        final items = (res['items'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        // Guardar en cache (con y sin fecha para compatibilidad)
        final allCache = storage.getCantidadPollos();
        allCache['${cenco.codigo}_${galpon.tcodint}'] = items;
        await storage.saveCantidadPollos(allCache);
        setState(() {
          _cantidadPollos = items;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingCantidad = false);
  }

  // ─── Carga de registros pendientes ───
  Future<void> _cargar() async {
    // Limpiar estado anterior
    for (final r in _registros) {
      r.dispose();
    }
    _registros.clear();
    _seleccionarTodos = false;

    // Cargar cache local inmediatamente para respuesta rapida
    final storage = context.read<StorageService>();
    final cached = storage.getAuditoriaPendienteCache();
    if (cached.isNotEmpty) {
      // Filtrar cache por granja configurada para evitar flicker
      final granjaFilter = _selectedCenco?.granjaCodigo;
      final galponFilter = _selectedGalpon?.tcodint;
      var filtered = cached;
      if (granjaFilter != null && granjaFilter.isNotEmpty) {
        filtered = filtered.where((m) {
          return m['granja']?.toString().startsWith(granjaFilter) == true;
        }).toList();
      }
      if (galponFilter != null && galponFilter.isNotEmpty) {
        filtered = filtered.where((m) {
          return m['galpon']?.toString() == galponFilter;
        }).toList();
      }
      _poblarRegistrosDesdeRaw(filtered);
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    // Intentar refrescar desde API en background (solo si hay internet)
    if (await _checkInternet()) {
      final res = await _api.listarAuditoriaPendiente(
      granjaCodigo: _selectedCenco?.granjaCodigo,
      campaniaCodigo: _selectedCenco?.campaniaCodigo,
      galponCodigo: _selectedGalpon?.tcodint,
    );
    if (!mounted) return;

    if (res['success'] == true) {
      // API exitosa: guardar en cache y poblar registros
    final data = res['data'];
    final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
      final rawRegistros = map['registros'];

      if (rawRegistros is List) {
        final rawList = rawRegistros
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        await storage.saveAuditoriaPendienteCache(rawList);
        _poblarRegistrosDesdeRaw(rawList);
      }
    }
    }

    setState(() {
      _loading = false;
    });
  }

  String _fmtFechaAud(String raw) {
    if (raw.length < 10) return raw;
    try {
      final parts = raw.substring(0, 10).split('-');
      if (parts.length == 3) {
        return '${parts[2]}/${parts[1]}/${parts[0].substring(2)}';
      }
    } catch (_) {}
    return raw;
  }

  void _poblarRegistrosDesdeRaw(List<Map<String, dynamic>> rawList) {
    _registros.clear();
    for (final m in rawList) {
      final rawGranja = m['granja']?.toString() ?? '';
      final rawGranjaNombre = m['granja_nombre']?.toString();
      final resolvedGranjaNombre = rawGranjaNombre != null && rawGranjaNombre.trim().isNotEmpty
          ? rawGranjaNombre
          : _resolveGranjaFromCencos(rawGranja);
      _registros.add(_RegistroAuditable(
        cabUuid: m['cab_uuid']?.toString() ?? '',
        tipoMortalidad: m['tipoMortalidad']?.toString() ?? '',
        subtipoTransporte: m['subtipoTransporte']?.toString(),
        subtipoProduccion: m['subtipoProduccion']?.toString(),
        granja: rawGranja,
        granjaNombre: resolvedGranjaNombre,
        campania: m['campania']?.toString(),
        galpon: m['galpon']?.toString() ?? '',
        fechaRegistro: m['fechaRegistro']?.toString() ?? '',
        cantMachos: int.tryParse(m['cant_machos']?.toString() ?? '0') ?? 0,
        cantHembras: int.tryParse(m['cant_hembras']?.toString() ?? '0') ?? 0,
          totalAves: int.tryParse(m['total_aves']?.toString() ?? '0') ?? 0,
        ));
      }
    }

  String _resolveGranjaFromCencos(String rawCode) {
    if (rawCode.trim().isEmpty) return '';
    final prefix = rawCode.length >= 3 ? rawCode.substring(0, 3) : rawCode;
    final found = _cencos.cast<Cenco?>().firstWhere(
      (c) => c?.granjaCodigo == prefix,
      orElse: () => null,
    );
    return found?.labelShort ?? rawCode;
  }

  // ─── Acciones ───
  Future<void> _pickImage(_RegistroAuditable reg) async {
    if (reg.fotos.length >= _maxPhotos) {
      showWarningToast(context, 'Maximo $_maxPhotos fotos');
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded, color: AppColors.primary),
                title: const Text('Camara'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: AppColors.primary),
                title: const Text('Galeria'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;

    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${dir.path}/mortalidad_images');
    if (!imagesDir.existsSync()) imagesDir.createSync(recursive: true);
    final dest = File(
      '${imagesDir.path}/audit_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await File(picked.path).copy(dest.path);

    if (!mounted) return;
    setState(() => reg.fotos.add(dest.path));
  }

  void _toggleTodos(bool? v) {
    setState(() {
      _seleccionarTodos = v ?? false;
      for (final r in _registros) {
        r.aprobado = _seleccionarTodos;
      }
    });
  }

  Future<void> _guardar() async {
    final seleccionados = _selected;
    if (seleccionados.isEmpty) {
      showWarningToast(context, 'Seleccione al menos un registro para auditar');
      return;
    }

    final storage = context.read<StorageService>();
    final usuario = storage.getUserCodeSync() ?? '';
    if (usuario.isEmpty) {
      showErrorToast(context, 'No hay usuario en sesion');
      return;
    }

    // Agrupar seleccionados por clave
    final gruposMap = <String, List<_RegistroAuditable>>{};
    for (final r in seleccionados) {
      final key = r.clave;
      gruposMap.putIfAbsent(key, () => []).add(r);
    }

    final registrosPayload = gruposMap.entries.map((e) {
      final items = e.value;
      final allObs = items.map((r) => r.obsController.text.trim()).where((o) => o.isNotEmpty).join(' | ');
      final allFotos = items.expand((r) => r.fotos).toList();
      final allUuids = items.map((r) => r.cabUuid).toList();
      final sumMachos = items.fold<int>(0, (s, r) => s + r.cantMachos);
      final sumHembras = items.fold<int>(0, (s, r) => s + r.cantHembras);
      final sumTotal = items.fold<int>(0, (s, r) => s + r.totalAves);
      final firstItem = items.first;
      return {
        'clave': e.key,
        'aprobado': true,
        'registro_uuids': allUuids,
        'observaciones': allObs,
        'fotos': allFotos,
        'cant_machos': sumMachos,
        'cant_hembras': sumHembras,
        'total_aves': sumTotal,
        'granja': firstItem.granja,
        'granja_nombre': (firstItem.granjaNombre != null && firstItem.granjaNombre!.trim().isNotEmpty)
            ? firstItem.granjaNombre
            : _resolveGranjaFromCencos(firstItem.granja),
        'campania': firstItem.campania,
        'galpon': firstItem.galpon,
        'fecha_registro': firstItem.fechaRegistro,
      };
    }).toList();

    final totalReg = seleccionados.length;
    final totalAvesSel = _selectedTotalAves;
    final hasInternet = await _checkInternet();
    if (!mounted) return;

    final confirmed = await AuditoriaSummarySheet.show(
      context: context,
      usuario: usuario,
      grupos: seleccionados.map((r) => AuditoriaGrupoResumen(
        clave: r.clave,
        label: r.tipoLabel,
        totalRegistros: 1,
        totalAves: r.totalAves,
        observaciones: r.obsController.text,
        fotos: List<String>.from(r.fotos),
        granja: r.granja,
      granjaNombre: (r.granjaNombre != null && r.granjaNombre!.trim().isNotEmpty)
          ? r.granjaNombre
          : _resolveGranjaFromCencos(r.granja),
        campania: r.campania,
        galpon: r.galpon,
        cantMachos: r.cantMachos,
        cantHembras: r.cantHembras,
      )).toList(),
      totalRegistros: totalReg,
      totalAves: totalAvesSel,
    );
    if (confirmed != true || !mounted) return;

    await _confirmarGuardar(
      storage: storage,
      usuario: usuario,
      seleccionados: seleccionados,
      registros: registrosPayload,
      hasInternet: hasInternet,
    );
  }

  Future<void> _confirmarGuardar({
    required StorageService storage,
    required String usuario,
    required List<_RegistroAuditable> seleccionados,
    required List<Map<String, dynamic>> registros,
    required bool hasInternet,
  }) async {
    setState(() => _saving = true);
    final close = showChickenLoadingDialog(context, 'Guardando auditoria...');

    try {
      if (hasInternet) {
        final res = await _api.guardarAuditoriaMovil(
          usuario: usuario,
          registros: registros,
        );
        close();
        if (!mounted) return;

        if (res['success'] == true) {
          await _guardarLocal(storage, usuario, registros, synced: true,
            granja: seleccionados.first.granja,
            granjaNombre: seleccionados.first.granjaNombre,
            campania: seleccionados.first.campania,
            fecha: seleccionados.first.fechaRegistro,
            cantMachos: seleccionados.fold<int>(0, (s, r) => s + r.cantMachos),
            cantHembras: seleccionados.fold<int>(0, (s, r) => s + r.cantHembras),
          );
          if (!mounted) return;
          showSuccessToast(context, AppStrings.auditoriaGuardadaExitoso);
          _quitarGuardados(seleccionados);
          await _cargar();
        } else {
          await _guardarLocal(storage, usuario, registros, synced: false,
            granja: seleccionados.first.granja,
            granjaNombre: seleccionados.first.granjaNombre,
            campania: seleccionados.first.campania,
            fecha: seleccionados.first.fechaRegistro,
            cantMachos: seleccionados.fold<int>(0, (s, r) => s + r.cantMachos),
            cantHembras: seleccionados.fold<int>(0, (s, r) => s + r.cantHembras),
          );
          if (!mounted) return;
          _quitarGuardados(seleccionados);
          showWarningToast(
            context,
            AppStrings.auditoriaGuardadaLocal,
            duration: const Duration(seconds: 5),
          );
        }
      } else {
        await _guardarLocal(storage, usuario, registros,
          granja: seleccionados.first.granja,
          granjaNombre: seleccionados.first.granjaNombre,
          campania: seleccionados.first.campania,
          fecha: seleccionados.first.fechaRegistro,
          cantMachos: seleccionados.fold<int>(0, (s, r) => s + r.cantMachos),
          cantHembras: seleccionados.fold<int>(0, (s, r) => s + r.cantHembras),
        );
        close();
        if (!mounted) return;
        _quitarGuardados(seleccionados);
        showSuccessToast(context, AppStrings.auditoriaGuardadaLocal);
      }
    } catch (e) {
      close();
      if (mounted) showErrorToast(context, 'Error inesperado. Intente de nuevo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _guardarLocal(
    StorageService storage,
    String usuario,
    List<Map<String, dynamic>> registros, {
    bool synced = false,
    String? granja,
    String? granjaNombre,
    String? campania,
    String? fecha,
    int cantMachos = 0,
    int cantHembras = 0,
  }) async {
    final now = DateTime.now();
    await storage.saveForm(AppStrings.formTypeAuditoria, {
      'tuuid': const Uuid().v4(),
      'synced': synced,
      'guardado_backend': synced,
      'tipo': 'auditoria',
      'tdate_trans': DateFormat('yyyy-MM-dd').format(now),
      'ttime_trans': DateFormat('HH:mm:ss').format(now),
      'fecha': fecha ?? DateFormat('yyyy-MM-dd').format(now),
      'usuario': usuario,
      'observaciones': '',
      'granja': granja ?? '',
      'granja_nombre': granjaNombre ?? '',
      'campania': campania ?? '',
      'cant_machos': cantMachos,
      'cant_hembras': cantHembras,
      'registros': registros,
    });
    if (synced) {
      await storage.setLastSyncDate();
    }
  }

  void _quitarGuardados(List<_RegistroAuditable> seleccionados) {
    final uuids = seleccionados.map((r) => r.cabUuid).toSet();
    for (final r in seleccionados) {
      r.dispose();
    }
    _registros.removeWhere((r) => uuids.contains(r.cabUuid));
  }

  // ─── Widgets ───
  Widget _buildSummaryCards(BuildContext context) {
    final selCount = _selectedCount;
    final selM = _selectedMachos;
    final selH = _selectedHembras;
    final totalM = _totalMachos;
    final totalH = _totalHembras;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              value: selCount > 0 ? '$selM' : '$totalM',
              label: 'Machos',
              sub: selCount > 0 ? 'de $totalM total' : null,
              color: AppColors.maleDark,
              bgColor: AppColors.maleTint,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              value: selCount > 0 ? '$selH' : '$totalH',
              label: 'Hembras',
              sub: selCount > 0 ? 'de $totalH total' : null,
              color: AppColors.femaleDark,
              bgColor: AppColors.femaleTint,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              value: selCount > 0 ? '${_selectedTotalAves}' : '${totalM + totalH}',
              label: 'Total aves',
              sub: selCount > 0 ? 'de ${totalM + totalH} total' : null,
              color: AppColors.primary,
              bgColor: AppColors.primary.withValues(alpha: 0.08),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              value: selCount > 0 ? '$selCount' : '${_registros.length}',
              label: 'Registros',
              sub: selCount > 0 ? 'de ${_registros.length} total' : null,
              color: AppColors.info,
              bgColor: AppColors.info.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: context.borderColor),
      ),
      child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              StyledSelectField(
                label: 'Granja / Campania',
                value: _selectedCenco?.labelFilter ?? 'Todas las granjas',
                placeholder: 'Seleccionar granja...',
                icon: Icons.home_work_outlined,
                compact: true,
                onTap: _pickCenco,
              ),
              const SizedBox(height: 8),
              StyledSelectField(
                label: 'Galpon',
                value: _selectedGalpon?.tcodint ?? 'Todos los galpones',
                placeholder: _selectedCenco == null
                    ? 'Seleccione una granja'
                    : 'Seleccionar galpon...',
                icon: Icons.warehouse_outlined,
                compact: true,
                enabled: _selectedCenco != null,
                onTap: _pickGalpon,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCantidadPollosCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                Text(
            'Cantidad de pollos',
                  style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: context.mutedTextColor,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            children: _cantidadPollos.map((item) {
              final descri = item['descri']?.toString() ?? '';
              final cant = item['cantidad'] ?? 0;
              return Text(
                '$descri: $cant',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _sectionHeaderLabel(String tipo) {
    switch (tipo) {
      case 'produccion': return 'Produccion:';
      case 'despacho': return 'Despacho:';
      case 'incubacion': return 'Planta Incubacion:';
      case 'transporte': return 'Transporte:';
      default: return '${tipo[0].toUpperCase()}${tipo.substring(1)}:';
    }
  }

  Widget _buildSectionHeader(String tipo) {
    final count = _registros.where((r) => r.tipoMortalidad.toLowerCase() == tipo).length;
    final icono = _iconoParaTipo(tipo);
    final color = _colorParaTipo(tipo);
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 10, 0, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: color, width: 4),
        ),
      ),
      child: Row(
              children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icono, size: 16, color: color),
          ),
                const SizedBox(width: 8),
          Text(
            _sectionHeaderLabel(tipo),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGroupedRows() {
    final slivers = <Widget>[];
    const tipos = ['produccion', 'despacho', 'incubacion', 'transporte'];
    for (final tipo in tipos) {
      final items = _registros
          .where((r) => r.tipoMortalidad.toLowerCase() == tipo)
          .toList();
      if (items.isEmpty) continue;
      slivers.add(SliverToBoxAdapter(child: _buildSectionHeader(tipo)));
      slivers.add(SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildTableRow(context, items[index]),
          childCount: items.length,
        ),
      ));
    }
    return slivers;
  }

  Widget _buildTableHeader(BuildContext context) {
    return Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
      child: Row(
          children: [
          SizedBox(
            width: 40,
            child: Checkbox(
              value: _seleccionarTodos,
              onChanged: _toggleTodos,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(flex: 3, child: SizedBox(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text('Fecha y Tipo', style: _headerTextStyle),
            ),
          )),
          Expanded(flex: 1, child: Text('M', style: _headerTextStyle, textAlign: TextAlign.center)),
          Expanded(flex: 1, child: Text('H', style: _headerTextStyle, textAlign: TextAlign.center)),
          Expanded(flex: 1, child: Text('Tot', style: _headerTextStyle, textAlign: TextAlign.center)),
          SizedBox(width: 56, child: Text('Opc.', style: _headerTextStyle, textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  TextStyle get _headerTextStyle => const TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: AppColors.primaryDark,
  );

  TextStyle get _cellTextStyle => const TextStyle(fontSize: 13);

  Widget _buildTableRow(BuildContext context, _RegistroAuditable reg) {
    final fecha = _fmtFechaAud(reg.fechaRegistro);
    final isSelected = reg.aprobado;

    final tipoColor = _colorParaTipo(reg.tipoMortalidad);
    final tipoLabel = _subtipoLabel(reg.tipoMortalidad, reg.subtipoTransporte ?? reg.subtipoProduccion);

    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    decoration: BoxDecoration(
        color: isSelected
            ? tipoColor.withValues(alpha: 0.06)
            : null,
                      borderRadius: BorderRadius.circular(8),
        border: isSelected
            ? Border(
                left: BorderSide(color: tipoColor, width: 3),
              )
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Checkbox(
              value: reg.aprobado,
              onChanged: (v) => setState(() => reg.aprobado = v ?? false),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              activeColor: tipoColor,
              checkColor: Colors.white,
            ),
          ),
          const SizedBox(width: 4),
                Expanded(
            flex: 3,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                    children: [
                  Text(fecha, style: _cellTextStyle.copyWith(fontSize: 12)),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 1, height: 14,
                    color: Colors.grey.withValues(alpha: 0.3),
                  ),
                      Text(
                    tipoLabel,
                        style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: tipoColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${reg.cantMachos}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.maleDark),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${reg.cantHembras}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.femaleDark),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${reg.totalAves}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(
            width: 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _iconWithBadge(
                  icon: reg.obsController.text.isNotEmpty
                      ? Icons.note_alt_rounded
                      : Icons.notes_rounded,
                  color: reg.obsController.text.isNotEmpty
                      ? tipoColor
                      : context.mutedTextColor,
                  tooltip: 'Observaciones',
                  hasContent: reg.obsController.text.isNotEmpty,
                  onTap: () => _showObsDialog(reg),
                ),
                const SizedBox(width: 4),
                _iconWithBadge(
                  icon: reg.fotos.isNotEmpty
                      ? Icons.photo_camera_rounded
                      : Icons.photo_camera_outlined,
                  color: reg.fotos.isNotEmpty
                      ? tipoColor
                      : context.mutedTextColor,
                  tooltip: 'Fotos (${reg.fotos.length})',
                  hasContent: reg.fotos.isNotEmpty,
                  badgeCount: reg.fotos.length,
                  onTap: () => _showFotosDialog(reg),
                      ),
                    ],
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: const Border(
          left: BorderSide(color: AppColors.primary, width: 4),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 40),
          Expanded(
            flex: 2,
            child: Text(
              'TOTALES',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: context.primaryTextColor),
            ),
          ),
          Expanded(flex: 2, child: Text('${_registros.length} reg.', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          Expanded(flex: 1, child: Text('$_totalMachos', textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.maleDark))),
          Expanded(flex: 1, child: Text('$_totalHembras', textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.femaleDark))),
          Expanded(flex: 1, child: Text('${_totalMachos + _totalHembras}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
          const SizedBox(width: 56),
        ],
      ),
    );
  }

  void _showObsDialog(_RegistroAuditable reg) {
    final controller = TextEditingController(text: reg.obsController.text);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Observaciones'),
          content: TextField(
            controller: controller,
            maxLines: 4,
            decoration: const InputDecoration(
                hintText: 'Observaciones del auditor...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                setState(() => reg.obsController.text = controller.text);
                setDialogState(() {});
                Navigator.pop(ctx);
              },
              child: const Text('Guardar'),
                ),
              ],
            ),
      ),
    );
  }

  void _showFotosDialog(_RegistroAuditable reg) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Fotos (${reg.fotos.length}/$_maxPhotos)'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
            SizedBox(
                  height: _photoSize + 8,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                      ...reg.fotos.asMap().entries.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: DashedPhotoSlot(
                            size: _photoSize,
                            imagePath: e.value,
                            onAdd: () async {
                              await _pickImage(reg);
                              if (mounted) setDialogState(() {});
                            },
                            onTapImage: () async {
                              final edited = await Navigator.push<XFile?>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ImageEditorScreen(imageFile: XFile(reg.fotos[e.key])),
                                ),
                              );
                              if (edited != null && mounted) {
                                setState(() => reg.fotos[e.key] = edited.path);
                                setDialogState(() {});
                              }
                            },
                            onDeleteImage: () {
                              setState(() => reg.fotos.removeAt(e.key));
                              setDialogState(() {});
                            },
                          ),
                        ),
                      ),
                      if (reg.fotos.length < _maxPhotos)
                    DashedPhotoSlot(
                      size: _photoSize,
                          onAdd: () async {
                            await _pickImage(reg);
                            if (mounted) setDialogState(() {});
                          },
                    ),
                ],
              ),
            ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
          ],
        ),
      ),
    );
  }

  // ─── Selectores granja/galpon ───
  Future<void> _pickCenco() async {
    if (_cencos.isEmpty) {
      showInfoToast(context, 'No hay granjas disponibles. Descargue desde el menu.');
      return;
    }

    final opciones = <({String id, String label})>[
      (id: '__todas__', label: 'Todas las granjas'),
      for (final c in _cencos) (id: c.codigo, label: c.labelFilter),
    ];

    final selectedValue = _selectedCenco?.codigo ?? '__todas__';

    await showSearchableSelectDialog<({String id, String label})>(
      context: context,
      title: 'Granja / Campania',
      icon: Icons.home_work_outlined,
      items: opciones,
      getLabel: (o) => o.label,
      showSubtitle: false,
      selectedValue: selectedValue,
      getValue: (o) => o.id,
      onSelected: (id) {
        if (id == null) return;
        setState(() {
          if (id == '__todas__') {
            _selectedCenco = null;
            _selectedGalpon = null;
            _galpones = [];
          } else {
            final found = _cencos.where((c) => c.codigo == id).firstOrNull;
            _selectedCenco = found;
            _selectedGalpon = null;
            _loadGalpones(found!.codigo);
          }
        });
        _cargar();
      },
    );
  }

  Future<void> _pickGalpon() async {
    if (_selectedCenco == null) {
      showInfoToast(context, 'Seleccione primero la granja / campania.');
      return;
    }
    final options = <({String id, String label})>[
      (id: '__todos__', label: 'Todos los galpones'),
      ..._galpones.map((g) => (id: g.tcodint, label: g.tcodint)),
    ];
    await showSearchableSelectDialog<({String id, String label})>(
      context: context,
      title: 'Galpon',
      icon: Icons.warehouse_outlined,
      items: options,
      getLabel: (o) => o.label,
      selectedValue: _selectedGalpon?.tcodint ?? '__todos__',
      getValue: (o) => o.id,
      onSelected: (id) {
        if (id == null) return;
        setState(() {
          if (id == '__todos__') {
            _selectedGalpon = null;
          } else {
            final found = _galpones.firstWhere((g) => g.tcodint == id);
            _selectedGalpon = found;
          }
        });
        _cargar();
        if (_selectedGalpon != null) _loadCantidadPollos();
      },
      emptyMessage: 'Sin galpones para esta granja',
    );
  }

  // ─── Build principal ───
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildAppBar(
        context,
        AppStrings.auditoriaTitle,
        appIcon: Icons.fact_check_outlined,
        rightIcon: (!_loading && _registros.isNotEmpty && !_saving) ? Icons.save : null,
        rightIconColor: AppColors.iconAccent,
        rightIconLoading: _saving,
        rightIconTooltip: 'Guardar auditoria',
        onRightIconPressed: (!_loading && _registros.isNotEmpty && !_saving) ? _guardar : null,
      ),
      drawer: const AppDrawer(),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _cargar,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildFilterRow()),
              if (_cantidadPollos.isNotEmpty)
                SliverToBoxAdapter(child: _buildCantidadPollosCard()),
              if (_loadingCantidad)
                const SliverToBoxAdapter(
                    child: Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      height: 16,
                      child: Center(
                        child: SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(child: _buildSummaryCards(context)),
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              else if (_registros.isEmpty)
                SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                          child: Column(
                            children: [
                                Icon(Icons.verified_outlined, size: 64, color: AppColors.primary.withValues(alpha: 0.5)),
                              const SizedBox(height: 16),
                              Text(
                                  'No hay registros pendientes de auditoria',
                                textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 16, color: context.mutedTextColor),
                              ),
                            ],
                            ),
                          ),
                        ),
                      )
                    else ...[
                      SliverToBoxAdapter(child: _buildTableHeader(context)),
                      ..._buildGroupedRows(),
                      SliverToBoxAdapter(child: _buildTotalRow(context)),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

// ─── Widgets auxiliares ───

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final String? sub;
  final Color color;
  final Color bgColor;

  const _StatCard({
    required this.value,
    required this.label,
    this.sub,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark ? Colors.grey.shade400 : Colors.grey.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
      child: Column(
                          children: [
          Text(value,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: color)),
          const SizedBox(height: 2),
          Text(label,
                              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: labelColor)),
          if (sub != null)
            Text(sub!,
                style: TextStyle(fontSize: 10, color: labelColor.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}

Widget _iconWithBadge({
  required IconData icon,
  required Color color,
  required String tooltip,
  required bool hasContent,
  required VoidCallback onTap,
  int badgeCount = 0,
}) {
  return Tooltip(
    message: tooltip,
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, size: 16, color: color),
            if (hasContent)
              Positioned(
                top: -4,
                right: -5,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            if (badgeCount > 1)
              Positioned(
                top: -7,
                right: -8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                ),
              ),
                          ],
                        ),
                      ),
      ),
    );
}
