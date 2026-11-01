import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/theme_colors.dart';
import '../widgets/app_card.dart';
import '../widgets/app_drawer.dart';
import '../widgets/granja_campania_picker.dart';
import '../widgets/screen_status_bar.dart';
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

    final porGranja = <String, Map<String, dynamic>>{};
    for (final r in week) {
      final g3 = r['granja']?.toString() ?? '';
      final nom = r['granjaNombre']?.toString() ?? '';
      final camp = GranjaCampaniaPicker.padCampania(
        r['campania']?.toString() ?? '',
      );
      final label = GranjaCampaniaPicker.formatGranjaLabel(g3, nom);
      final key = '$g3|$camp';
      final entry = porGranja.putIfAbsent(
        key,
        () => {
          'label': label.isNotEmpty ? label : (g3.isNotEmpty ? g3 : '?'),
          'camp': camp,
          'count': 0,
        },
      );
      entry['count'] = (entry['count'] as int) + 1;
    }
    final porGranjaList = porGranja.values.toList()
      ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

    final isDark = Theme.of(context).brightness == Brightness.dark;
    const lightGradientEnd = Color(0xFFD6E4F0);
    const darkGradientEnd = Color(0xFF121212);

    return ScreenStatusBar(
      color: AppColors.primary,
      iconBrightness: Brightness.light,
      navigationBarColor: isDark ? darkGradientEnd : lightGradientEnd,
      child: Scaffold(
      backgroundColor: isDark ? darkGradientEnd : lightGradientEnd,
      extendBody: true,
      drawer: const AppDrawer(),
      appBar: SectionAppBar(
        title: AppStrings.menuDashboard,
        sectionIcon: Icons.dashboard_rounded,
        navigationBarColor: isDark ? darkGradientEnd : lightGradientEnd,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    const Color(0xFF1A1A1A),
                    darkGradientEnd,
                  ]
                : const [
              Color(0xFFF8F9FA),
              Color(0xFFE8EEF3),
              lightGradientEnd,
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          bottom: false,
          child: RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  16 + MediaQuery.paddingOf(context).bottom,
                ),
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
                    if (porGranjaList.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.1),
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
                        child: _buildPieChartByGranja(porGranjaList, tc),
                      ),
                    ],
                  ],
                ),
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

  static const _granjaPalette = [
    Color(0xFF42A5F5),
    Color(0xFFAB47BC),
    Color(0xFF26A69A),
    Color(0xFFEF5350),
    Color(0xFF7E57C2),
    Color(0xFFFF7043),
    Color(0xFF29B6F6),
    Color(0xFF66BB6A),
    Color(0xFFEC407A),
    Color(0xFF8D6E63),
    Color(0xFF78909C),
    Color(0xFFFFD54F),
  ];

  Widget _buildPieChartByGranja(
    List<Map<String, dynamic>> porGranja,
    BuildContext context,
  ) {
    Color pieColor(int idx) => _granjaPalette[idx % _granjaPalette.length];

    final sections = porGranja.asMap().entries.map((e) {
      return PieChartSectionData(
        value: (e.value['count'] as int).toDouble(),
        title: '${e.value['count']}',
        radius: 44,
        titleStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: context.textThemePrimary,
        ),
        color: pieColor(e.key),
      );
    }).toList();

    return Column(
      children: [
        SizedBox(
          height: 140,
          child: PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 30,
              sectionsSpace: 2,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              const SizedBox(width: 22),
              Expanded(
                flex: 3,
                child: Text(
                  'Granja',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: context.textThemeSecondary,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              SizedBox(
                width: 52,
                child: Text(
                  'Camp',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: context.textThemeSecondary,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  'Cant.',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: context.textThemeSecondary,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (final e in porGranja.asMap().entries) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: pieColor(e.key),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: Text(
                    e.value['label'].toString(),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: context.textThemePrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    (e.value['camp'] as String).isNotEmpty
                        ? e.value['camp'].toString()
                        : '—',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.textThemeSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${e.value['count']}',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: pieColor(e.key),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
