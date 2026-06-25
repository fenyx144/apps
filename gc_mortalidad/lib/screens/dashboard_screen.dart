import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';
import '../services/catalog_download_service.dart';
import '../services/catalog_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/mortality_design.dart';
import '../widgets/app_bar.dart';
import '../widgets/app_drawer.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late DateTime _weekStart;
  final _catalogDownload = CatalogDownloadService();
  bool _autoDownloadStarted = false;

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

  List<Map<String, dynamic>> _weekRecords(StorageService storage) {
    final all = storage.getAllRecords(AppStrings.formTypeMortalidad);
    final end = _weekStart.add(const Duration(days: 6));
    return all.where((r) {
      final raw = r['tdate_trans']?.toString() ?? r['fecha']?.toString() ?? '';
      if (raw.isEmpty) return false;
      try {
        final d = DateTime.parse(raw.split(' ').first);
        final dn = DateTime(d.year, d.month, d.day);
        return !dn.isBefore(_weekStart) && !dn.isAfter(end);
      } catch (_) {
        return false;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final registros = _weekRecords(storage);
    final total = registros.length;
    final pendientes = registros.where((r) => r['synced'] != true).length;
    final subidos = total - pendientes;

    final byType = <String, int>{};
    for (final r in registros) {
      final t = r['tipo_mortalidad']?.toString() ?? 'otro';
      byType[t] = (byType[t] ?? 0) + 1;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedText = isDark ? Colors.white54 : Colors.grey;

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
            const SizedBox(height: 16),
            Row(
              children: [
                _statCard(context, AppStrings.total, '$total', Icons.list_alt_rounded, AppColors.primary),
                const SizedBox(width: 12),
                _statCard(context, AppStrings.pendientes, '$pendientes', Icons.pending_actions_rounded, AppColors.warning),
                const SizedBox(width: 12),
                _statCard(context, AppStrings.subidos, '$subidos', Icons.cloud_done_rounded, AppColors.success),
              ],
            ),
            const SizedBox(height: 24),
            _sectionTitle('Registros por fecha', isDark),
            SizedBox(
              height: 220,
              child: _buildBarChart(registros, isDark),
            ),
            const SizedBox(height: 24),
            _sectionTitle('Por tipo de mortalidad', isDark),
            SizedBox(
              height: 200,
              child: byType.isEmpty
                  ? Center(child: Text('Sin datos', style: TextStyle(color: mutedText)))
                  : PieChart(
                      PieChartData(
                        sections: byType.entries.map((e) {
                          final type = MortalityTypeExt.fromId(e.key);
                          return PieChartSectionData(
                            value: e.value.toDouble(),
                            title: '${type?.title ?? e.key}\n${e.value}',
                            color: type?.accentColor ?? Colors.grey,
                            radius: 60,
                            titleStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _buildBarChart(List<Map<String, dynamic>> registros, bool isDark) {
    final axisColor = isDark ? Colors.white54 : Colors.grey.shade700;
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
    final maxY = math.max(maxCount + 1, 2).toDouble();
    final bars = [
      for (var i = 0; i < fechas.length; i++)
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: (conteoPorFecha[fechas[i]] ?? 0).toDouble(),
              color: AppColors.primary,
              width: 14,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            ),
          ],
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 8, top: 8, bottom: 4),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          minY: 0,
          maxY: maxY,
          barGroups: bars,
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= fechas.length) return const SizedBox.shrink();
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
                  if (value < 0 || value > maxY) return const SizedBox.shrink();
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
    );
  }

  Widget _weekSelector(bool isDark) {
    final end = _weekStart.add(const Duration(days: 6));
    final fmt = DateFormat('dd/MM');
    final isCurrentWeek = _weekStart.isAtSameMomentAs(_mondayOf(DateTime.now()));

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
            onPressed: () => setState(() => _weekStart = _weekStart.subtract(const Duration(days: 7))),
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
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                if (!isCurrentWeek)
                  GestureDetector(
                    onTap: () => setState(() => _weekStart = _mondayOf(DateTime.now())),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Ir a semana actual',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
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
                        color: isDark ? Colors.white54 : Colors.grey,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _weekStart = _weekStart.add(const Duration(days: 7))),
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
            color: isDark ? Colors.white : AppColors.textPrimary,
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
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 8),
              Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
