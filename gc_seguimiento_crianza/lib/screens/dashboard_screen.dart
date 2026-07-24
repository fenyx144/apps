import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/catalog_service.dart';
import '../services/catalog_sync_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/theme_colors.dart';
import '../widgets/app_card.dart';
import '../widgets/app_drawer.dart';
import '../widgets/section_app_bar.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncCatalogsSilent());
  }

  Future<void> _syncCatalogsSilent() async {
    final storage = context.read<StorageService>();
    final catalog = context.read<CatalogService>();
    await CatalogSyncService().syncAll(storage: storage, catalog: catalog);
    if (mounted) setState(() {});
  }

  void _changeWeek(int offset) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: 7 * offset));
    });
  }

  List<Map<String, dynamic>> _weekRecords(List<Map<String, dynamic>> all) {
    final end = _weekStart.add(const Duration(days: 6));
    return all.where((r) {
      final f = DateTime.tryParse(r['fecha']?.toString() ?? '');
      if (f == null) return false;
      final d = DateTime(f.year, f.month, f.day);
      return !d.isBefore(_weekStart) && !d.isAfter(end);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tc = context;
    final storage = context.watch<StorageService>();
    final all = storage.getAllRecords();
    final week = _weekRecords(all);
    final synced = week.where((r) => r['synced'] == true).length;
    final pending = week.length - synced;

    final byDay = List.generate(7, (i) {
      final d = _weekStart.add(Duration(days: i));
      final ds = DateFormat('yyyy-MM-dd').format(d);
      return week.where((r) => r['fecha']?.toString() == ds).length;
    });

    final byGranja = <String, int>{};
    for (final r in week) {
      final g = r['granjaNombre']?.toString() ?? r['granja']?.toString() ?? '?';
      byGranja[g] = (byGranja[g] ?? 0) + 1;
    }

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: const SectionAppBar(
        title: AppStrings.menuDashboard,
        sectionIcon: Icons.dashboard_rounded,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: Theme.of(context).brightness == Brightness.dark
                ? [
                    const Color(0xFF1A1A1A),
                    const Color(0xFF121212),
                  ]
                : const [
              Color(0xFFF8F9FA),
              Color(0xFFE8EEF3),
              Color(0xFFD6E4F0),
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          bottom: true,
          child: RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resumen de tus registros',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: tc.textThemePrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppCard(
                      borderRadius: 18,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_left,
                              color: AppColors.primary,
                            ),
                            onPressed: () => _changeWeek(-1),
                          ),
                          Text(
                            'Semana: ${_weekRangeLabel()}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: tc.textThemePrimary,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_right,
                              color: AppColors.primary,
                            ),
                            onPressed: () => _changeWeek(1),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildSummaryCard(
                      total: week.length,
                      pendientes: pending,
                      subidos: synced,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.calendar_today,
                            size: 20,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Registros por día',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: tc.textThemePrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AppCard(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        height: 200,
                        child: _buildBarChart(byDay, tc),
                      ),
                    ),
                    if (byGranja.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.category,
                              size: 20,
                              color: AppColors.accent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Por granja',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: tc.textThemePrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppCard(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(
                          height: 180,
                          child: _buildPieChartByGranja(byGranja),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _weekRangeLabel() {
    final end = _weekStart.add(const Duration(days: 6));
    final formatter = DateFormat('dd/MM');
    return "${formatter.format(_weekStart)} - ${formatter.format(end)}";
  }

  Widget _buildSummaryCard({
    required int total,
    required int pendientes,
    required int subidos,
  }) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _metric(context, 'Total', total.toString(), AppColors.primary),
          _metric(context, 'Pendientes', pendientes.toString(), Colors.orange),
          _metric(context, 'Subidos', subidos.toString(), Colors.green.shade600),
        ],
      ),
    );
  }

  Widget _metric(BuildContext context, String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: context.textThemeSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildBarChart(List<int> byDay, BuildContext context) {
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: byDay.isEmpty
            ? 1
            : (byDay.reduce((a, b) => a > b ? a : b) + 1).toDouble(),
        barGroups: List.generate(7, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: byDay[i].toDouble(),
                color: AppColors.primary,
                width: 18,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final d = _weekStart.add(Duration(days: v.toInt()));
                return Padding(
                  padding: const EdgeInsets.only(top: 6.0),
                  child: Text(
                    DateFormat('E', 'es').format(d).substring(0, 2),
                    style: TextStyle(
                      fontSize: 10,
                      color: context.chartLabelColor,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  Widget _buildPieChartByGranja(Map<String, int> byGranja) {
    final sections = byGranja.entries.map((e) {
      final idx = byGranja.keys.toList().indexOf(e.key);
      final alpha = 0.4 + (idx % 5) * 0.12;
      return PieChartSectionData(
        value: e.value.toDouble(),
        title: '${e.value}',
        radius: 50,
        color: AppColors.primary.withOpacity(alpha.clamp(0.0, 1.0)),
      );
    }).toList();

    return PieChart(
      PieChartData(
        sections: sections,
        centerSpaceRadius: 35,
        sectionsSpace: 2,
      ),
    );
  }
}
