import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/cenco.dart';
import '../models/galpon.dart';
import '../models/mortality_detail.dart';
import '../models/motivo_mortalidad.dart';
import '../services/api_service.dart';
import '../services/catalog_download_service.dart';
import '../services/storage_service.dart';
import '../utils/app_dialogs.dart';
import '../utils/constants.dart';
import '../utils/dialog_helper.dart';
import '../utils/mortality_design.dart';
import '../utils/text_utils.dart';
import '../utils/theme_extensions.dart';
import '../utils/toast_helper.dart';
import '../widgets/app_bar.dart';
import '../widgets/form_section_card.dart' show FormSectionTitle;
import '../widgets/inline_mortality_section.dart';
import '../widgets/mortality_detail_dialog.dart';
import '../widgets/mortality_details_section.dart';
import '../widgets/searchable_select_dialog.dart';
import '../widgets/mortality_summary_sheet.dart';
import '../widgets/poultry_icon.dart';
import '../widgets/styled_select_field.dart';

class MortalityFormScreen extends StatefulWidget {
  final MortalityType type;
  final Map<String, dynamic>? existingRecord;
  final bool isEditing;
  final String? initialSubtipoTransporte;
  final String? initialOrigenAnalisis;

  const MortalityFormScreen({
    super.key,
    required this.type,
    this.existingRecord,
    this.isEditing = false,
    this.initialSubtipoTransporte,
    this.initialOrigenAnalisis,
  });

  @override
  State<MortalityFormScreen> createState() => _MortalityFormScreenState();
}

class _MortalityFormScreenState extends State<MortalityFormScreen> {
  final _obsController = TextEditingController();
  final _scrollController = ScrollController();
  final _keyFechaLlegada = GlobalKey();
  final _keyGranja = GlobalKey();
  final _keyGalpon = GlobalKey();
  final _keyDetalles = GlobalKey();

  DateTime _fecha = DateTime.now();
  DateTime? _fechaLlegada;
  Cenco? _selectedCenco;
  Galpon? _selectedGalpon;
  final List<MortalityDetail> _detalles = [];
  String? _subtipoTransporte;
  String? _origenAnalisis;
  String? _tuuid;

  String? _errorGranja;
  String? _errorGalpon;
  String? _errorFechaLlegada;
  String? _errorDetallesCantidad;
  String? _errorDetallesCausa;
  String? _errorDetallesAgregar;
  bool _dirty = false;
  bool _saving = false;
  bool _sinMortalidad = false;

