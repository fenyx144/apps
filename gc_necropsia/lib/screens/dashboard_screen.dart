import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../utils/constants.dart';
import '../services/storage_service.dart';
import '../widgets/app_drawer.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    {
  late DateTime _selectedWeekStart;

  @override
  void initState() {
    super.initState();
    _selectedWeekStart = _getMondayOf(DateTime.now());
  }

  DateTime _getMondayOf(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }

  void _changeWeek(int offset) {
    setState(() {
      _selectedWeekStart = _selectedWeekStart.add(Duration(days: 7 * offset));
    });
  }

  String _getWeekRangeLabel() {
    final end = _selectedWeekStart.add(const Duration(days: 6));
    final formatter = DateFormat('dd/MM');
    return "${formatter.format(_selectedWeekStart)} - ${formatter.format(end)}";
  }

  List<Map<String, dynamic>> _getRegistrosSemana(StorageService storage) {
    final all = storage.getAllRecords(AppStrings.formType1);
    final start = DateTime(_selectedWeekStart.year, _selectedWeekStart.month, _selectedWeekStart.day);
    final end = DateTime(_selectedWeekStart.year, _selectedWeekStart.month, _selectedWeekStart.day + 6);

    return all.where((reg) {
      // Usar FECHA DE REGISTRO para dashboard (tdate / diareg / tdate_trans)
      final fechaStr = reg['tdate_trans'] ?? reg['tdate'] ?? reg['diareg'];
      if (fechaStr == null || fechaStr.toString().isEmpty) return false;
      try {
        final fecha = DateFormat('yyyy-MM-dd').parse(fechaStr.toString());
        final fechaNormalizada = DateTime(fecha.year, fecha.month, fecha.day);
        return (fechaNormalizada.isAtSameMomentAs(start) || fechaNormalizada.isAfter(start)) &&
               (fechaNormalizada.isAtSameMomentAs(end) || fechaNormalizada.isBefore(end));
      } catch (e) {
        return false;
      }
    }).toList();
  }

  Future<void> _refreshData() async {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final registrosSemana = _getRegistrosSemana(storage);

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Container(
          decoration: BoxDecoration(
            gradient: AppColors.headerGradient,
            boxShadow: AppColors.strongShadow,
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: false,
            leading: Builder(
              builder: (context) => IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.menu_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.2),
                        Colors.white.withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.dashboard_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Mi Dashboard',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.98),
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      drawer: const AppDrawer(),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
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
            onRefresh: _refreshData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Resumen de tus registros',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.shade200,
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_left, color: AppColors.primary),
                          onPressed: () => _changeWeek(-1),
                        ),
                        Text(
                          'Semana: ${_getWeekRangeLabel()}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_right, color: AppColors.primary),
                          onPressed: () => _changeWeek(1),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Summary card (sin animación)
                  _buildSummaryCard(registrosSemana),
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
                      const Text(
                        'Registros por fecha',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Gráfico de barras (sin animación)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.shade100,
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      height: 180,
                      child: _buildBarChart(registrosSemana),
                    ),
                  ),

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
                      const Text(
                        'Por CENCO/Granja',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Pie chart por tipo (sin animación)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.shade100,
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      height: 180,
                      child: _buildPieChartTipo(registrosSemana),
                    ),
                  ),

                  const SizedBox(height: 24),

                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.sync,
                          size: 20,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Estado',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Pie chart por estado (sin animación)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.shade100,
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      height: 180,
                      child: _buildPieChartEstado(registrosSemana),
                    ),
                  ),
                ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(List<Map<String, dynamic>> registros) {
    final total = registros.length;
    final pendientes = registros.where((r) => r['synced'] != true).length;
    final subidos = total - pendientes;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMetric('Total', total.toString(), AppColors.primary),
          _buildMetric('Pendientes', pendientes.toString(), Colors.orange),
          _buildMetric('Subidos', subidos.toString(), Colors.green.shade600),
        ],
      ),
    );
  }

  Widget _buildMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
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

  Widget _buildBarChart(List<Map<String, dynamic>> registros) {
    final Map<String, int> conteoPorFecha = {};
    for (var reg in registros) {
      // Usar FECHA DE REGISTRO para el gráfico
      final fechaStr = reg['tdate_trans'] ?? reg['tdate'] ?? reg['diareg'];
      if (fechaStr != null) {
        try {
          final date = DateFormat('yyyy-MM-dd').parse(fechaStr.toString());
          final key = DateFormat('dd/MM').format(date);
          conteoPorFecha.update(key, (value) => value + 1, ifAbsent: () => 1);
        } catch (_) {}
      }
    }

    if (conteoPorFecha.isEmpty) {
      return const Center(
          child: Text('Sin datos', style: TextStyle(color: Colors.grey)));
    }

    final fechas = conteoPorFecha.keys.toList()
      ..sort((a, b) {
        try {
          final da = DateFormat('dd/MM').parse(a);
          final db = DateFormat('dd/MM').parse(b);
          return da.compareTo(db);
        } catch (_) {
          return 0;
        }
      });

    final bars = [
      for (int i = 0; i < fechas.length; i++)
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: conteoPorFecha[fechas[i]]!.toDouble(),
              color: AppColors.primary,
              width: 18,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
    ];

    return AspectRatio(
      aspectRatio: 1.6,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: bars.map((b) => b.barRods.first.toY).reduce(math.max) + 1,
            barGroups: bars,
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, _) {
                    if (v.toInt() >= 0 && v.toInt() < fechas.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 6.0),
                        child: Text(
                          fechas[v.toInt()],
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 20,
                  getTitlesWidget: (v, _) {
                    if (v.toInt() >= 0 && v.toInt() < fechas.length) {
                      final cantidad = conteoPorFecha[fechas[v.toInt()]] ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4.0),
                        child: Text(
                          '$cantidad',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(
              enabled: true,
              touchTooltipData: BarTouchTooltipData(
               
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final valorEntero = rod.toY.toInt();
                  return BarTooltipItem(
                    '$valorEntero',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPieChartTipo(List<Map<String, dynamic>> registros) {
    final Map<String, int> conteo = {};
    for (var r in registros) {
      // Agrupar por granja/CENCO o galpón
      String tipo = 'Sin clasificar';
      if (r['tcencos'] != null && r['tcencos'].toString().isNotEmpty) {
        tipo = r['tcencos'].toString();
      } else if (r['granja'] != null && r['granja'].toString().isNotEmpty) {
        tipo = 'Granja ${r['granja']}';
      } else if (r['galpon'] != null && r['galpon'].toString().isNotEmpty) {
        tipo = 'Galpón ${r['galpon']}';
      }
      
      final tipoTruncado = tipo.length > 16
          ? '${tipo.substring(0, 16)}...'
          : tipo;
      conteo.update(tipoTruncado, (v) => v + 1, ifAbsent: () => 1);
    }

    if (conteo.isEmpty) {
      return const Center(
        child: Text('Sin datos', style: TextStyle(color: Colors.grey)),
      );
    }

    final colores = [
      Colors.blue.shade300,
      Colors.green.shade300,
      Colors.purple.shade300,
      Colors.orange.shade300,
      Colors.red.shade300,
      Colors.teal.shade300,
    ];

    int i = 0;
    final sections = conteo.entries.map((e) {
      return PieChartSectionData(
        color: colores[i++ % colores.length],
        value: e.value.toDouble(),
        title: '${e.key} (${e.value})',
        titleStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
        radius: 50,
        titlePositionPercentageOffset: 0.6,
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

  Widget _buildPieChartEstado(List<Map<String, dynamic>> registrosSemana) {
    if (registrosSemana.isEmpty) {
      return const Center(
        child: Text('Sin datos', style: TextStyle(color: Colors.grey)),
      );
    }

    final pendientes = registrosSemana.where((r) => r['synced'] != true).length;
    final sincronizados = registrosSemana.length - pendientes;

    final sections = [
      if (pendientes > 0)
        PieChartSectionData(
          color: Colors.orange.shade300,
          value: pendientes.toDouble(),
          title: 'Pend. ($pendientes)',
          titleStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
          radius: 50,
          titlePositionPercentageOffset: 0.6,
        ),
      if (sincronizados > 0)
        PieChartSectionData(
          color: Colors.green.shade300,
          value: sincronizados.toDouble(),
          title: 'Sub. ($sincronizados)',
          titleStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
          radius: 50,
          titlePositionPercentageOffset: 0.6,
        ),
    ];

    return PieChart(
      PieChartData(
        sections: sections,
        centerSpaceRadius: 35,
        sectionsSpace: 2,
      ),
    );
  }
}