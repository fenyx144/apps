import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/theme_colors.dart';
import '../utils/route_observer.dart';
import '../widgets/app_card.dart';
import '../widgets/app_drawer.dart';
import '../widgets/section_app_bar.dart';
import 'register_decloracion_screen.dart';
import 'register_vacunacion_screen.dart';
import 'reports_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with RouteAware {
  static const _secciones = ['decloracion', 'vacunacion'];

  // Sin descargas automáticas: el dashboard solo lee datos locales. Los
  // catálogos, la proyección, los galpones y el aviso de versión se actualizan
  // únicamente cuando el usuario pulsa «Descargar» en el menú lateral.

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<void>) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    // Tras guardar un registro y volver del formulario, los contadores se
    // recalculan (Provider no reconstruye si el dashboard quedó bajo la ruta).
    setState(() {});
  }

  // ── Datos para los gráficos ────────────────────────────────────────────

  List<Map<String, dynamic>> _registros(StorageService storage) =>
      storage.getMyRecords();

  /// Clave AAAA-MM-DD del campo `fecha` del registro (ISO o dd/MM/yyyy).
  static String? _fechaRegistroYmd(dynamic raw) {
    final s = raw?.toString().trim() ?? '';
    if (s.isEmpty) return null;
    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s)) {
      return s.substring(0, 10);
    }
    if (s.contains('/')) {
      final p = s.split('/');
      if (p.length == 3) {
        final d = int.tryParse(p[0]);
        final m = int.tryParse(p[1]);
        final y = int.tryParse(p[2]);
        if (d != null && m != null && y != null) {
          return '${y.toString().padLeft(4, '0')}-'
              '${m.toString().padLeft(2, '0')}-'
              '${d.toString().padLeft(2, '0')}';
        }
      }
    }
    final dt = DateTime.tryParse(s);
    if (dt != null) {
      return DateFormat('yyyy-MM-dd').format(dt);
    }
    return null;
  }

  /// Conteo de registros por día para los últimos [dias] días.
  List<({DateTime dia, int total})> _porDia(
    List<Map<String, dynamic>> registros,
    int dias,
  ) {
    final hoy = DateTime.now();
    final out = <({DateTime dia, int total})>[];
    for (var i = dias - 1; i >= 0; i--) {
      final d = DateTime(hoy.year, hoy.month, hoy.day - i);
      final key = DateFormat('yyyy-MM-dd').format(d);
      final total = registros
          .where((r) => _fechaRegistroYmd(r['fecha']) == key)
          .length;
      out.add((dia: d, total: total));
    }
    return out;
  }

  Map<String, int> _porSeccion(List<Map<String, dynamic>> registros) {
    final out = <String, int>{for (final s in _secciones) s: 0};
    for (final r in registros) {
      final rep = r['reporte']?.toString() ?? '';
      if (out.containsKey(rep)) {
        out[rep] = out[rep]! + 1;
      }
    }
    return out;
  }

  List<({String granja, String nombre, int total})> _topGranjas(
    List<Map<String, dynamic>> registros,
    int limite,
  ) {
    final conteo = <String, int>{};
    final nombres = <String, String>{};
    for (final r in registros) {
      final g = (r['granja']?.toString() ?? '').trim();
      if (g.isEmpty) continue;
      conteo[g] = (conteo[g] ?? 0) + 1;
      final n = (r['granjaNombre']?.toString() ?? '').trim();
      if (n.isNotEmpty && !nombres.containsKey(g)) nombres[g] = n;
    }
    final lista = conteo.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return lista
        .take(limite)
        .map((e) => (
              granja: e.key,
              nombre: nombres[e.key] ?? '',
              total: e.value,
            ))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final registros = _registros(storage);
    final pendientes = storage.getMyPendingCount();
    final subidos = registros.length - pendientes;
    final nombre = storage.getUserName() ?? 'USUARIO';

    final hace7 = _porDia(registros, 7);
    final secciones = _porSeccion(registros);
    final top = _topGranjas(registros, 5);

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: const SectionAppBar(
        title: AppStrings.dashboardTitle,
        sectionIcon: Icons.dashboard_rounded,
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSaludo(context, nombre, storage.lastSyncDateDisplay),
            const SizedBox(height: 16),
            _buildStats(context, registros.length, pendientes, subidos),
            const SizedBox(height: 20),
            _buildAccesos(context),
            const SizedBox(height: 20),
            _buildPorDia(context, hace7),
            const SizedBox(height: 20),
            _buildPorSeccion(context, secciones),
            const SizedBox(height: 20),
            _buildTopGranjas(context, top),
          ],
        ),
      ),
    );
  }

  Widget _buildSaludo(
    BuildContext context,
    String nombre,
    String ultimaSync,
  ) {
    final hoy = DateFormat("EEEE d 'de' MMMM", 'es').format(DateTime.now());
    final fecha = hoy.isEmpty ? hoy : hoy[0].toUpperCase() + hoy.substring(1);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: BorderRadius.circular(AppColors.radiusXl),
        boxShadow: AppColors.primaryShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: const Icon(
              Icons.person_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hola, ${nombre.toUpperCase()}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                  // Dos renglones: los nombres largos se cortaban con puntos
                  // suspensivos en la primera línea.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  fecha,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Última subida: $ultimaSync',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats(
    BuildContext context,
    int total,
    int pendientes,
    int subidos,
  ) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: 'Registros',
            value: total,
            icon: Icons.assignment_rounded,
            color: AppColors.primaryDark,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: 'Pendientes',
            value: pendientes,
            icon: Icons.cloud_off_rounded,
            color: AppColors.warning,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: 'Subidos',
            value: subidos,
            icon: Icons.cloud_done_rounded,
            color: AppColors.success,
          ),
        ),
      ],
    );
  }

  Widget _buildAccesos(BuildContext context) {
    final items = [
      (
        icon: Icons.water_drop_outlined,
        label: AppStrings.menuDecloracion,
        screen: () => const RegisterDecloracionScreen(),
      ),
      (
        icon: Icons.vaccines_outlined,
        label: AppStrings.menuVacunacion,
        screen: () => const RegisterVacunacionScreen(),
      ),
      (
        icon: Icons.assessment_outlined,
        label: 'Reportes',
        screen: () => const ReportsScreen(),
      ),
    ];

    // Tres accesos en una fila.
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final ancho = (constraints.maxWidth - spacing * 2) / 3;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              SizedBox(
                width: ancho,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppColors.radiusLg),
                  onTap: () => Get.to(
                    item.screen,
                    transition: Transition.rightToLeftWithFade,
                    duration: const Duration(milliseconds: 320),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 6,
                    ),
                    decoration: BoxDecoration(
                      color: context.surfaceCard,
                      borderRadius: BorderRadius.circular(AppColors.radiusLg),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.22),
                      ),
                      boxShadow: context.cardShadow(blur: 8, dy: 2),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            item.icon,
                            size: 20,
                            color: AppColors.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: context.textThemePrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildPorDia(
    BuildContext context,
    List<({DateTime dia, int total})> datos,
  ) {
    final maxTotal = datos.fold<int>(0, (a, b) => b.total > a ? b.total : a);
    final maxY = (maxTotal == 0 ? 4 : maxTotal + 1).toDouble();

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.bar_chart_rounded,
                size: 18,
                color: AppColors.primaryDark,
              ),
              const SizedBox(width: 6),
              Text(
                'Registros por día',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: context.textThemePrimary,
                ),
              ),
              const Spacer(),
              Text(
                'Últimos 7 días',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: context.textThemeMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                alignment: BarChartAlignment.spaceAround,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY <= 5 ? 1 : maxY / 4,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppColors.borderLight,
                    strokeWidth: 1,
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                        BarTooltipItem(
                      '${rod.toY.toInt()} registro(s)',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      interval: maxY <= 5 ? 1 : maxY / 4,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: TextStyle(
                          fontSize: 10,
                          color: context.textThemeMuted,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= datos.length) {
                          return const SizedBox.shrink();
                        }
                        final d = datos[i].dia;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            DateFormat('dd/MM').format(d),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: context.textThemeSecondary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < datos.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: datos[i].total.toDouble(),
                          width: 18,
                          borderRadius: BorderRadius.circular(5),
                          gradient: const LinearGradient(
                            colors: [AppColors.primaryDark, AppColors.primary],
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                          ),
                          // El total encima de la barra, sin decimales: el dato
                          // se lee sin tener que tocar la barra ni mirar el eje.
                          label: BarChartRodLabel(
                            show: datos[i].total > 0,
                            text: '${datos[i].total}',
                            offset: const Offset(0, 6),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: context.textThemeSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPorSeccion(BuildContext context, Map<String, int> secciones) {
    final colores = {
      'decloracion': AppColors.tableAccent,
      'vacunacion': AppColors.primaryDark,
    };
    final labels = {
      'decloracion': AppStrings.menuDecloracion,
      'vacunacion': AppStrings.menuVacunacion,
    };
    final iconos = {
      'decloracion': Icons.water_drop_outlined,
      'vacunacion': Icons.vaccines_outlined,
    };
    final total = secciones.values.fold<int>(0, (a, b) => a + b);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.pie_chart_rounded,
                size: 18,
                color: AppColors.primaryDark,
              ),
              const SizedBox(width: 6),
              Text(
                'Distribución por sección',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: context.textThemePrimary,
                ),
              ),
              const Spacer(),
              if (total > 0)
                Text(
                  '$total en total',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: context.textThemeMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (total == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Aún no hay registros guardados.',
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: context.textThemeMuted,
                  ),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final dona = SizedBox(
                  height: 156,
                  width: 156,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 46,
                          sections: [
                            for (final e in secciones.entries)
                              if (e.value > 0)
                                PieChartSectionData(
                                  value: e.value.toDouble(),
                                  color: colores[e.key],
                                  radius: 24,
                                  title:
                                      '${(e.value * 100 / total).round()}%',
                                  titleStyle: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$total',
                            style: TextStyle(
                              fontSize: 22,
                              height: 1.1,
                              fontWeight: FontWeight.w800,
                              color: context.textThemePrimary,
                            ),
                          ),
                          Text(
                            total == 1 ? 'registro' : 'registros',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: context.textThemeMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
                final leyenda = Column(
                  children: [
                    for (final e in secciones.entries)
                      _filaSeccion(
                        context,
                        icono: iconos[e.key] ?? Icons.assignment_rounded,
                        color: colores[e.key] ?? AppColors.primary,
                        label: labels[e.key] ?? e.key,
                        valor: e.value,
                        total: total,
                      ),
                  ],
                );
                if (constraints.maxWidth < 330) {
                  return Column(
                    children: [
                      dona,
                      const SizedBox(height: 14),
                      leyenda,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    dona,
                    const SizedBox(width: 14),
                    Expanded(child: leyenda),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  /// Renglón de la leyenda: ícono, nombre, cantidad, porcentaje y una barra con
  /// el peso de la sección en el total.
  Widget _filaSeccion(
    BuildContext context, {
    required IconData icono,
    required Color color,
    required String label,
    required int valor,
    required int total,
  }) {
    final pct = total == 0 ? 0.0 : valor / total;
    final vacio = valor == 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icono,
                size: 14,
                color: vacio ? AppColors.borderLight : color,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: vacio
                        ? context.textThemeMuted
                        : context.textThemePrimary,
                  ),
                ),
              ),
              Text(
                '$valor',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: vacio
                      ? context.textThemeMuted
                      : context.textThemeSecondary,
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 36,
                child: Text(
                  '${(pct * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.textThemeMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 5,
              backgroundColor: AppColors.borderLight,
              valueColor: AlwaysStoppedAnimation(
                vacio ? AppColors.borderLight : color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopGranjas(
    BuildContext context,
    List<({String granja, String nombre, int total})> top,
  ) {
    final maxTotal = top.isEmpty
        ? 1
        : top.map((e) => e.total).reduce((a, b) => a > b ? a : b);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                size: 18,
                color: AppColors.primaryDark,
              ),
              const SizedBox(width: 6),
              Text(
                'Top 5 granjas con más registros',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: context.textThemePrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (top.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'Sin datos para mostrar.',
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: context.textThemeMuted,
                  ),
                ),
              ),
            )
          else
            for (var i = 0; i < top.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i == 0
                            ? AppColors.primary
                            : AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: i == 0
                              ? Colors.white
                              : AppColors.primaryDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _labelGranja(top[i].granja, top[i].nombre),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: context.textThemePrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: top[i].total / maxTotal,
                              minHeight: 6,
                              backgroundColor:
                                  AppColors.primary.withValues(alpha: 0.12),
                              valueColor: const AlwaysStoppedAnimation(
                                AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${top[i].total}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  static String _labelGranja(String granja, String nombre) {
    final limpio = nombre.replaceAll(RegExp(r'\s*C\s*=\s*\d+\s*'), ' ').trim();
    if (limpio.isEmpty) return granja;
    return '$granja $limpio';
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: context.surfaceCard,
        borderRadius: BorderRadius.circular(AppColors.radiusLg),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: context.cardShadow(blur: 8, dy: 2),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: context.textThemePrimary,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: context.textThemeMuted,
            ),
          ),
        ],
      ),
    );
  }
}