  List<Cenco> _cencos = [];
  List<Galpon> _galpones = [];
  List<MotivoMortalidad> _motivos = [];
  StorageService? _storage;
  final _catalogDownload = CatalogDownloadService();
  final _apiService = ApiService();
  bool _motivosFetchStarted = false;
  List<Map<String, dynamic>> _cantidadPollos = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final storage = context.read<StorageService>();
      if (!storage.canSeeMortalityType(widget.type.id)) {
        showErrorToast(context, 'No tiene permiso para este tipo de mortalidad.');
        Get.back();
      }
    });
    if (widget.existingRecord != null) {
      _loadExisting(widget.existingRecord!);
    } else {
      _subtipoTransporte = widget.type == MortalityType.transporte
          ? (widget.initialSubtipoTransporte ?? 'transporte')
          : null;
      _origenAnalisis = widget.type == MortalityType.produccion
          ? (widget.initialOrigenAnalisis ?? 'Crianza')
          : null;
    }
    _obsController.addListener(() => _dirty = true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _storage?.removeListener(_onCatalogsChanged);
    _storage = context.read<StorageService>();
    _storage!.addListener(_onCatalogsChanged);
    _loadCatalogs();
    _fetchMotivosIfNeeded();
  }

  Future<void> _fetchMotivosIfNeeded() async {
    if (_motivosFetchStarted || _storage == null) return;
    if (_motivos.isNotEmpty) return;
    _motivosFetchStarted = true;
    await _catalogDownload.downloadMotivosIfNeeded(_storage!);
    if (mounted) _loadCatalogs();
  }

  void _onCatalogsChanged() {
    if (mounted) _loadCatalogs();
  }

  void _loadExisting(Map<String, dynamic> r) {
    _tuuid = r['tuuid']?.toString();
    final fechaStr = r['fecha']?.toString() ?? '';
    if (fechaStr.isNotEmpty) {
      try {
        _fecha = DateFormat('yyyy-MM-dd').parse(fechaStr);
      } catch (_) {}
    }
    _detalles
      ..clear()
      ..addAll(MortalityDetail.listFromRecord(r));
    _subtipoTransporte = r['subtipo_transporte']?.toString();
    _origenAnalisis = r['origen_analisis']?.toString();
    _obsController.text = r['observaciones']?.toString() ?? '';
    final llegadaStr = r['fecha_llegada']?.toString() ?? '';
    if (llegadaStr.isNotEmpty) {
      try {
        _fechaLlegada = DateFormat('yyyy-MM-dd').parse(llegadaStr);
      } catch (_) {}
    }
    if (_permiteRegistroCero) {
      final total = MortalityDetail.totalMachos(_detalles) +
          MortalityDetail.totalHembras(_detalles);
      _sinMortalidad = total == 0;
    }
  }

  Future<void> _pickDate({
    required DateTime initial,
    required ValueChanged<DateTime> onPicked,
    VoidCallback? onAfterPick,
  }) async {
    final picked = await showAppDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        onPicked(picked);
        onAfterPick?.call();
        _dirty = true;
      });
    }
  }

  void _reconcileDetailErrors() {
    final total = MortalityDetail.totalMachos(_detalles) +
        MortalityDetail.totalHembras(_detalles);

    if (_errorDetallesCantidad != null && total > 0) {
      _errorDetallesCantidad = null;
    }

    final needsCausa = mortalityShowsCausa(
      widget.type,
      origenAnalisis: _origenAnalisis,
    );

    if (_errorDetallesCausa != null && needsCausa) {
      final causaIncompleta = _detalles.any(
        (d) =>
            d.cantidad > 0 &&
            (d.causaCodigo == null || d.causaCodigo!.isEmpty),
      );
      if (!causaIncompleta) _errorDetallesCausa = null;
    }

    if (_errorDetallesAgregar == null) return;

    if (total == 0) return;

    if (_errorDetallesAgregar == 'Agregue al menos un detalle de aves') {
      _errorDetallesAgregar = null;
      return;
    }

    if (_errorDetallesAgregar == 'Complete la causa en todos los detalles' &&
        needsCausa) {
      final causaIncompleta = _detalles.any(
        (d) =>
            d.cantidad > 0 &&
            (d.causaCodigo == null || d.causaCodigo!.isEmpty),
      );
      if (!causaIncompleta) _errorDetallesAgregar = null;
    }
  }

  void _loadCatalogs() {
    final storage = context.read<StorageService>();
    _cencos = storage.getCencosWithEdadActual()
      ..sort((a, b) => a.codigo.compareTo(b.codigo));
    _motivos = storage
        .getMotivosMortalidad()
        .map((e) => MotivoMortalidad.fromJson(e))
        .toList();

    if (widget.existingRecord != null) {
      final cencoCode = widget.existingRecord!['cenco_codigo']?.toString() ?? '';
      _selectedCenco = _cencos.cast<Cenco?>().firstWhere(
            (c) => c?.codigo == cencoCode,
            orElse: () => null,
          );
      if (_selectedCenco != null) {
        _loadGalpones(_selectedCenco!.codigo);
        final galponCode = widget.existingRecord!['galpon']?.toString() ?? '';
        _selectedGalpon = _galpones.cast<Galpon?>().firstWhere(
              (g) => g?.tcodint == galponCode,
              orElse: () => null,
            );
      }
    } else {
      // Auto-seleccionar granja por defecto si está configurada
      final defaultGranja = storage.getDefaultGranja();
      if (defaultGranja != null && defaultGranja.isNotEmpty) {
        _selectedCenco = _cencos.cast<Cenco?>().firstWhere(
              (c) => c?.granjaCodigo == defaultGranja,
              orElse: () => null,
            );
        if (_selectedCenco != null) {
          _loadGalpones(_selectedCenco!.codigo);
        }
      }
    }
    setState(() {});
  }

  void _loadGalpones(String cencoCode) {
    final storage = context.read<StorageService>();
    final raw = storage.getGalponesPorCenco(cencoCode);
    _galpones = raw.map((e) => Galpon.fromJson(e)).toList();
  }

  Future<void> _loadCantidadPollos() async {
    final cenco = _selectedCenco;
    final galpon = _selectedGalpon;
    if (cenco == null || galpon == null) return;

    final fechaStr = DateFormat('yyyy-MM-dd').format(_fecha);

    // Intentar desde cache primero
    final storage = context.read<StorageService>();
    final cached = storage.getCantidadPollosPorGalpon(cenco.codigo, galpon.tcodint);
    if (cached.isNotEmpty) {
      setState(() {
        _cantidadPollos = cached;
      });
    }

    // Refrescar desde API
    try {
      final res = await _apiService.downloadCantidadPollos(
        tcencos: cenco.codigo,
        fecha: fechaStr,
        galpon: galpon.tcodint,
      );
      if (res['success'] == true && mounted) {
        final items = (res['items'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final allCache = storage.getCantidadPollos();
        allCache['${cenco.codigo}_${galpon.tcodint}_$fechaStr'] = items;
        allCache['${cenco.codigo}_${galpon.tcodint}'] = items;
        await storage.saveCantidadPollos(allCache);
        setState(() {
          _cantidadPollos = items;
        });
      }
    } catch (_) {}
  }

  bool get _useInlineAvesEntry {
    if (widget.type == MortalityType.incubacion) return true;
    if (widget.type == MortalityType.transporte) return true;
    if (widget.type == MortalityType.produccion) {
      final o = _origenAnalisis;
      return o == 'Necropsia' || o == 'Laboratorio';
    }
    return false;
  }

  double get _progress {
    var steps = 0.0;
    steps += 0.2;
    if (_selectedCenco != null) steps += 0.2;
    if (_selectedGalpon != null) steps += 0.15;
    if (_sinMortalidad || _detalles.any((d) => d.hasContent)) steps += 0.25;
    if (_obsController.text.isNotEmpty) steps += 0.2;
    return steps.clamp(0, 1);
  }

  Future<bool> _onWillPop() async {
    if (!_dirty) return true;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkCard : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('¿Descartar cambios?'),
        content: const Text('Hay cambios sin guardar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Descartar')),
        ],
      ),
    );
    return result ?? false;
  }

  /// Tipos/orígenes que admiten registro sin mortalidad.
  bool get _permiteRegistroCero {
    if (widget.type == MortalityType.produccion) {
      final o = (_origenAnalisis ?? '').trim();
      if (o == 'Necropsia' || o == 'Laboratorio') return false;
    }
    return true;
  }

  /// Registro marcado explícitamente como sin mortalidad.
  bool get _esRegistroCero => _permiteRegistroCero && _sinMortalidad;

  void _setSinMortalidad(bool value) {
    if (!_permiteRegistroCero && value) return;
    setState(() {
      _sinMortalidad = value;
      _dirty = true;
      if (value) {
        final kept = _detalles
            .map((d) => d.copyWith(cantidad: 0, procesoEtapas: const {}))
            .where((d) => d.hasContent)
            .toList();
        _detalles
          ..clear()
          ..addAll(kept);
        _errorDetallesCantidad = null;
        _errorDetallesCausa = null;
        _errorDetallesAgregar = null;
      }
    });
  }

  bool _validate() {
    _errorGranja = _selectedCenco == null ? 'Seleccione granja' : null;
    _errorGalpon = _selectedGalpon == null ? 'Seleccione galpón' : null;
    _errorFechaLlegada = widget.type == MortalityType.incubacion && _fechaLlegada == null
        ? 'Seleccione fecha de llegada'
        : null;
    _errorDetallesCantidad = null;
    _errorDetallesCausa = null;
    _errorDetallesAgregar = null;

    final totalAves = MortalityDetail.totalMachos(_detalles) +
        MortalityDetail.totalHembras(_detalles);

    if (!_esRegistroCero &&
        (_detalles.isEmpty || totalAves == 0)) {
      if (_useInlineAvesEntry) {
        _errorDetallesCantidad = 'Ingrese cantidad en Machos o Hembras';
      } else {
        _errorDetallesAgregar = 'Agregue al menos un detalle de aves';
      }
    } else if (!_esRegistroCero &&
        mortalityShowsCausa(widget.type, origenAnalisis: _origenAnalisis)) {
      for (final d in _detalles) {
        if (d.cantidad > 0 &&
            (d.causaCodigo == null || d.causaCodigo!.isEmpty)) {
          if (_useInlineAvesEntry) {
            _errorDetallesCausa = 'Seleccione la causa de mortalidad';
          } else {
            _errorDetallesAgregar = 'Complete la causa en todos los detalles';
          }
          break;
        }
      }
    }

    if (widget.type == MortalityType.transporte && _subtipoTransporte == null) {
      showErrorToast(context, 'Seleccione subtipo de transporte');
      return false;
    }

    if (widget.type == MortalityType.produccion && _origenAnalisis == null) {
      showErrorToast(context, 'Seleccione origen del análisis');
      return false;
    }

    setState(() {});
    final valid = _errorGranja == null &&
        _errorGalpon == null &&
        _errorFechaLlegada == null &&
        _errorDetallesCantidad == null &&
        _errorDetallesCausa == null &&
        _errorDetallesAgregar == null;
    if (!valid) _scrollToValidationError();
    return valid;
  }

  void _scrollToValidationError() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final keys = <GlobalKey>[
        if (_errorFechaLlegada != null) _keyFechaLlegada,
        if (_errorGranja != null) _keyGranja,
        if (_errorGalpon != null) _keyGalpon,
        if (_errorDetallesCantidad != null ||
            _errorDetallesCausa != null ||
            _errorDetallesAgregar != null)
          _keyDetalles,
      ];

      for (final key in keys) {
        final target = key.currentContext;
        if (target == null) continue;
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOut,
          alignment: 0.12,
        );
        break;
      }
    });
  }

  List<MortalityDetail> get _detallesParaGuardar {
    var conContenido = _detalles.where((d) => d.hasContent).toList();
    if (_esRegistroCero) {
      conContenido = conContenido
          .map((d) => d.copyWith(cantidad: 0, procesoEtapas: const {}))
          .where((d) => d.hasContent)
          .toList();
    }
    if (widget.type != MortalityType.transporte) return conContenido;
    final c = mortalityCausaTransporte(_motivos);
    return conContenido
        .map((d) => d.cantidad > 0
            ? d.copyWith(causaCodigo: c.codigo, causaNombre: c.nombre)
            : d)
        .toList();
  }

  Map<String, dynamic> _collectFormData() {
    final cenco = _selectedCenco!;
    _tuuid ??= const Uuid().v4();

    final detalles = _detallesParaGuardar;
    final cantMachos = MortalityDetail.totalMachos(detalles);
    final cantHembras = MortalityDetail.totalHembras(detalles);
    MortalityDetail? primeraM;
    MortalityDetail? primeraH;
    for (final d in detalles) {
      if (d.isMacho && primeraM == null) primeraM = d;
      if (d.isHembra && primeraH == null) primeraH = d;
    }
    final allFotos = MortalityDetail.allPhotoPaths(detalles);

    return {
      'tuuid': _tuuid,
      'tipo_mortalidad': widget.type.id,
      'subtipo_transporte': _subtipoTransporte,
      'origen_analisis': _origenAnalisis,
      'fecha': DateFormat('yyyy-MM-dd').format(_fecha),
      if (widget.type == MortalityType.incubacion)
        'fecha_llegada': _fechaLlegada != null
            ? DateFormat('yyyy-MM-dd').format(_fechaLlegada!)
            : '',
      'granja': cenco.granjaCodigo,
      'granja_nombre': cenco.nombre,
      'campania': cenco.campaniaCodigo,
      'cenco_codigo': cenco.codigo,
      'galpon': _selectedGalpon!.tcodint,
      'detalles': detalles.map((d) => d.toJson()).toList(),
      'cant_machos': cantMachos,
      'causa_machos': primeraM?.causaCodigo ?? '',
      'causa_machos_nombre': primeraM?.causaNombre ?? '',
      'cant_hembras': cantHembras,
      'causa_hembras': primeraH?.causaCodigo ?? '',
      'causa_hembras_nombre': primeraH?.causaNombre ?? '',
      'observaciones': capitalizeText(_obsController.text),
      'fotos': allFotos
          .map((p) => {'path': p, 'nombre': p.split(Platform.pathSeparator).last})
          .toList(),
    };
  }

  Future<void> _openDetailDialogForAdd() async {
    final result = await showMortalityDetailDialog(
      context: context,
      type: widget.type,
      motivos: _motivos,
      sinMortalidad: _sinMortalidad,
    );
    if (result == null || !mounted) return;
    if (result.isEmpty) return;
    setState(() {
      _detalles.addAll(result);
      _dirty = true;
      _reconcileDetailErrors();
    });
  }

  Future<void> _openDetailDialogForEditGroup(MortalityDetailGroup group) async {
    final result = await showMortalityDetailDialog(
      context: context,
      type: widget.type,
      motivos: _motivos,
      existingMacho: group.macho,
      existingHembra: group.hembra,
      sinMortalidad: _sinMortalidad,
    );
    if (result == null || !mounted) return;
    setState(() {
      _detalles.removeWhere(
        (d) => (d.grupoId ?? d.id) == group.grupoId,
      );
      _detalles.addAll(result);
      _dirty = true;
      _reconcileDetailErrors();
    });
  }

  void _deleteDetailGroup(String grupoId) {
    setState(() {
      _detalles.removeWhere((d) => (d.grupoId ?? d.id) == grupoId);
      _dirty = true;
    });
  }

  Future<void> _onSavePressed() async {
    FocusScope.of(context).unfocus();
    if (!_validate()) return;

    final preview = _collectFormData();
    final confirmed = await MortalitySummarySheet.show(
      context: context,
      type: widget.type,
      data: preview,
      isEditing: widget.isEditing,
    );
    if (confirmed != true || !mounted) return;

    await _confirmSave(preview);
  }

  Future<bool> _checkInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    }
  }

  void _mergeUploadResponse(Map<String, dynamic> data, Map<String, dynamic> result) {
    final respData = result['data'];
    if (respData is! Map) return;
    final registros = respData['registros'];
    if (registros is! List || registros.isEmpty) return;
    final first = registros.first;
    if (first is! Map) return;
    for (final key in ['doc', 'serie', 'numero', 'codigo', 'id']) {
      if (first[key] != null) {
        data[key] = first[key];
      }
    }
  }

  Future<void> _persistRecord(
    StorageService storage,
    Map<String, dynamic> data, {
    required bool synced,
  }) async {
    data['synced'] = synced;
    data['guardado_backend'] = synced
        ? true
        : widget.existingRecord?['guardado_backend'] == true;

    if (widget.isEditing) {
      await storage.updateRecord(AppStrings.formTypeMortalidad, data);
    } else {
      await storage.saveForm(AppStrings.formTypeMortalidad, data);
    }

    if (synced) {
      await storage.setLastSyncDate();
    }
  }

  Future<void> _confirmSave(Map<String, dynamic> preview) async {
    setState(() => _saving = true);
    void Function()? closeDialog;
    try {
      final storage = context.read<StorageService>();
      final now = DateTime.now();
      final data = Map<String, dynamic>.from(preview);
      data['tdate_trans'] = DateFormat('yyyy-MM-dd').format(now);
      data['ttime_trans'] = DateFormat('HH:mm:ss').format(now);
      data['usuario'] = storage.getUserCodeSync() ?? '';
      data['tidandroid'] = storage.getDeviceIdSync() ?? '';

      final hasInternet = await _checkInternet();

      if (hasInternet) {
        closeDialog = showChickenLoadingDialog(context, 'Guardando registro...');
        final result = await _apiService.uploadMortalidadMovil(record: data);
        print('[MORTALIDAD_UPLOAD] ${jsonEncode(result)}');
        closeDialog();
        closeDialog = null;

        if (!mounted) return;

        if (result['success'] == true) {
          _mergeUploadResponse(data, result);
          await _persistRecord(storage, data, synced: true);
          if (!mounted) return;
          showSuccessToast(context, AppStrings.guardadoExitoso);
          Get.back();
          return;
        }

        await _persistRecord(storage, data, synced: false);
        if (!mounted) return;
        showWarningToast(
          context,
          AppStrings.guardadoLocal,
          duration: const Duration(seconds: 5),
        );
        Get.back();
        return;
      }

      await _persistRecord(storage, data, synced: false);
      if (!mounted) return;
      showWarningToast(
        context,
        AppStrings.guardadoLocal,
        duration: const Duration(seconds: 5),
      );
      Get.back();
    } catch (e) {
      if (mounted) showErrorToast(context, 'Error al guardar el registro.');
    } finally {
      closeDialog?.call();
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _storage?.removeListener(_onCatalogsChanged);
    _obsController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildSinMortalidadSwitch(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Material(
        color: isDark ? AppColors.darkSurface : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _setSinMortalidad(!_sinMortalidad),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _sinMortalidad
                    ? AppColors.primary.withValues(alpha: 0.45)
                    : AppColors.primary.withValues(alpha: 0.12),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            child: Row(
              children: [
                Icon(
                  Icons.health_and_safety_outlined,
                  size: 20,
                  color: _sinMortalidad
                      ? AppColors.primary
                      : (isDark ? Colors.white54 : AppColors.textSecondary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sin mortalidad',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: isDark ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Marca si no hubo aves muertas',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark
                              ? Colors.white54
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _sinMortalidad,
                  activeColor: AppColors.primary,
                  onChanged: _setSinMortalidad,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _onWillPop() && mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: buildAppBar(
          context,
          widget.type.title,
          showBackButton: true,
          appIcon: widget.type.icon,
          rightIcon: Icons.save,
          rightIconColor: AppColors.iconAccent,
          rightIconLoading: _saving,
          onRightIconPressed: _onSavePressed,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(
              value: _progress,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
          children: [
            if (widget.isEditing)
              Container(
                width: double.infinity,
                color: AppColors.warning.withValues(alpha: 0.2),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: const Text(
                  '✏️ Editando registro',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                          if (widget.type == MortalityType.incubacion)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: StyledSelectField(
                                    label: 'F. Registro',
                                    value: DateFormat('dd/MM/yyyy').format(_fecha),
                                    placeholder: 'Seleccionar',
                                    icon: Icons.calendar_today_rounded,
                                    compact: true,
                                    onTap: () => _pickDate(
                                      initial: _fecha,
                                      onPicked: (d) => _fecha = d,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: KeyedSubtree(
                                    key: _keyFechaLlegada,
                                    child: StyledSelectField(
                                      label: 'F. Llegada',
                                      value: _fechaLlegada != null
                                          ? DateFormat('dd/MM/yyyy').format(_fechaLlegada!)
                                          : null,
                                      placeholder: 'Seleccionar',
                                      icon: Icons.calendar_today_rounded,
                                      compact: true,
                                      errorText: _errorFechaLlegada,
                                      onTap: () => _pickDate(
                                        initial: _fechaLlegada ?? _fecha,
                                        onPicked: (d) => _fechaLlegada = d,
                                        onAfterPick: () => _errorFechaLlegada = null,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            StyledSelectField(
                              label: 'Fecha',
                              value: DateFormat('dd/MM/yyyy').format(_fecha),
                              placeholder: 'Seleccionar',
                              icon: Icons.calendar_today_rounded,
                              compact: true,
                              onTap: () => _pickDate(
                                initial: _fecha,
                                onPicked: (d) => _fecha = d,
                                onAfterPick: () {
                                  if (widget.type == MortalityType.produccion ||
                                      widget.type == MortalityType.despacho) {
                                    _loadCantidadPollos();
                                  }
                                },
                              ),
                            ),
                          const SizedBox(height: 10),
                          KeyedSubtree(
                            key: _keyGranja,
                            child: StyledSelectField(
                            label: 'Granja / Campaña',
                            value: _selectedCenco?.labelMortality,
                            placeholder: 'Seleccionar granja...',
                            icon: Icons.home_work_outlined,
                            errorText: _errorGranja,
                            onTap: () async {
                              if (_cencos.isEmpty) {
                                showInfoToast(
                                  context,
                                  'No hay granjas disponibles. Descargue desde el menú.',
                                );
                                return;
                              }
                              await showSearchableSelectDialog<Cenco>(
                                context: context,
                                title: 'Seleccionar granja',
                                icon: Icons.home_work_outlined,
                                items: _cencos,
                                getLabel: (c) => c.labelMortality,
                                showSubtitle: true,
                                getSubtitle: (c) => c.subtitleAge,
                                selectedValue: _selectedCenco?.codigo,
                                getValue: (c) => c.codigo,
                                onSelected: (code) {
                                  if (code == null) return;
                                  final found = _cencos.firstWhere((c) => c.codigo == code);
                                  setState(() {
                                    _selectedCenco = found;
                                    _selectedGalpon = null;
                                    _loadGalpones(found.codigo);
                                    _errorGranja = null;
                                    _dirty = true;
                                  });
                                },
                              );
                            },
                          ),
                          ),
                          const SizedBox(height: 10),
                          KeyedSubtree(
                            key: _keyGalpon,
                            child: StyledSelectField(
                            label: 'Galpón',
                            value: _selectedGalpon?.tcodint,
                            placeholder: _selectedCenco == null
                                ? 'Seleccione primero una granja'
                                : 'Seleccionar galpón...',
                            icon: Icons.warehouse_outlined,
                            errorText: _errorGalpon,
                            enabled: _selectedCenco != null,
                            onTap: () async {
                              if (_selectedCenco == null) return;
                              if (_galpones.isEmpty) {
                                showInfoToast(context, 'No hay galpones para esta granja.');
                                return;
                              }
                              await showSearchableSelectDialog<Galpon>(
                                context: context,
                                title: 'Seleccionar galpón',
                                icon: Icons.warehouse_outlined,
                                items: _galpones,
                                getLabel: (g) => g.tcodint,
                                selectedValue: _selectedGalpon?.tcodint,
                                getValue: (g) => g.tcodint,
                                onSelected: (code) {
                                  if (code == null) return;
                                  final found =
                                      _galpones.firstWhere((g) => g.tcodint == code);
                                  setState(() {
                                    _selectedGalpon = found;
                                    _errorGalpon = null;
                                    _dirty = true;
                                  });
                                  if (widget.type == MortalityType.produccion ||
                                      widget.type == MortalityType.despacho) {
                                    _loadCantidadPollos();
                                  }
                                },
                              );
                            },
                          ),
                          ),
                          if ((widget.type == MortalityType.produccion ||
                                  widget.type == MortalityType.despacho) &&
                              _cantidadPollos.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6, bottom: 2),
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'Stock de aves  ',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: context.mutedTextColor,
                                      ),
                                    ),
                                    ..._cantidadPollos.map((item) {
                                      final codigo = item['tcodigo']?.toString() ?? '';
                                      final cant = item['cantidad'] ?? 0;
                                      final sexo = codigo.contains('1001') ? 'M' : 'H';
                                      final sep = _cantidadPollos.indexOf(item) ==
                                                  _cantidadPollos.length - 1
                                          ? ''
                                          : '  ';
                                      return TextSpan(
                                        text: '$sexo: $cant$sep',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: widget.type.accentColor,
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            ),
                          KeyedSubtree(
                            key: _keyDetalles,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FormSectionTitle(
                                  title: 'Detalle de aves',
                                  leading: PoultryIcon(
                                    size: 18,
                                    color: widget.type.accentColor,
                                  ),
                                  color: widget.type.accentColor,
                                  topPadding: 0,
                                  bottomPadding: 0,
                                ),
                                if (_permiteRegistroCero)
                                  _buildSinMortalidadSwitch(isDark),
                                if (_useInlineAvesEntry)
                                  InlineMortalitySection(
                                    key: ValueKey('${_tuuid ?? 'new'}_${_origenAnalisis ?? ''}'),
                                    initialDetalles: List.from(_detalles),
                                    cantidadError: _errorDetallesCantidad,
                                    causaError: _errorDetallesCausa,
                                    showCausa: mortalityShowsCausa(
                                      widget.type,
                                      origenAnalisis: _origenAnalisis,
                                    ),
                                    motivos: _motivos,
                                    tabAccentColor: widget.type.accentColor,
                                    sinMortalidad: _sinMortalidad,
                                    onChanged: (detalles) {
                                      setState(() {
                                        _detalles
                                          ..clear()
                                          ..addAll(detalles);
                                        _dirty = true;
                                        _reconcileDetailErrors();
                                      });
                                    },
                                  )
                                else
                                  MortalityDetailsSection(
                                    detalles: _detalles,
                                    type: widget.type,
                                    permiteRegistroCero: _permiteRegistroCero,
                                    sinMortalidad: _sinMortalidad,
                                    agregarError: _errorDetallesAgregar,
                                    onAdd: _openDetailDialogForAdd,
                                    onEditGroup: _openDetailDialogForEditGroup,
                                    onDeleteGroup: _deleteDetailGroup,
                                  ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Divider(
                              height: 1,
                              color: AppColors.primary.withValues(alpha: 0.12),
                            ),
                          ),
                          FormSectionTitle(
                            title: 'Observaciones',
                            icon: Icons.notes_rounded,
                            color: widget.type.accentColor,
                          ),
                          TextField(
                            controller: _obsController,
                            maxLines: 3,
                            maxLength: 500,
                            textCapitalization: TextCapitalization.sentences,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: 15,
                            ),
                            decoration: AppInputStyles.decoration(
                              context,
                              r: 12,
                              labelText: 'Observaciones',
                              hintText: 'Notas u observaciones adicionales...',
                              accentBorder: true,
                              hintStyle: TextStyle(
                                color: isDark ? Colors.white54 : Colors.grey.shade400,
                              ),
                            ),
                          ),
                  ],
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
