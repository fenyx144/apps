import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/cenco.dart';
import '../models/galpon.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/theme_extensions.dart';
import '../utils/toast_helper.dart';
import '../widgets/app_bar.dart';
import '../widgets/app_drawer.dart';
import '../widgets/searchable_select_dialog.dart';
import '../widgets/styled_select_field.dart';

// Color de acento para liquidacion (azul, reemplaza el morado)
const Color _accentColor = Color(0xFF1565C0);

// Anchos fijos para cada columna (para scroll horizontal sincronizado)
const double _colFecha = 75;
const double _colGranja = 160;
const double _colNum = 42;
const double _colExpand = 36;
const double _colSpacing = 4;

class LiquidacionReportScreen extends StatefulWidget {
  const LiquidacionReportScreen({super.key});

  @override
  State<LiquidacionReportScreen> createState() => _LiquidacionReportScreenState();
}

class _LiquidacionReportScreenState extends State<LiquidacionReportScreen> {
  final _apiService = ApiService();

  Cenco? _selectedCenco;
  String _galponFilter = '__todos__';

  List<Cenco> _cencos = [];
  List<Galpon> _galpones = [];
  bool _loadingCencos = false;

  List<Map<String, dynamic>> _liquidaciones = [];
  bool _loading = false;
  String? _error;
  final Set<int> _expandedRows = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadCatalogs();
      await _cargar();
    });
  }

  Future<bool> _checkInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    }
  }

  Future<void> _loadCatalogs() async {
    setState(() => _loadingCencos = true);
    final storage = context.read<StorageService>();

    // Cache-first: mostrar datos locales inmediatamente
    _poblarCencosDesdeCache(storage, autoSelectDefault: true);

    // Refrescar desde API en background (solo si hay internet)
    if (await _checkInternet()) {
      final res = await _apiService.downloadCencosGalpones(
        fecha: DateFormat('yyyy-MM-dd').format(DateTime.now()),
      );
      if (res['success'] == true) {
        final cencos = res['cencos'] as List? ?? [];
        final galponesPorCenco =
            res['galponesPorCenco'] as Map<String, List<dynamic>>? ?? {};
        await storage.saveCencosGalpones(
          cencos: cencos
              .map((c) => {
                    'codigo': c.codigo,
                    'nombre': c.nombre,
                    'edad': c.edad,
                    'fec_ing_min': c.fecIngMin ?? '',
                  })
              .toList(),
          galponesPorCenco: galponesPorCenco.map(
            (k, v) => MapEntry(
              k,
              v
                  .map((g) => {
                        'tcodint': g.tcodint,
                        'fec_ing_min': g.fecIngMin ?? '',
                      })
                  .toList(),
            ),
          ),
        );
        // Re-poblar con datos frescos
        _poblarCencosDesdeCache(storage);
      }
    }
  }

  void _poblarCencosDesdeCache(StorageService storage, {bool autoSelectDefault = false}) {
    if (!mounted) return;
    final raw = storage.getCencosLocal();
    debugPrint('[CENCOS_LOAD] liquidacion_screen: getCencosLocal().length=${raw.length}');
    setState(() {
      _cencos = raw
          .map((e) => Cenco.fromJson(e))
          .where((c) => c.codigo.isNotEmpty)
          .toList()
        ..sort((a, b) => a.codigo.compareTo(b.codigo));
      debugPrint('[CENCOS_LOAD] liquidacion_screen: _cencos.length=${_cencos.length}');
      // Auto-seleccionar granja por defecto si esta configurada
      if (autoSelectDefault && _selectedCenco == null) {
        final defaultGranja = storage.getDefaultGranja();
        if (defaultGranja != null && defaultGranja.isNotEmpty) {
          _selectedCenco = _cencos.cast<Cenco?>().firstWhere(
                (c) => c?.granjaCodigo == defaultGranja,
                orElse: () => null,
              );
        }
      } else {
        _selectedCenco = _cencos
            .where((c) => c.codigo == _selectedCenco?.codigo)
            .firstOrNull;
      }
      _refreshGalpones();
      _loadingCencos = false;
    });
  }

  void _refreshGalpones() {
    if (_selectedCenco == null) {
      _galpones = [];
      return;
    }
    final storage = context.read<StorageService>();
    _galpones = storage
        .getGalponesPorCenco(_selectedCenco!.codigo)
        .map((e) => Galpon.fromJson(e))
        .where((g) => g.tcodint.isNotEmpty)
        .toList();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final storage = context.read<StorageService>();

    // Cache-first: mostrar datos locales inmediatamente
    final cached = storage.getBloquesLiquidacion();
    if (cached.isNotEmpty) {
      _poblarLiquidaciones(cached, storage);
    }

    // Refrescar desde API en background (solo si hay internet)
    if (await _checkInternet()) {
      try {
        final apiRes = await _apiService.listarBloquesLiquidacion(
        granjaCodigo: _selectedCenco?.granjaCodigo,
        campaniaCodigo: _selectedCenco?.campaniaCodigo,
        galponCodigo: _galponFilter == '__todos__' ? null : _galponFilter,
      );

      if (apiRes['success'] == true) {
        final data = apiRes['data'];
        final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
        final raw = map['bloques'];
        var list = <Map<String, dynamic>>[];
        if (raw is List) {
          for (final item in raw) {
            if (item is! Map) continue;
            list.add(Map<String, dynamic>.from(item));
          }
        }
        // Depuración: mostrar datos del primer bloque
        if (list.isNotEmpty) {
          final first = list.first;
          debugPrint('[LIQUIDACION_DEBUG] granja_nombre=${first['granja_nombre']} granja=${first['granja']}');
          debugPrint('[LIQUIDACION_DEBUG] grupos_keys=${first['_debug_grupo_keys']}');
          debugPrint('[LIQUIDACION_DEBUG] uuidGranjaMap_keys_count=${(first['_debug_uuidGranjaMap_keys'] as List?)?.length ?? 0}');
          debugPrint('[LIQUIDACION_DEBUG] allUuidList_count=${first['_debug_allUuidList_count']}');
          final grupos = (first['grupos'] as List?) ?? [];
          if (grupos.isNotEmpty && grupos.first is Map) {
            final g = grupos.first as Map;
            debugPrint('[LIQUIDACION_DEBUG] grupo[0] keys=${g.keys.join(',')}');
            debugPrint('[LIQUIDACION_DEBUG] grupo[0] granja=${g['granja']} granja_nombre=${g['granja_nombre']}');
          }
        }
        // Filtrar segun permiso verLiquidacionTodos
        final permisos = storage.getPermisos();
        final verTodos = permisos['verLiquidacionTodos'] == true;
        final usuarioActual = storage.getUserCodeSync() ?? '';
        if (!verTodos && usuarioActual.isNotEmpty) {
          list = list.where((b) {
            return b['usuario']?.toString().trim().toLowerCase() == usuarioActual.toLowerCase();
          }).toList();
        }
        // Guardar en cache offline
        await storage.saveBloquesLiquidacion(list);
        _poblarLiquidaciones(list, storage);
      }
      // Si API falla, se mantienen los datos del cache cargados al inicio
    } catch (e) {
      debugPrint('[LIQUIDACION_CARGAR_ERROR] $e');
      if (_liquidaciones.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Sin conexi\u00f3n. No hay datos locales disponibles.';
        });
      }
    }
    }

    if (_error != null && _liquidaciones.isEmpty && mounted) {
      showWarningToast(context, _error!, duration: const Duration(seconds: 4));
    }
  }

  void _poblarLiquidaciones(List<Map<String, dynamic>> bloques, StorageService storage) {
    // Filtrar por granja seleccionada si corresponde
    final granjaCodigo = _selectedCenco?.granjaCodigo;
    var filtered = bloques;
    if (granjaCodigo != null && granjaCodigo.isNotEmpty) {
      filtered = filtered.where((b) {
        final bg = b['granja']?.toString() ?? '';
        final bgn = b['granja_nombre']?.toString() ?? '';
        return bg.startsWith(granjaCodigo) || bgn.startsWith(granjaCodigo);
      }).toList();
    }
    // Filtrar por galpon si corresponde
    if (_galponFilter != '__todos__' && _galponFilter.isNotEmpty) {
      filtered = filtered.where((b) {
        final bg = b['galpon']?.toString() ?? '';
        return bg == _galponFilter;
      }).toList();
    }
    if (!mounted) return;
    setState(() {
      _liquidaciones = filtered;
      _loading = false;
      _error = null;
    });
  }

  // ─── Selectores ───
  Future<void> _pickCenco() async {
    if (_cencos.isEmpty) {
      showInfoToast(context, 'No hay granjas disponibles. Descargue desde el menu.');
      return;
    }

    final opciones = <({String id, String label})>[
      (id: '__todas__', label: 'Todas las granjas'),
      for (final c in _cencos) (id: c.codigo, label: c.labelFilter),
    ];

    await showSearchableSelectDialog<({String id, String label})>(
      context: context,
      title: 'Granja / Campania',
      icon: Icons.home_work_outlined,
      items: opciones,
      getLabel: (o) => o.label,
      showSubtitle: false,
      selectedValue: _selectedCenco?.codigo ?? '__todas__',
      getValue: (o) => o.id,
      onSelected: (id) {
        if (id == null) return;
        setState(() {
          if (id == '__todas__') {
            _selectedCenco = null;
            _galponFilter = '__todos__';
          } else {
            final found = _cencos.where((c) => c.codigo == id).firstOrNull;
            _selectedCenco = found;
            _galponFilter = '__todos__';
            _refreshGalpones();
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
      selectedValue: _galponFilter,
      getValue: (o) => o.id,
      onSelected: (id) {
        if (id == null) return;
        setState(() => _galponFilter = id);
        _cargar();
      },
      emptyMessage: 'Sin galpones para esta granja',
    );
  }

  String? get _galponLabel {
    if (_selectedCenco == null) return null;
    if (_galponFilter == '__todos__') return 'Todos los galpones';
    return _galponFilter;
  }

  // ─── Totals ───
  int get _totalLiquidaciones => _liquidaciones.length;
  int get _totalAves => _liquidaciones.fold<int>(
      0, (s, b) => s + (int.tryParse(b['total_aves']?.toString() ?? '0') ?? 0));

  ({int machos, int hembras, int aves, int regs}) _itemTotals(Map<String, dynamic> item) {
    final grupos = (item['grupos'] as List?) ?? [];
    int m = 0, h = 0;
    for (final g in grupos) {
      final gMap = g is Map ? Map<String, dynamic>.from(g) : <String, dynamic>{};
      m += int.tryParse(gMap['cantMachos']?.toString() ?? '0') ?? 0;
      h += int.tryParse(gMap['cantHembras']?.toString() ?? '0') ?? 0;
    }
    return (
      machos: m,
      hembras: h,
      aves: int.tryParse(item['total_aves']?.toString() ?? '0') ?? 0,
      regs: int.tryParse(item['total_registros']?.toString() ?? '0') ?? 0,
    );
  }

  String _fmtFecha(String? raw) {
    if (raw == null || raw.isEmpty) return '---';
    try {
      final parts = raw.split('-');
      if (parts.length == 3) {
        return '${parts[2]}/${parts[1]}/${parts[0].substring(2)}';
      }
    } catch (_) {}
    return raw;
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: buildAppBar(
        context,
        AppStrings.reporteLiquidacionTitle,
        appIcon: Icons.receipt_long_rounded,
      ),
      drawer: const AppDrawer(),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadCatalogs();
            await _cargar();
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildFiltersCard(context)),
              if (!_loading && _liquidaciones.isNotEmpty)
                SliverToBoxAdapter(child: _buildSummaryRow(context)),
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_liquidaciones.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(context),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header - mismo estilo que auditoria
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(width: _colFecha, child: _th('Fecha', center: true)),
                                const SizedBox(width: _colSpacing),
                                SizedBox(width: _colGranja, child: _th('Granja')),
                                const SizedBox(width: _colSpacing),
                                SizedBox(width: _colNum, child: _th('Tot', center: true)),
                                const SizedBox(width: _colSpacing),
                                SizedBox(width: _colExpand, child: const SizedBox.shrink()),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Rows
                          ..._liquidaciones.asMap().entries.map(
                            (e) => Padding(
                              padding: EdgeInsets.only(top: e.key > 0 ? 4 : 0),
                              child: _buildRow(context, e.value, isDark, e.key),
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Total
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: _colFecha + _colSpacing + _colGranja,
                                  child: Text('TOTALES',
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                                          color: isDark ? Colors.white : AppColors.textPrimary)),
                                ),
                                const SizedBox(width: _colSpacing),
                                SizedBox(
                                  width: _colNum,
                                  child: Text('$_totalAves',
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                                      textAlign: TextAlign.center),
                                ),
                                const SizedBox(width: _colSpacing),
                                const SizedBox(width: _colExpand),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _th(String text, {bool center = false}) {
    return Text(text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
        textAlign: center ? TextAlign.center : TextAlign.start);
  }

  Widget _buildRow(BuildContext context, Map<String, dynamic> item, bool isDark, int index) {
    final fecha = _fmtFecha(item['fecha']?.toString());
    final usuario = item['usuario']?.toString() ?? '---';
    // Resolver granja: primero intentar desde cencos usando codigo raw
    String granja = '';
    final rawGranja = (item['granja']?.toString() ?? '').trim();
    if (rawGranja.isNotEmpty) {
      granja = _resolveGranjaFromCencos(rawGranja);
    }
    // Si no se resolvio, usar granja_nombre (aunque sea codigo raw)
    if (granja.isEmpty) {
      granja = (item['granja_nombre']?.toString() ?? '').trim();
    }
    // Fallback: buscar en los grupos del JSON
    if (granja.isEmpty) {
      final grupos = (item['grupos'] as List?) ?? [];
      for (final g in grupos) {
        if (g is! Map) continue;
        final gNombre = g['granja_nombre']?.toString() ?? '';
        if (gNombre.trim().isNotEmpty) {
          granja = gNombre.trim();
          break;
        }
        final gGranja = g['granja']?.toString() ?? '';
        if (gGranja.trim().isNotEmpty) {
          granja = _resolveGranjaFromCencos(gGranja.trim());
          if (granja.isNotEmpty) break;
        }
      }
    }
    if (granja.isEmpty) granja = '---';
    final t = _itemTotals(item);
    final totalGrupos = (item['grupos'] as List?)?.length ?? 0;
    final isExpanded = _expandedRows.contains(index);
    final grupos = (item['grupos'] as List?) ?? [];
    final fechaHora = item['fecha_hora_registro']?.toString() ?? '';

    final totalMachos = grupos.fold<int>(0, (s, g) {
      final gMap = g is Map ? Map<String, dynamic>.from(g) : <String, dynamic>{};
      return s + (int.tryParse(gMap['cantMachos']?.toString() ?? '0') ?? 0);
    });
    final totalHembras = grupos.fold<int>(0, (s, g) {
      final gMap = g is Map ? Map<String, dynamic>.from(g) : <String, dynamic>{};
      return s + (int.tryParse(gMap['cantHembras']?.toString() ?? '0') ?? 0);
    });

    return Padding(
      padding: EdgeInsets.fromLTRB(12, index == 0 ? 0 : 4, 12, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedRows.remove(index);
                } else {
                  _expandedRows.add(index);
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: _colFecha,
                    child: Text(fecha, style: const TextStyle(fontSize: 14), textAlign: TextAlign.center),
                  ),
                  const SizedBox(width: _colSpacing),
                  SizedBox(
                    width: _colGranja,
                    child: Text(granja,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(width: _colSpacing),
                  SizedBox(
                    width: _colNum,
                    child: Text('${t.aves}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center),
                  ),
                  const SizedBox(width: _colSpacing),
                  SizedBox(
                    width: _colExpand,
                    child: totalGrupos > 0
                          ? IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: AnimatedRotation(
                                turns: isExpanded ? 0.5 : 0.0,
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  Icons.expand_more_rounded,
                                  size: 22,
                                  color: isExpanded ? _accentColor : context.mutedTextColor,
                                ),
                              ),
                              onPressed: () {
                                setState(() {
                                  if (isExpanded) {
                                    _expandedRows.remove(index);
                                  } else {
                                    _expandedRows.add(index);
                                  }
                                });
                              },
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: isExpanded
                ? Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurface : _accentColor.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark ? Colors.grey.shade700 : _accentColor.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Granja: $granja',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white70 : AppColors.textPrimary)),
                        const SizedBox(height: 4),
                        Text('Auditor: $usuario',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white70 : AppColors.textSecondary)),
                        const SizedBox(height: 4),
                        Text('Fecha/Hora: ${_fmtFecha(fechaHora.isNotEmpty ? fechaHora.split(' ').first : fecha)}',
                            style: TextStyle(fontSize: 13,
                                color: isDark ? Colors.white60 : AppColors.textSecondary)),
                        if ((item['observaciones'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('Obs: ${item['observaciones']}',
                              style: TextStyle(fontSize: 12,
                                  color: isDark ? Colors.white60 : AppColors.textSecondary)),
                        ],
                        const SizedBox(height: 8),
                        if (grupos.isNotEmpty) ...[
                          const Divider(height: 1),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                            decoration: BoxDecoration(
                              color: _accentColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(width: 150, child: Text('Tipo',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _accentColor))),
                                SizedBox(width: 50, child: Text('M',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _accentColor),
                                    textAlign: TextAlign.center)),
                                SizedBox(width: 50, child: Text('H',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _accentColor),
                                    textAlign: TextAlign.center)),
                                SizedBox(width: 50, child: Text('Tot',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _accentColor),
                                    textAlign: TextAlign.center)),
                              ],
                            ),
                          ),
                          ...grupos.map((g) {
                            final gMap = g is Map ? Map<String, dynamic>.from(g) : <String, dynamic>{};
                            final label = gMap['label']?.toString() ?? gMap['clave']?.toString() ?? '--';
                            final aves = int.tryParse(gMap['totalAves']?.toString() ?? '0') ?? 0;
                            final mMachos = int.tryParse(gMap['cantMachos']?.toString() ?? '0') ?? 0;
                            final mHembras = int.tryParse(gMap['cantHembras']?.toString() ?? '0') ?? 0;
                            return Container(
                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                              margin: const EdgeInsets.only(top: 4),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade200),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(width: 150, child: Text(label,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                                  SizedBox(width: 50, child: Text('$mMachos',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _accentColor),
                                      textAlign: TextAlign.center)),
                                  SizedBox(width: 50, child: Text('$mHembras',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _accentColor),
                                      textAlign: TextAlign.center)),
                                  SizedBox(width: 50, child: Text('$aves',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                      textAlign: TextAlign.center)),
                                ],
                              ),
                            );
                          }),
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                            margin: const EdgeInsets.only(top: 4),
                            decoration: BoxDecoration(
                              color: _accentColor.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: _accentColor.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(width: 150, child: Text('TOTAL',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                                        color: isDark ? Colors.white : AppColors.textPrimary))),
                                SizedBox(width: 50, child: Text('$totalMachos',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _accentColor),
                                    textAlign: TextAlign.center)),
                                SizedBox(width: 50, child: Text('$totalHembras',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _accentColor),
                                    textAlign: TextAlign.center)),
                                SizedBox(width: 50, child: Text('${totalMachos + totalHembras}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                                    textAlign: TextAlign.center)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // ─── Widgets ───
  Widget _buildFiltersCard(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.cardColor,
        border: Border(bottom: BorderSide(color: context.borderColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDarkTheme ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StyledSelectField(
            label: 'Granja / Campania',
            value: _loadingCencos
                ? 'Cargando...'
                : (_selectedCenco?.labelFilter ?? 'Todas las granjas'),
            placeholder: 'Seleccionar granja...',
            icon: Icons.home_work_outlined,
            compact: true,
            enabled: !_loadingCencos,
            onTap: _pickCenco,
          ),
          const SizedBox(height: 8),
          StyledSelectField(
            label: 'Galpon',
            value: _galponLabel,
            placeholder: _selectedCenco == null
                ? 'Seleccione una granja'
                : 'Todos los galpones',
            icon: Icons.warehouse_outlined,
            compact: true,
            enabled: _selectedCenco != null,
            onTap: _pickGalpon,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.cardBackground,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text('$_totalLiquidaciones',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: _accentColor,
                      )),
                  const SizedBox(height: 2),
                  Text('Liquidaciones',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                      )),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.cardBackground,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text('$_totalAves',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: _accentColor,
                      )),
                  const SizedBox(height: 2),
                  Text('Total aves',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                      )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.fact_check_outlined, size: 56,
                color: context.mutedTextColor.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'Sin liquidaciones',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: context.primaryTextColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'No hay auditorias registradas.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.mutedTextColor, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
