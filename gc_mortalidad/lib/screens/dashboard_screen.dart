import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/catalog_download_service.dart';
import '../services/catalog_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/mortality_design.dart';
import '../utils/theme_extensions.dart';
import '../widgets/app_bar.dart';
import '../widgets/app_drawer.dart';
import '../widgets/mortality_register_icon.dart';

enum _RegistroFiltro { todos, mortalidad, auditoria }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late DateTime _weekStart;
  final _catalogDownload = CatalogDownloadService();
  bool _autoDownloadStarted = false;
  _RegistroFiltro _filtro = _RegistroFiltro.todos;

  @override
  void initState() {
    super.initState();
    _weekStart = _mondayOf(DateTime.now());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChannels.textInput.invokeMethod('TextInput.hide');
      _autoDownloadCatalogsIfNeeded();
    });
  }

  Future<void> _autoDownloadCatalogsIfNeeded() async {
    if (_autoDownloadStarted || !mounted) return;
    _autoDownloadStarted = true;

    final storage = context.read<StorageService>();
    if (!_catalogDownload.catalogsAreEmpty(storage)) return;

    try {
      await _catalogDownload.downloadIfNeeded(
        storage: storage,
        catalogService: context.read<CatalogService>(),
      );
    } catch (e) {
      debugPrint('Error descarga interna en dashboard: $e');
    }
  }

  DateTime _mondayOf(DateTime date) {
    final n = DateTime(date.year, date.month, date.day);
    return n.subtract(Duration(days: n.weekday - 1));
  }

  String _permisoParaTipo(MortalityType t) {
    switch (t) {
      case MortalityType.produccion:
        return 'verRegProduccion';
      case MortalityType.despacho:
        return 'verRegDespacho';
      case MortalityType.incubacion:
        return 'verRegPI';
      case MortalityType.transporte:
        return 'verRegTransporte';
    }
  }

  List<MortalityType> _tiposPermitidos(Map<String, dynamic> permisos) {
    return MortalityType.values
        .where((t) => permisos[_permisoParaTipo(t)] == true)
        .toList();
  }

  /// Cruza permisos ACL con visibilidad del login (`data.visibilidad`).
  List<MortalityType> _tiposVisibles(
    StorageService storage,
    Map<String, dynamic> permisos,
  ) {
    final porPermiso = _tiposPermitidos(permisos);
    if (permisos['verRegMortalidad'] != true) return [];
    final vis = storage.getMortalityVisibility();
    if (vis.isEmpty) return porPermiso;
    final porVis = mortalityTypesFromVisibility(vis);
    return porPermiso.where(porVis.contains).toList();
  }

  bool _puedeVerMortalidad(Map<String, dynamic> permisos) =>
      permisos['verRegMortalidad'] == true;

  bool _puedeVerAuditoria(Map<String, dynamic> permisos) =>
      permisos['verAuditoria'] == true;

  /// Ajusta el filtro UI según lo que el usuario puede ver.
  _RegistroFiltro _filtroEfectivo(Map<String, dynamic> permisos) {
    final verMort = _puedeVerMortalidad(permisos);
    final verAud = _puedeVerAuditoria(permisos);
    if (!verMort && !verAud) return _RegistroFiltro.todos;
    if (verMort && !verAud) return _RegistroFiltro.mortalidad;
    if (!verMort && verAud) return _RegistroFiltro.auditoria;
    switch (_filtro) {
      case _RegistroFiltro.mortalidad:
        return verMort ? _RegistroFiltro.mortalidad : _RegistroFiltro.auditoria;
      case _RegistroFiltro.auditoria:
        return verAud ? _RegistroFiltro.auditoria : _RegistroFiltro.mortalidad;
      case _RegistroFiltro.todos:
        return _RegistroFiltro.todos;
    }
  }

  bool _inWeek(Map<String, dynamic> r) {
    final raw = r['tdate_trans']?.toString() ?? r['fecha']?.toString() ?? '';
    if (raw.isEmpty) return false;
    try {
      final d = DateTime.parse(raw.split(' ').first);
      final dn = DateTime(d.year, d.month, d.day);
      final end = _weekStart.add(const Duration(days: 6));
      return !dn.isBefore(_weekStart) && !dn.isAfter(end);
    } catch (_) {
      return false;
    }
  }

  List<Map<String, dynamic>> _weekMortalidad(StorageService storage) {
    return storage
        .getAllRecords(AppStrings.formTypeMortalidad)
        .where(_inWeek)
        .toList();
  }

  List<Map<String, dynamic>> _weekAuditoria(StorageService storage) {
    return storage
        .getAllRecords(AppStrings.formTypeAuditoria)
        .where(_inWeek)
        .toList();
  }

  List<Map<String, dynamic>> _registrosVisibles(
    StorageService storage,
    Map<String, dynamic> permisos,
    _RegistroFiltro filtro,
  ) {
    final verMort = _puedeVerMortalidad(permisos);
    final verAud = _puedeVerAuditoria(permisos);
    final mort = verMort ? _weekMortalidad(storage) : <Map<String, dynamic>>[];
    final aud = verAud ? _weekAuditoria(storage) : <Map<String, dynamic>>[];

    switch (filtro) {
      case _RegistroFiltro.mortalidad:
        return mort;
      case _RegistroFiltro.auditoria:
        return aud;
      case _RegistroFiltro.todos:
        return [...mort, ...aud];
    }
  }

  Map<String, int> _conteoTipoRegistro(
    StorageService storage,
    List<Map<String, dynamic>> registros,
    Map<String, dynamic> permisos,
    _RegistroFiltro filtro,
  ) {
    if (!_puedeVerAuditoria(permisos) &&
        filtro == _RegistroFiltro.auditoria) {
      return {};
    }
    if (!_puedeVerMortalidad(permisos) &&
        filtro == _RegistroFiltro.mortalidad) {
      return {};
    }

    if (filtro == _RegistroFiltro.auditoria) {
      if (!_puedeVerAuditoria(permisos)) return {};
      final audCount =
          registros.where((r) => r['tipo']?.toString() == 'auditoria').length;
      return audCount > 0 ? {'auditoria': audCount} : {};
    }

    return _conteoPorTipoMortalidad(
      storage,
      registros,
      permisos,
      incluirAuditoria:
          filtro == _RegistroFiltro.todos && _puedeVerAuditoria(permisos),
    );
  }

  Map<String, int> _conteoPorTipoMortalidad(
    StorageService storage,
    List<Map<String, dynamic>> registros,
    Map<String, dynamic> permisos, {
    required bool incluirAuditoria,
  }) {
    if (!_puedeVerMortalidad(permisos)) {
      if (incluirAuditoria && _puedeVerAuditoria(permisos)) {
        final audCount = registros
            .where((r) => r['tipo']?.toString() == 'auditoria')
            .length;
        return audCount > 0 ? {'auditoria': audCount} : {};
      }
      return {};
    }

    final permitidos =
        _tiposVisibles(storage, permisos).map((t) => t.id).toSet();
    final byType = <String, int>{};

    for (final r in registros) {
      if (r['tipo']?.toString() == 'auditoria') continue;
      final t = r['tipo_mortalidad']?.toString() ?? '';
      if (t.isEmpty || !permitidos.contains(t)) continue;
      byType[t] = (byType[t] ?? 0) + 1;
    }

    if (incluirAuditoria && _puedeVerAuditoria(permisos)) {
      final audCount =
          registros.where((r) => r['tipo']?.toString() == 'auditoria').length;
      if (audCount > 0) byType['auditoria'] = audCount;
    }

    return byType;
  }

  String _labelTipo(String key) {
    if (key == 'auditoria') return 'Registros';
    return MortalityTypeExt.fromId(key)?.title ?? key;
  }

  Color _colorTipo(String key) {
    if (key == 'auditoria') return AppColors.primary;
    return MortalityTypeExt.fromId(key)?.accentColor ?? AppColors.textSecondary;
  }

  bool _mostrarSeccionTipos(
    Map<String, dynamic> permisos,
    Map<String, int> byType,
    _RegistroFiltro filtro,
  ) {
    if (byType.isEmpty) return false;
    if (filtro == _RegistroFiltro.auditoria) {
      return _puedeVerAuditoria(permisos);
    }
    if (filtro == _RegistroFiltro.mortalidad) {
      return _puedeVerMortalidad(permisos);
    }
    return _puedeVerMortalidad(permisos) || _puedeVerAuditoria(permisos);
  }

  String _tituloSeccionFecha(_RegistroFiltro filtro) {
    switch (filtro) {
      case _RegistroFiltro.mortalidad:
        return 'Mortalidad por fecha';
      case _RegistroFiltro.auditoria:
        return 'Auditoría por fecha';
      case _RegistroFiltro.todos:
        return 'Registros por fecha';
    }
  }

  String _tituloSeccionTipos(
    Map<String, dynamic> permisos,
    _RegistroFiltro filtro,
  ) {
    if (filtro == _RegistroFiltro.auditoria) {
      return 'Auditoría de la semana';
    }
    if (filtro == _RegistroFiltro.mortalidad) {
      return 'Mortalidad por tipo';
    }
    if (_puedeVerMortalidad(permisos) && _puedeVerAuditoria(permisos)) {
      return 'Por tipo de registro';
    }
    if (_puedeVerAuditoria(permisos)) {
      return 'Auditoría de la semana';
    }
    return 'Mortalidad por tipo';
  }

  Widget _buildContextoVisibilidad(
    Map<String, dynamic> permisos,
    _RegistroFiltro filtro,
  ) {
    final verMort = _puedeVerMortalidad(permisos);
    final verAud = _puedeVerAuditoria(permisos);
    if (!verMort && !verAud) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          'No tiene permisos para ver registros de mortalidad ni auditoría.',
          style: TextStyle(
            fontSize: 13,
            color: context.azulTextoMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    if (verMort && verAud) return const SizedBox.shrink();

    final texto = filtro == _RegistroFiltro.auditoria
        ? 'Mostrando solo registros de auditoría'
        : 'Mostrando solo registros de mortalidad';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            filtro == _RegistroFiltro.auditoria
                ? Icons.verified_rounded
                : Icons.list_alt_rounded,
            size: 16,
            color: filtro == _RegistroFiltro.auditoria
                ? AppColors.primary
                : context.azulTextoMuted,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.azulTextoMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final permisos = storage.getPermisos();
    final filtro = _filtroEfectivo(permisos);
    final registros = _registrosVisibles(storage, permisos, filtro);
    final total = registros.length;
    final pendientes = registros.where((r) => r['synced'] != true).length;
    final subidos = total - pendientes;

    final byType =
        _conteoTipoRegistro(storage, registros, permisos, filtro);
    final mostrarTipos = _mostrarSeccionTipos(permisos, byType, filtro);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedText = context.mutedTextColor;

    return Scaffold(
      appBar: buildAppBar(
        context,
        'Mi Dashboard',
        appIcon: Icons.dashboard_rounded,
      ),
      drawer: const AppDrawer(),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async => setState(() {}),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _weekSelector(isDark),
              const SizedBox(height: 12),
              _buildFiltroRegistros(permisos, isDark),
              _buildContextoVisibilidad(permisos, filtro),
              const SizedBox(height: 16),
              Row(
                children: [
                  _statCard(
                    context,
                    AppStrings.total,
                    '$total',
                    Icons.list_alt_rounded,
                    AppColors.primary,
                  ),
                  const SizedBox(width: 12),
                  _statCard(
                    context,
                    AppStrings.pendientes,
                    '$pendientes',
                    Icons.pending_actions_rounded,
                    AppColors.warning,
                  ),
                  const SizedBox(width: 12),
                  _statCard(
                    context,
                    AppStrings.subidos,
                    '$subidos',
                    Icons.cloud_done_rounded,
                    AppColors.success,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _sectionTitle(_tituloSeccionFecha(filtro), isDark),
              SizedBox(
                height: 220,
                child: _buildBarChart(registros, isDark),
              ),
              if (mostrarTipos) ...[
                const SizedBox(height: 24),
                _sectionTitle(_tituloSeccionTipos(permisos, filtro), isDark),
                SizedBox(
                  height: 188,
                  child: byType.isEmpty
                      ? Center(
                          child: Text(
                            'Sin datos en esta semana',
                            style: TextStyle(color: mutedText),
                          ),
                        )
                      : _buildPieWithLegend(
                          byType,
                          isDark,
                          permisos: permisos,
                          filtro: filtro,
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFiltroRegistros(Map<String, dynamic> permisos, bool isDark) {
    final verMort = permisos['verRegMortalidad'] == true;
    final verAud = permisos['verAuditoria'] == true;
    if (!verMort && !verAud) return const SizedBox.shrink();
    if (verMort && !verAud) return const SizedBox.shrink();
    if (!verMort && verAud) return const SizedBox.shrink();

    final chips = <({
      String label,
      _RegistroFiltro value,
      Widget leading,
    })>[
      (
        label: 'Todos',
        value: _RegistroFiltro.todos,
        leading: Icon(
          Icons.dataset_rounded,
          size: 17,
          color: _filtro == _RegistroFiltro.todos
              ? Colors.white
              : context.azulTexto,
        ),
      ),
      (
        label: 'Mortalidad',
        value: _RegistroFiltro.mortalidad,
        leading: MortalityRegisterIcon(
          size: 16,
          color: _filtro == _RegistroFiltro.mortalidad
              ? Colors.white
              : context.azulTexto,
        ),
      ),
      (
        label: 'Auditoría',
        value: _RegistroFiltro.auditoria,
        leading: Icon(
          Icons.verified_rounded,
          size: 17,
          color: _filtro == _RegistroFiltro.auditoria
              ? Colors.white
              : context.azulTexto,
        ),
      ),
    ];

    return Row(
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _filtroChip(
              label: chips[i].label,
              selected: _filtro == chips[i].value,
              leading: chips[i].leading,
              isDark: isDark,
              onTap: () => setState(() => _filtro = chips[i].value),
            ),
          ),
        ],
      ],
    );
  }

  Widget _filtroChip({
    required String label,
    required bool selected,
    required Widget leading,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected
          ? AppColors.primary
          : (isDark ? AppColors.darkCard : AppColors.cardBackground),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : context.borderColor,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              leading,
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: selected ? Colors.white : context.azulTexto,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPieWithLegend(
    Map<String, int> byType,
    bool isDark, {
    required Map<String, dynamic> permisos,
    required _RegistroFiltro filtro,
  }) {
    final entries = byType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final mortEntries = _puedeVerMortalidad(permisos)
        ? entries.where((e) => e.key != 'auditoria').toList()
        : <MapEntry<String, int>>[];
    final audEntries = _puedeVerAuditoria(permisos)
        ? entries.where((e) => e.key == 'auditoria').toList()
        : <MapEntry<String, int>>[];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 132,
          height: 132,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 28,
              sections: entries.map((e) {
                return PieChartSectionData(
                  value: e.value.toDouble(),
                  color: _colorTipo(e.key),
                  radius: 46,
                  showTitle: false,
                  title: '',
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (mortEntries.isNotEmpty &&
                  (filtro != _RegistroFiltro.auditoria)) ...[
                if (filtro == _RegistroFiltro.todos && audEntries.isNotEmpty)
                  _legendGroupTitle('Mortalidad', isDark),
                ...mortEntries.map((e) => _legendRow(e, isDark)),
              ],
              if (mortEntries.isNotEmpty &&
                  audEntries.isNotEmpty &&
                  filtro == _RegistroFiltro.todos)
                const SizedBox(height: 10),
              if (audEntries.isNotEmpty &&
                  (filtro != _RegistroFiltro.mortalidad)) ...[
                if (filtro == _RegistroFiltro.todos && mortEntries.isNotEmpty)
                  _legendGroupTitle('Auditoría', isDark),
                ...audEntries.map((e) => _legendRow(e, isDark)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _legendGroupTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: title == 'Auditoría'
              ? AppColors.primary
              : context.azulTextoMuted,
        ),
      ),
    );
  }

  Widget _legendRow(MapEntry<String, int> e, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: _colorTipo(e.key),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _labelTipo(e.key),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.azulTexto,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${e.value}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: context.azulTexto,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart(List<Map<String, dynamic>> registros, bool isDark) {
    final axisColor = context.azulTextoMuted;
    final gridColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.grey.withValues(alpha: 0.15);
    final conteoPorFecha = <String, int>{};
    for (final reg in registros) {
      final fechaStr = reg['tdate_trans'] ?? reg['fecha'];
      if (fechaStr == null) continue;
      try {
        final raw = fechaStr.toString().split(' ').first;
        final date = DateTime.parse(raw);
        final key = DateFormat('dd/MM').format(date);
        conteoPorFecha[key] = (conteoPorFecha[key] ?? 0) + 1;
      } catch (_) {}
    }

    final fechas = <String>[];
    for (var i = 0; i < 7; i++) {
      fechas.add(DateFormat('dd/MM').format(_weekStart.add(Duration(days: i))));
    }

    final tieneDatos = conteoPorFecha.values.any((v) => v > 0);
    if (!tieneDatos) {
      return Center(
        child: Text('Sin datos', style: TextStyle(color: axisColor)),
      );
    }

    final maxCount = conteoPorFecha.values.fold<int>(0, math.max);
    final bars = [
      for (var i = 0; i < fechas.length; i++)
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: (conteoPorFecha[fechas[i]] ?? 0).toDouble(),
              color: AppColors.primary,
              width: 14,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(6)),
            ),
          ],
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 8, top: 4, bottom: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const leftRes = 32.0;
          const bottomRes = 30.0;
          const labelSpace = 22.0;
          final ancho = constraints.maxWidth;
          final alto = constraints.maxHeight;
          final plotW = ancho - leftRes;
          final plotH = alto - bottomRes;
          final slotW = plotW / fechas.length;
          final maxY = _chartMaxY(maxCount, plotH, labelSpace);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  minY: 0,
                  maxY: maxY,
                  barGroups: bars,
                  barTouchData: const BarTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= fechas.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              fechas[i],
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: axisColor,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          if (value < 0 || value > maxY) {
                            return const SizedBox.shrink();
                          }
                          if ((value - value.roundToDouble()).abs() > 0.01) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              '${value.toInt()}',
                              style: TextStyle(
                                fontSize: 11,
                                color: axisColor,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 1,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: gridColor,
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                ),
              ),
              for (var i = 0; i < fechas.length; i++) ...[
                if ((conteoPorFecha[fechas[i]] ?? 0) > 0)
                  Positioned(
                    left: leftRes + slotW * (i + 0.5) - 30,
                    top: _barLabelTop(
                      count: conteoPorFecha[fechas[i]]!,
                      maxY: maxY,
                      plotH: plotH,
                      labelSpace: labelSpace,
                    ),
                    width: 60,
                    child: IgnorePointer(
                      child: Text(
                        '${conteoPorFecha[fechas[i]]}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: axisColor,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Escala Y con espacio superior para que la etiqueta no se recorte.
  double _chartMaxY(int maxCount, double plotH, double labelSpace) {
    if (maxCount <= 0) return 2;
    final headroomRatio = (labelSpace / plotH).clamp(0.08, 0.35);
    return math
        .max(maxCount + 1, maxCount / (1 - headroomRatio))
        .ceilToDouble();
  }

  double _barLabelTop({
    required int count,
    required double maxY,
    required double plotH,
    required double labelSpace,
  }) {
    final barTop = plotH * (1 - count / maxY);
    return math.max(2, barTop - labelSpace + 6);
  }

  Widget _weekSelector(bool isDark) {
    final end = _weekStart.add(const Duration(days: 6));
    final fmt = DateFormat('dd/MM');
    final isCurrentWeek =
        _weekStart.isAtSameMomentAs(_mondayOf(DateTime.now()));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : AppColors.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => setState(
              () => _weekStart = _weekStart.subtract(const Duration(days: 7)),
            ),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '${fmt.format(_weekStart)} - ${fmt.format(end)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: context.azulTexto,
                  ),
                ),
                if (!isCurrentWeek)
                  GestureDetector(
                    onTap: () => setState(
                      () => _weekStart = _mondayOf(DateTime.now()),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Ir a semana actual',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.azulTextoMuted,
                        ),
                      ),
                    ),
                  ),
                if (isCurrentWeek)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Semana actual',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: context.azulTextoMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(
              () => _weekStart = _weekStart.add(const Duration(days: 7)),
            ),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, bool isDark) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: context.azulTexto,
          ),
        ),
      );

  Widget _statCard(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: context.borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: context.azulTextoMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
