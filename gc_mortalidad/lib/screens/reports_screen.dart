import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/mortality_detail.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/mortality_design.dart';
import '../utils/theme_extensions.dart';
import '../widgets/app_bar.dart';
import '../widgets/app_drawer.dart';
import '../widgets/mortality_summary_sheet.dart';
import '../widgets/photo_thumb.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTime? _desde;
  DateTime? _hasta;
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;

  // Filtros por tipo de registro
  static const List<_TipoFiltro> _tipoFiltros = [
    _TipoFiltro('Incubaci\u00f3n', 'incubacion', Icons.egg_outlined),
    _TipoFiltro('Transporte', 'transporte', Icons.local_shipping_outlined),
    _TipoFiltro('Producci\u00f3n', 'produccion', Icons.agriculture_outlined),
    _TipoFiltro('Despacho', 'despacho', Icons.inventory_2_outlined),
    _TipoFiltro('Auditor\u00eda', 'auditoria', Icons.verified_rounded),
  ];

  final Set<String> _activeTipoFilters = {};

  @override
  void initState() {
    super.initState();
    // Rango por defecto: año actual (desde 01/01 hasta hoy)
    final now = DateTime.now();
    _desde = DateTime(now.year, 1, 1);
    _hasta = DateTime(now.year, now.month, now.day);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Extrae nombre de granja desde datos del registro, con fallback a registros anidados
  String _extractGranjaDisplay(Map<String, dynamic> r) {
    final granjaNombre = r['granja_nombre']?.toString() ?? '';
    final granja = r['granja']?.toString() ?? '';
    final campania = r['campania']?.toString() ?? '';
    final galpon = r['galpon']?.toString() ?? '';

    if (granja.isNotEmpty || granjaNombre.isNotEmpty || campania.isNotEmpty) {
      return _ubicacionLinea(
        granja: granja,
        granjaNombre: granjaNombre,
        campania: campania,
        galpon: galpon,
      );
    }

    final detalleRaw = r['registros_detalle'];
    if (detalleRaw is List && detalleRaw.isNotEmpty) {
      final first = detalleRaw.first;
      if (first is Map) {
        return _ubicacionLinea(
          granja: first['granja']?.toString() ?? '',
          granjaNombre: first['granja_nombre']?.toString() ?? '',
          campania: first['campania']?.toString() ?? '',
          galpon: first['galpon']?.toString() ?? '',
        );
      }
    }

    final registrosRaw = r['registros'];
    final registros =
        registrosRaw is List ? registrosRaw.whereType<Map>().toList() : <Map>[];
    for (final reg in registros) {
      final linea = _ubicacionLinea(
        granja: reg['granja']?.toString() ?? '',
        granjaNombre: reg['granja_nombre']?.toString() ?? '',
        campania: reg['campania']?.toString() ?? '',
        galpon: reg['galpon']?.toString() ?? '',
      );
      if (linea.isNotEmpty) return linea;
    }

    return '';
  }

  String _ubicacionLinea({
    required String granja,
    required String granjaNombre,
    required String campania,
    required String galpon,
  }) {
    final granjaConCodigo = [
      if (granja.isNotEmpty) granja,
      if (granjaNombre.isNotEmpty) granjaNombre,
    ].join(' ');
    final partes = <String>[
      if (granjaConCodigo.isNotEmpty) 'Granja: $granjaConCodigo',
      if (campania.isNotEmpty) 'Campa\u00f1a: $campania',
      if (galpon.isNotEmpty) 'Galp\u00f3n: $galpon',
    ];
    return partes.join(' · ');
  }

  String _auditRegTipoLabel(Map<String, dynamic> reg) {
    final label = reg['label']?.toString().trim() ?? '';
    final clave = reg['clave']?.toString() ?? '';
    if (label.isNotEmpty &&
        label.toLowerCase() != 'produccion' &&
        label.toLowerCase() != 'producción') {
      return label;
    }
    if (clave.isNotEmpty) return _tipoFromClave(clave);
    final tipo = reg['tipo_mortalidad']?.toString() ?? '';
    if (tipo.isNotEmpty) return _tipoFromClave(tipo);
    return 'Registro';
  }

  Color _auditRegTipoColor(Map<String, dynamic> reg) {
    final clave = reg['clave']?.toString() ?? '';
    final base = clave.split(':').first;
    final tipo = base.isNotEmpty
        ? base
        : (reg['tipo_mortalidad']?.toString() ?? '');
    switch (tipo.toLowerCase()) {
      case 'incubacion':
        return const Color(0xFFFFB300);
      case 'transporte':
        return const Color(0xFF42A5F5);
      case 'produccion':
        return const Color(0xFF66BB6A);
      case 'despacho':
        return const Color(0xFFFF7043);
      default:
        return AppColors.textSecondary;
    }
  }

  /// Identifica el id de tipo de mortalidad de un registro local.
  /// Los registros guardados localmente usan 'tipo_mortalidad' (id textual);
  /// los provenientes del backend pueden traer 'mortality_type' (índice).
  String? _mortalityTypeId(Map<String, dynamic> r) {
    final rawId = (r['tipo_mortalidad']?.toString() ?? '').trim();
    if (rawId.isNotEmpty) {
      final t = MortalityTypeExt.fromId(rawId);
      if (t != null) return t.id;
    }
    final idx = int.tryParse(r['mortality_type']?.toString() ?? '');
    if (idx != null && idx >= 0 && idx < MortalityType.values.length) {
      return MortalityType.values[idx].id;
    }
    return null;
  }

  /// Color del chip de filtro según el tipo (el color identifica el dato).
  Color _tipoFiltroColor(String id) {
    final t = MortalityTypeExt.fromId(id);
    return t?.accentColor ?? AppColors.primary;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final storage = context.read<StorageService>();

    final mortalityRecords =
        storage.getAllRecords(AppStrings.formTypeMortalidad);
    final auditRecords =
        storage.getAllRecords(AppStrings.formTypeAuditoria);

    final all = <Map<String, dynamic>>[
      ...mortalityRecords,
      ...auditRecords,
    ];

    all.sort((a, b) {
      final dateA = a['tdate_trans']?.toString() ?? '';
      final timeA = a['ttime_trans']?.toString() ?? '';
      final dateB = b['tdate_trans']?.toString() ?? '';
      final timeB = b['ttime_trans']?.toString() ?? '';
      return '$dateB $timeB'.compareTo('$dateA $timeA');
    });

    final filtered = all.where((r) {
      final fecha =
          r['fecha']?.toString() ?? r['tdate_trans']?.toString() ?? '';
      final granja = r['granja']?.toString() ?? '';
      if (fecha.isEmpty || granja.isEmpty) return false;

      // Filtro por tipo de registro
      if (_activeTipoFilters.isNotEmpty) {
        final tipo = r['tipo']?.toString() ?? '';
        if (tipo == 'auditoria') {
          if (!_activeTipoFilters.contains('auditoria')) return false;
        } else {
          final tipoMort = _mortalityTypeId(r);
          if (tipoMort == null || !_activeTipoFilters.contains(tipoMort)) {
            return false;
          }
        }
      }

      if (_desde != null &&
          fecha.compareTo(DateFormat('yyyy-MM-dd').format(_desde!)) < 0) {
        return false;
      }
      if (_hasta != null &&
          fecha.compareTo(DateFormat('yyyy-MM-dd').format(_hasta!)) > 0) {
        return false;
      }
      return true;
    }).toList();

    if (!mounted) return;
    setState(() {
      _records = filtered;
      _loading = false;
    });
  }

  Future<void> _pickDesde() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _desde ?? DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Seleccionar fecha desde',
    );
    if (picked != null && mounted) {
      setState(() => _desde = picked);
      _load();
    }
  }

  Future<void> _pickHasta() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _hasta ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Seleccionar fecha hasta',
    );
    if (picked != null && mounted) {
      setState(() => _hasta = picked);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Theme(
      data: azulReporteTheme(context),
      child: Scaffold(
        appBar: buildAppBar(
          context,
          'Mis Registros',
          appIcon: Icons.assignment_rounded,
        ),
        drawer: const AppDrawer(),
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: _load,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(child: _buildFilters(context)),
                      if (_records.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _buildEmptyState(context),
                        )
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final r = _records[index];
                              final tipo = r['tipo']?.toString() ?? '';
                              if (tipo == 'auditoria') {
                                return _buildAuditoriaCard(context, r, isDark);
                              }
                              return _buildMortalityCard(context, r, isDark);
                            },
                            childCount: _records.length,
                          ),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 80)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilters(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
          Row(
              children: [
                Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _pickDesde,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Desde',
                      prefixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    child: Text(
                      _desde != null
                          ? DateFormat('dd/MM/yyyy').format(_desde!)
                          : '---',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white70 : context.azulTexto,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
                Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _pickHasta,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Hasta',
                      prefixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    child: Text(
                      _hasta != null
                          ? DateFormat('dd/MM/yyyy').format(_hasta!)
                          : '---',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white70 : context.azulTexto,
                      ),
                    ),
                    ),
                  ),
                ),
              ],
          ),
          const SizedBox(height: 10),
          // ── Chips de filtro por tipo ──
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _tipoFiltros.map((tf) {
              final selected = _activeTipoFilters.contains(tf.id);
              final accent = _tipoFiltroColor(tf.id);
              return FilterChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(tf.icon,
                        size: 14,
                        color: selected
                            ? Colors.white
                            : accent.withValues(alpha: 0.9)),
                    const SizedBox(width: 4),
                    Text(tf.label,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: selected
                                ? Colors.white
                                : (isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.textSecondary))),
                  ],
                ),
                selected: selected,
                selectedColor: accent,
                checkmarkColor: Colors.white,
                showCheckmark: true,
                backgroundColor: isDark
                    ? AppColors.darkSurface
                    : Colors.grey.shade100,
                side: BorderSide(
                  color: selected
                      ? accent
                      : (isDark
                          ? AppColors.darkBorder
                          : AppColors.borderLight),
                ),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _activeTipoFilters.add(tf.id);
                    } else {
                      _activeTipoFilters.remove(tf.id);
                    }
                  });
                  _load();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  _desde = null;
                  _hasta = null;
                  _activeTipoFilters.clear();
                });
                _load();
              },
              icon: const Icon(Icons.clear_all_rounded, size: 16),
              label: const Text('Limpiar filtros', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
            Icon(Icons.fact_check_outlined,
                size: 56,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('Sin registros',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 8),
            Text('No hay registros guardados localmente.\n'
                'Deslice hacia abajo para refrescar.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4)),
          ],
        ),
      ),
    );
  }

  // ─── Tarjeta de mortalidad ───
  Widget _buildMortalityCard(
      BuildContext context, Map<String, dynamic> r, bool isDark) {
    final synced = r['synced'] == true;
    final fecha =
        r['fecha']?.toString() ?? r['tdate_trans']?.toString() ?? '';
    final hora = r['ttime_trans']?.toString() ?? '';
    final granja = r['granja']?.toString() ?? '';
    final granjaNombre = r['granja_nombre']?.toString() ?? '';
    final campania = r['campania']?.toString() ?? '';
    final galpon = r['galpon']?.toString() ?? '';
    final cantMachos =
        int.tryParse(r['cant_machos']?.toString() ?? '0') ?? 0;
    final cantHembras =
        int.tryParse(r['cant_hembras']?.toString() ?? '0') ?? 0;
    final detallesCard = MortalityDetail.listFromRecord(r);
    final cantMn = MortalityDetail.totalTipo(detallesCard, 'MN');
    final cantMe = MortalityDetail.totalTipo(detallesCard, 'ME');
    final fechaDisplay = _fmtFecha(fecha);
    final horaDisplay = hora.length >= 5 ? hora.substring(0, 5) : hora;

    // Granja display: código + nombre juntos (p. ej. '621 STA TERESA').
    final granjaConCodigo = [
      if (granja.isNotEmpty) granja,
      if (granjaNombre.isNotEmpty) granjaNombre,
    ].join(' ');

    // Tipo y subtipo
    final tipoRaw = r['tipo_mortalidad']?.toString() ?? '';
    final String tipoLabel;
    final IconData tipoIcon;
    switch (tipoRaw) {
      case 'incubacion':
        tipoLabel = 'Incubacion';
        tipoIcon = Icons.egg_outlined;
      case 'transporte':
        tipoLabel = 'Transporte';
        tipoIcon = Icons.local_shipping_outlined;
      case 'produccion':
        tipoLabel = 'Produccion';
        tipoIcon = Icons.agriculture_outlined;
      case 'despacho':
        tipoLabel = 'Despacho';
        tipoIcon = Icons.inventory_2_outlined;
      default:
        tipoLabel = tipoRaw;
        tipoIcon = Icons.warning_amber_rounded;
    }

    // Color del tipo de registro (el color indica el tipo de dato).
    final tipoAccent = MortalityTypeExt.fromId(tipoRaw)?.accentColor ??
        Theme.of(context).colorScheme.primary;

    String? subtipoLabel;
    if (tipoRaw == 'transporte') {
      final st = (r['subtipo_transporte']?.toString() ?? '').toLowerCase();
      subtipoLabel = st == 'evento' ? 'Evento' : 'Traslado';
    } else if (tipoRaw == 'produccion') {
      final st = (r['origen_analisis']?.toString() ?? '').toLowerCase();
      if (st == 'necropsia') {
        subtipoLabel = 'Necropsia';
      } else if (st == 'laboratorio') {
        subtipoLabel = 'Laboratorio';
      } else if (st == 'cuarentena') {
        subtipoLabel = 'Cuarentena';
      } else {
        subtipoLabel = 'Crianza';
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: Theme.of(context).cardColor,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.borderColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showMortalityDetail(context, r, isDark),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 6,
                color: tipoAccent,
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: tipoAccent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(tipoIcon,
                              color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 8),
                        Expanded(
                          child: Text('Mortalidad $tipoLabel',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface),
                              overflow: TextOverflow.ellipsis),
                        ),
                        Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: synced
                                ? Colors.green.withValues(alpha: 0.15)
                                : Colors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                synced
                                    ? Icons.check_circle_rounded
                                    : Icons.hourglass_empty_rounded,
                                size: 12,
                                color: synced ? Colors.green : Colors.orange,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                synced ? 'Subido' : 'Pendiente',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (fechaDisplay.isNotEmpty)
                          Text(fechaDisplay,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                        if (fechaDisplay.isNotEmpty && horaDisplay.isNotEmpty)
                          Text('  $horaDisplay',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                        if (subtipoLabel != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: tipoAccent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(subtipoLabel,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: tipoAccent)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (granjaConCodigo.isNotEmpty)
                          Text('Granja: $granjaConCodigo',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                        if (campania.isNotEmpty)
                          Text('Campa\u00f1a: $campania',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                        if (galpon.isNotEmpty)
                          Text('Galp\u00f3n: $galpon',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (cantMachos > 0)
                          Text('M: $cantMachos',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.maleDark)),
                        if (cantMachos > 0 && cantHembras > 0)
                          const SizedBox(width: 12),
                        if (cantHembras > 0)
                          Text('H: $cantHembras',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.femaleDark)),
                        if (cantMachos > 0 || cantHembras > 0)
                          const SizedBox(width: 12),
                        Text('Total: ${cantMachos + cantHembras}',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700)),
                        if (cantMn > 0) ...[
                          const SizedBox(width: 12),
                          Text('M.N.: $cantMn',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                        ],
                        if (cantMe > 0) ...[
                          const SizedBox(width: 12),
                          Text('M.E.: $cantMe',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Center(
              child: Icon(Icons.chevron_right_rounded, color: Colors.grey),
            ),
            const SizedBox(width: 10),
          ],
          ),
        ),
      ),
    );
  }

  void _showMortalityDetail(
      BuildContext context, Map<String, dynamic> r, bool isDark) async {
    final tipoId = _mortalityTypeId(r);
    final type = MortalityTypeExt.fromId(tipoId) ?? MortalityType.produccion;

    await MortalitySummarySheet.show(
      context: context,
      type: type,
      data: r,
      readOnly: true,
    );
  }

  // ─── Tarjeta de auditoria ───
  Widget _buildAuditoriaCard(
      BuildContext context, Map<String, dynamic> r, bool isDark) {
    final synced = r['synced'] == true;
    final registrosRaw = r['registros'];
    final registros =
        registrosRaw is List ? registrosRaw.whereType<Map>().toList() : <Map>[];
    final detalleRawCard = r['registros_detalle'];
    final detalleCard = detalleRawCard is List
        ? detalleRawCard.whereType<Map>().toList()
        : <Map>[];
    final fecha = r['fecha']?.toString() ?? r['tdate_trans']?.toString() ?? '';
    final hora = r['ttime_trans']?.toString() ?? '';
    final fechaDisplay = _fmtFecha(fecha);
    final horaDisplay = hora.length >= 5 ? hora.substring(0, 5) : hora;
    final granja = r['granja']?.toString() ?? '';
    final granjaNombre = r['granja_nombre']?.toString() ?? '';
    final campania = r['campania']?.toString() ?? '';
    final granjaConCodigo = [
      if (granja.isNotEmpty) granja,
      if (granjaNombre.isNotEmpty) granjaNombre,
    ].join(' ');
    final cantMachos =
        int.tryParse(r['cant_machos']?.toString() ?? '0') ?? 0;
    final cantHembras =
        int.tryParse(r['cant_hembras']?.toString() ?? '0') ?? 0;

    final tiposCount = <String, int>{};
    if (detalleCard.isNotEmpty) {
      for (final reg in detalleCard) {
        final clave = reg['clave']?.toString() ?? '';
        if (clave.isNotEmpty) {
          tiposCount[clave] = (tiposCount[clave] ?? 0) + 1;
        }
      }
    } else {
      for (final reg in registros) {
        final clave = reg['clave']?.toString() ?? '';
        if (clave.isEmpty) continue;
        final uuids = reg['registro_uuids'];
        final count = uuids is List ? uuids.length : 1;
        tiposCount[clave] = (tiposCount[clave] ?? 0) + count;
      }
    }
    final resumenTipos = tiposCount.entries.map((e) {
      final tipoLabel = _tipoFromClave(e.key);
      return '$tipoLabel: ${e.value}';
    }).join(', ');

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: Theme.of(context).cardColor,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.borderColor),
      ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
        onTap: () => _showAuditoriaDetail(context, r, isDark),
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  width: 6,
                                  color: AppColors.primary,
                                ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                          child: const Icon(Icons.verified_rounded,
                              color: Colors.white, size: 16),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                          child: Text('Auditor\u00eda',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface),
                              overflow: TextOverflow.ellipsis),
                                          ),
                                          Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: synced
                                                  ? Colors.green.withValues(alpha: 0.15)
                                                  : Colors.orange.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                            mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  synced
                                      ? Icons.check_circle_rounded
                                      : Icons.hourglass_empty_rounded,
                                  size: 12,
                                  color: synced ? Colors.green : Colors.orange,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  synced ? 'Subido' : 'Pendiente',
                                              style: const TextStyle(fontSize: 11),
                                ),
                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          if (fechaDisplay.isNotEmpty)
                                            Text(fechaDisplay,
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant)),
                                          if (fechaDisplay.isNotEmpty &&
                                              horaDisplay.isNotEmpty)
                                            Text('  $horaDisplay',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant)),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 2,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          if (granjaConCodigo.isNotEmpty)
                                            Text('Granja: $granjaConCodigo',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.w500,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant)),
                                          if (campania.isNotEmpty)
                                            Text('Campa\u00f1a: $campania',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.w500,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant)),
                                        ],
                                      ),
                                      if (resumenTipos.isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(resumenTipos,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurface)),
                                        ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          if (cantMachos > 0)
                                            Text('M: $cantMachos',
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                    color:
                                                        AppColors.maleDark)),
                                          if (cantMachos > 0 &&
                                              cantHembras > 0)
                                            const SizedBox(width: 12),
                                          if (cantHembras > 0)
                                            Text('H: $cantHembras',
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                    color: AppColors
                                                        .femaleDark)),
                                          if (cantMachos > 0 ||
                                              cantHembras > 0)
                                            const SizedBox(width: 12),
                                          if (cantMachos > 0 ||
                                              cantHembras > 0)
                                            Text(
                                                'Total: ${cantMachos + cantHembras}',
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.w700)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const Center(
                                child: Icon(Icons.chevron_right_rounded,
                                    color: Colors.grey),
                              ),
                              const SizedBox(width: 10),
                            ],
                          ),
                        ),
                      ),
                      );
  }

  void _showAuditoriaDetail(
      BuildContext context, Map<String, dynamic> r, bool isDark) {
    final registrosRaw = r['registros'];
    final registros = registrosRaw is List
        ? registrosRaw.whereType<Map>().toList()
        : <Map>[];

    // Registros auditados de forma individual (campo 'registros_detalle'
    // guardado localmente). Si existen se muestran tal cual; si no, se usa el
    // resumen agrupado por tipo de las auditorías guardadas antes del cambio.
    final detalleRaw = r['registros_detalle'];
    final detalleRegistros = detalleRaw is List
        ? detalleRaw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    // Solo mostramos bloques por registro cuando hay detalle local individual.
    // no representa cada mortalidad por separado.
    final items = detalleRegistros;

    var totalRegistrosAudit = detalleRegistros.length;
    if (detalleRegistros.isEmpty) {
      for (final g in registros) {
        final uuids = g['registro_uuids'];
        totalRegistrosAudit += uuids is List ? uuids.length : 1;
      }
    }

    final fechaRaw = r['fecha']?.toString() ?? r['tdate_trans']?.toString() ?? '';
    final horaRaw = r['ttime_trans']?.toString() ?? '';
    final fechaDisplay = _fmtFecha(fechaRaw);
    final horaDisplay = horaRaw.length >= 5 ? horaRaw.substring(0, 5) : horaRaw;
    final fechaHoraDisplay = [
      if (fechaDisplay.isNotEmpty) fechaDisplay,
      if (horaDisplay.isNotEmpty) horaDisplay,
    ].join(' ');
    final granjaDisplay = _extractGranjaDisplay(r);
    final synced = r['synced'] == true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (ctx) => Theme(
        data: azulReporteTheme(ctx),
        child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.98,
        builder: (context, scrollController) {
          final headerBg = isDark ? AppColors.darkSurface : Colors.white;
          final cardBg = isDark ? AppColors.darkCard : AppColors.cardBackground;

          return Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkBackground : Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
                  decoration: BoxDecoration(
                    color: headerBg,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(
                                  alpha: isDark ? 0.2 : 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.verified_rounded,
                                color: AppColors.primary, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('Resumen de Auditor\u00eda',
                                style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : Theme.of(context).colorScheme.onSurface,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold)),
                          ),
                          IconButton(
                            icon: Icon(Icons.close_rounded,
                                color: isDark
                                    ? Colors.white70
                                    : Theme.of(context).colorScheme.onSurfaceVariant),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Informacion general ──
                        _buildAuditCard(
                          isDark: isDark,
                          cardBg: cardBg,
                          title: 'Informaci\u00f3n general',
                          icon: Icons.info_outline,
                          children: [
                            _auditItem(context, 'Fecha/Hora', fechaHoraDisplay),
                            if (granjaDisplay.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: _auditItem(context, 'Ubicaci\u00f3n',
                                    granjaDisplay),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: _auditItem(context, 'Estado',
                                  synced ? 'Subido' : 'Pendiente'),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: _auditItem(context, 'Registros auditados',
                                  '$totalRegistrosAudit'),
                            ),
                          ],
                        ),
                        if (items.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _buildAuditCard(
                            isDark: isDark,
                            cardBg: cardBg,
                            title: 'Mortalidades',
                            icon: Icons.layers_outlined,
                            children: items.map((reg) {
                              final tipoTxt = _auditRegTipoLabel(reg);
                              final tipoColor = _auditRegTipoColor(reg);
                              final obsReg =
                                  reg['observaciones']?.toString().trim() ?? '';
                              final fotos = reg['fotos'];
                              final fotosList = fotos is List
                                  ? fotos.map((e) => e.toString()).toList()
                                  : <String>[];
                              final mMachos = int.tryParse(
                                      reg['cant_machos']?.toString() ?? '0') ??
                                  0;
                              final mHembras = int.tryParse(
                                      reg['cant_hembras']?.toString() ?? '0') ??
                                  0;
                              final mTotal = int.tryParse(
                                      reg['total_aves']?.toString() ?? '0') ??
                                  (mMachos + mHembras);
                              final fechaReg =
                                  reg['fecha_registro']?.toString() ?? '';
                              final ubicacionReg = _ubicacionLinea(
                                granja: reg['granja']?.toString() ?? '',
                                granjaNombre:
                                    reg['granja_nombre']?.toString() ?? '',
                                campania: reg['campania']?.toString() ?? '',
                                galpon: reg['galpon']?.toString() ?? '',
                              );

                              return Container(
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.darkBackground
                                      : AppColors.background,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: isDark
                                          ? AppColors.darkBorder
                                          : AppColors.borderLight),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 4,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            color: tipoColor,
                                            borderRadius:
                                                BorderRadius.circular(2),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(tipoTxt,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    if (fechaReg.isNotEmpty)
                                      Text(
                                          'Fecha: ${_fmtFecha(fechaReg)}',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: isDark
                                                  ? Colors.white60
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant)),
                                    if (ubicacionReg.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(ubicacionReg,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: isDark
                                                  ? Colors.white60
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant)),
                                    ],
                                    if (obsReg.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text('Obs: $obsReg',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontStyle: FontStyle.italic,
                                              color: isDark
                                                  ? Colors.white60
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant)),
                                    ],
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        if (mMachos > 0)
                                          Text('M: $mMachos',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.maleDark)),
                                        if (mMachos > 0 && mHembras > 0)
                                          const SizedBox(width: 12),
                                        if (mHembras > 0)
                                          Text('H: $mHembras',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.femaleDark)),
                                        if (mMachos > 0 || mHembras > 0)
                                          const SizedBox(width: 12),
                                        Text('Total: $mTotal',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700)),
                                      ],
                                    ),
                                    if (fotosList.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text('Fotos (${fotosList.length}):',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant)),
                                      const SizedBox(height: 5),
                                      PhotoStrip(
                                        fotos: fotosList,
                                        size: 44,
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
        ),
          );
        },
      ),
      ),
    );
  }

  Widget _buildAuditCard({
    required bool isDark,
    required Color cardBg,
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _auditItem(BuildContext context, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface)),
        ),
      ],
    );
  }

  String _fmtFecha(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      // Acepta 'yyyy-MM-dd' o con hora: 'yyyy-MM-dd HH:mm:ss'
      final datePart = raw.trim().split(' ').first;
      final parts = datePart.split('-');
      if (parts.length == 3) {
        return '${parts[2]}/${parts[1]}/${parts[0]}';
      }
    } catch (_) {}
    return raw;
  }

  String _tipoFromClave(String clave) {
    final parts = clave.split(':');
    final base = parts.first.toLowerCase();
    final sub = parts.length > 1 ? parts[1].toLowerCase() : '';
    if (base == 'incubacion') return 'Planta Incubaci\u00f3n';
    if (base == 'despacho') return 'Despacho';
    if (base == 'transporte') {
      return sub == 'evento' ? 'Evento' : 'Traslado';
    }
    if (base == 'produccion') {
      const map = {
        'crianza': 'Crianza',
        'necropsia': 'Necropsia',
        'laboratorio': 'Laboratorio',
        'cuarentena': 'Cuarentena',
      };
      return map[sub] ?? 'Crianza';
    }
    return clave;
  }
}

class _TipoFiltro {
  final String label;
  final String id;
  final IconData icon;
  const _TipoFiltro(this.label, this.id, this.icon);
}
