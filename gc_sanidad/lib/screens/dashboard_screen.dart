import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:gc_puesto_mercado_tienda/services/storage_service.dart';
import 'package:gc_puesto_mercado_tienda/utils/constants.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import '../widgets/app_drawer.dart';
import '../widgets/app_bar.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  int selectedYear = DateTime.now().year;
  final List<int> years = List.generate(6, (i) => DateTime.now().year - i);
  late Future<DashboardData> dataFuture;
  late Future<List<EnvioReciente>> enviosRecientesFuture;
  DateTime _selectedMonth = DateTime.now();
  bool _verTodosLosEnvios = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadData() {
    dataFuture = fetchDashboardData(selectedYear.toString());
    enviosRecientesFuture = fetchEnviosRecientes(selectedYear.toString());
  }

  void _onYearChanged(int? year) {
    if (year != null && year != selectedYear) {
      setState(() {
        selectedYear = year;
      });
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final registrosMes = _getRegistrosMes(storage);
    return Scaffold(
      appBar: _buildAppBar(context),
      drawer: const AppDrawer(),
      body: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          children: [
            Container(
              height: 50,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F9FD),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200, width: 1.5),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                ),
                borderRadius: BorderRadius.circular(11),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF667EEA).withOpacity(0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorWeight: 0,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey[700],
              labelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              tabs: const [
                Tab(text: 'Estadísticas'),
                Tab(text: 'Mis Envíos'),
              ],
              dividerHeight: 0,
            ),
          ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildEstadisticasTab(),
                  _buildRegistrosTab(registrosMes),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEstadisticasTab() {
    return FutureBuilder<DashboardData>(
      future: dataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.orange, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    'No se pudieron cargar las estadísticas',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => setState(_loadData),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          );
        }
        final data = snapshot.data ?? _emptyDashboardData();
        final totalEnvios = data.estado.completadas + data.estado.pendientes;
        final pctCompGen = totalEnvios > 0
            ? (data.estado.completadas / totalEnvios * 100).toStringAsFixed(1)
            : '0.0';
        final pctCuantComp = data.cuantitativas.total > 0
            ? (data.cuantitativas.completadas / data.cuantitativas.total * 100)
                  .toStringAsFixed(1)
            : '0.0';
        final pctCualiComp = data.cualitativas.total > 0
            ? (data.cualitativas.completadas / data.cualitativas.total * 100)
                  .toStringAsFixed(1)
            : '0.0';

        final topM = data.topMuestras.items;
        final topA = data.topAnalisis.items;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 110,
                child: PageView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: _metricsRow([
                        _metricCard(
                          'Envíos Totales',
                          totalEnvios.toString(),
                          Colors.blue,
                          Colors.blue[50]!,
                        ),
                        _metricCard(
                          '% Completas',
                          '$pctCompGen%',
                          Colors.green,
                          Colors.green[50]!,
                        ),
                        _metricCard(
                          'Cuali. Completas',
                          '$pctCualiComp%',
                          Colors.orange,
                          Colors.orange[50]!,
                        ),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: _metricsRow([
                        _metricCard(
                          'Cuant. Completas',
                          '$pctCuantComp%',
                          Colors.cyan,
                          Colors.cyan[50]!,
                        ),
                        _metricCardWithList(
                          'Top 3 Muestras',
                          _top3Names(topM),
                          Colors.amber,
                          Colors.amber[50]!,
                        ),
                        _metricCardWithList(
                          'Top 3 Análisis',
                          _top3Names(topA),
                          Colors.pink,
                          Colors.pink[50]!,
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildYearSelector(),

              const SizedBox(height: 16),
              _buildEnviosRecientes(),
              const SizedBox(height: 16),
              _buildCard(
                title: "Envíos por mes",
                child: SizedBox(
                  height: 200,
                  child: BarChartEnvios(data.envios),
                ),
                legend: _buildEnviosLegend(data.envios),
              ),
              const SizedBox(height: 16),
              _buildCard(
                title: "Estado general de los envíos",
                child: SizedBox(
                  height: 240,
                  child: _PieChart(data.estado, isGeneral: true),
                ),
                legend: _buildEstadoGeneralLegend(data.estado),
              ),
              const SizedBox(height: 16),
              _buildEstadoDetallado(data.cuantitativas, data.cualitativas),
              const SizedBox(height: 16),
              _buildCard(
                title: "Top 10 Muestras",
                child: SizedBox(
                  height: 200,
                  child: _HorizontalBarChart(
                    data.topMuestras,
                    showTooltip: true,
                  ),
                ),
                legend: _buildTopListLegend(data.topMuestras.items, "muestras"),
              ),
              const SizedBox(height: 16),
              _buildCard(
                title: "Top 10 Análisis",
                child: SizedBox(
                  height: 300,
                  child: _HorizontalBarChart(
                    data.topAnalisis,
                    showTooltip: true,
                  ),
                ),
                legend: _buildTopListLegend(data.topAnalisis.items, "análisis"),
              ),

            ],
          ),
        );
      },
    );
  }

    Widget _buildEnviosRecientes() {
    return FutureBuilder<List<EnvioReciente>>(
      future: enviosRecientesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 100,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final envios = snapshot.data ?? [];
        // Filtramos la lista según el estado
        final enviosMostrados = _verTodosLosEnvios ? envios : envios.take(5).toList();

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Últimos envíos',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  if (envios.length > 5) // Solo mostrar si hay más de 5
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _verTodosLosEnvios = !_verTodosLosEnvios;
                        });
                      },
                      icon: Icon(
                        _verTodosLosEnvios ? Icons.visibility_off : Icons.visibility,
                        size: 16,
                        color: const Color(0xFF667EEA),
                      ),
                      label: Text(
                        _verTodosLosEnvios ? 'Ocultar' : 'Ver más',
                        style: const TextStyle(
                          color: Color(0xFF667EEA),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _buildEnviosTable(enviosMostrados),
            ],
          ),
        );
      },
    );
  }

  Widget _metricsRow(List<Widget> cards) {
    return Row(
      children: [
        if (cards.isNotEmpty) Expanded(child: cards[0]),
        for (int i = 1; i < cards.length; i++) ...[
          const SizedBox(width: 12),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }

  List<String> _top3Names(List<TopItem> items) {
    return [
      if (items.isNotEmpty) items[0].name,
      if (items.length > 1) '2°: ${items[1].name}',
      if (items.length > 2) '3°: ${items[2].name}',
    ];
  }

  Widget _metricCard(
    String title,
    String value,
    Color primaryColor,
    Color bgColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        // Degradado sutil
        gradient: LinearGradient(
          colors: [bgColor.withOpacity(0.9), bgColor.withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryColor.withOpacity(0.25), width: 1),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: primaryColor.withOpacity(0.85),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: primaryColor.withOpacity(0.95),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCardWithList(
    String title,
    List<String> items,
    Color primaryColor,
    Color bgColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [bgColor.withOpacity(0.9), bgColor.withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryColor.withOpacity(0.25), width: 1),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: primaryColor.withOpacity(0.85),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          ...items.map(
            (item) => Text(
              item,
              style: TextStyle(
                fontSize: 11,
                color: primaryColor.withOpacity(0.9),
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYearSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Filtrar por año:",
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
            color: Colors.white,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              isExpanded: true,
              value: selectedYear,
              items: years
                  .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                  .toList(),
              onChanged: _onYearChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCard({String? title, required Widget child, Widget? legend}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Text(
              title,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          child,
          if (legend != null) ...[const SizedBox(height: 8), legend],
        ],
      ),
    );
  }

  Widget _buildEnviosLegend(EnviosPorMes data) {
    final total = data.items.fold(0, (sum, item) => sum + item.total);
    return Wrap(
      alignment: WrapAlignment.center,
      runSpacing: 4,
      children: [
        Text(
          'Total: $total envíos',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        const SizedBox(height: 4),
        _buildEnviosLegendColumns(data.items),
      ],
    );
  }

  Widget _buildEnviosLegendColumns(List<EnvioMesItem> items) {
    final half = (items.length / 2).ceil();
    final col1 = items.sublist(0, half);
    final col2 = items.sublist(half);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildEnviosColumnLegend(col1, start: 1),
        const SizedBox(width: 16),
        _buildEnviosColumnLegend(col2, start: half + 1),
      ],
    );
  }

  Widget _buildEnviosColumnLegend(
    List<EnvioMesItem> items, {
    required int start,
  }) {
    final color = const Color(0xFF8b5cf6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < items.length; i++)
          Row(
            children: [
              Container(width: 10, height: 10, color: color),
              const SizedBox(width: 4),
              Text(
                '${start + i}. ${_mesAbrev(items[i].mes)}: ${items[i].total}',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
      ],
    );
  }

  String _mesAbrev(int mes) {
    final abrev = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];
    return abrev[mes - 1];
  }

  Widget _buildEstadoGeneralLegend(EstadoGeneral data) {
    final total = data.total;
    if (total == 0) return const SizedBox();
    final pctComp = (data.completadas / total * 100).toStringAsFixed(1);
    final pctPend = (data.pendientes / total * 100).toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LegendItem('Completadas', data.completadas, pctComp, Colors.blue),
        _LegendItem('Pendientes', data.pendientes, pctPend, Colors.orange),
      ],
    );
  }

  Widget _buildTopListLegend(List<TopItem> items, String tipo) {
    if (items.isEmpty) return const SizedBox();

    return Wrap(
      alignment: WrapAlignment.center,
      runSpacing: 4,
      children: [
        Text(
          'Top ${items.length} $tipo:',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _buildTopColumn(items, start: 1),
          ],
        ),
      ],
    );
  }

  String formatRank(int number, int width) {
    return number.toString().padLeft(width);
  }

  String formatNameFixedWidth(String name, int totalWidth) {
    // Si el nombre es más largo que el espacio disponible
    if (name.length > totalWidth) {
      // Deja espacio para los 3 puntos
      int maxLength = totalWidth - 3;
      if (maxLength <= 0) return '...';
      return name.substring(0, maxLength) + '...';
    } else {
      // Rellenar con espacios hasta totalWidth
      return name.padRight(totalWidth);
    }
  }

  Widget _buildTopColumn(List<TopItem> items, {required int start}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < items.length; i++)
          Text(
            '${formatRank(start + i, 2)}. ${formatNameFixedWidth(items[i].name, 30)} — ${items[i].total}',
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'monospace', // clave para alineación perfecta
            ),
          ),
      ],
    );
  }

  Widget _buildEstadoDetallado(Cuantitativas cuant, Cualitativas cuali) {
    return _buildCard(
      title: "Estado detallado por tipo",
      child: SizedBox(
        height: 160,
        child: Row(
          children: [
            Expanded(
              child: _buildEstadoDetalleColumn(
                "Cuantitativas",
                cuant.completadas,
                cuant.pendientes,
                cuant.total,
                Colors.blue,
                Colors.orange,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildEstadoDetalleColumn(
                "Cualitativas",
                cuali.completadas,
                cuali.pendientes,
                cuali.total,
                Colors.green,
                Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEstadoDetalleColumn(
    String title,
    int completadas,
    int pendientes,
    int total,
    Color colorComp,
    Color colorPending,
  ) {
    final pctComp = total > 0
        ? (completadas / total * 100).toStringAsFixed(1)
        : '0.0';
    final pctPend = total > 0
        ? (pendientes / total * 100).toStringAsFixed(1)
        : '0.0';

    return Column(
      children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.w600,  color: Colors.grey[600]),),
        const SizedBox(height: 6),
        SizedBox(
          height: 70,
          child: PieChart(
            PieChartData(
              sections: [
                PieChartSectionData(
                  value: completadas.toDouble(),
                  color: colorComp,
                  radius: 30,
                ),
                PieChartSectionData(
                  value: pendientes.toDouble(),
                  color: colorPending,
                  radius: 30,
                ),
              ],
              centerSpaceRadius: 15,
              sectionsSpace: 2,
            ),
            swapAnimationDuration: const Duration(milliseconds: 800),
            swapAnimationCurve: Curves.easeOutBack,
          ),
        ),
        const SizedBox(height: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 8, height: 8, color: colorComp),
                const SizedBox(width: 4),
                Text(
                  'Completadas: $pctComp%',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Container(width: 8, height: 8, color: colorPending),
                const SizedBox(width: 4),
                Text(
                  'Pendientes: $pctPend%',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _LegendItem(String label, int count, String pct, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, color: color),
        const SizedBox(width: 4),
        Text('$label: $count — $pct%', style: const TextStyle(fontSize: 11)),
      ],
    );
  }

    Widget _buildEnviosTable(List<EnvioReciente> envios) {
    if (envios.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: Text("No hay envíos recientes")),
      );
    }

    return AnimatedContainer( // Añadido para suavizar el cambio
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5),
        ],
      ),
      child: DataTable(
          columnSpacing: 8,
          headingTextStyle: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
          columns: const [
            DataColumn(label: Text('Código')),
            DataColumn(label: Text('Fecha')),
            DataColumn(label: Text('Estado')),
          ],
          rows: envios.map((e) {
            final estadoColor = e.estado == 'completado'
                ? const Color(0xFFdcfce7)
                : const Color(0xFFfef3c7);
            final estadoText = e.estado == 'completado'
                ? 'Completado'
                : 'Pendiente';
            return DataRow(
              cells: [
                DataCell(
                  Text(e.codEnvio, style: const TextStyle(fontSize: 11)),
                ),
                DataCell(
                  Text(
                    e.fechaFormateada(),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: estadoColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      estadoText,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),

    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(70),
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.headerGradient,
          boxShadow: AppColors.strongShadow,
        ),
        child: buildAppBar(context, 'Dashboard', appIcon: Icons.dashboard),
      ),
    );
  }

  Widget _buildRegistrosTab(List<Map<String, dynamic>> registros) {
    final total = registros.length;
    final pendientes = registros.where((r) => r['synced'] != true).length;
    final subidos = total - pendientes;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSelectorMes(),
          const SizedBox(height: 20),
          _buildResumenRegistros(total, pendientes, subidos),
          const SizedBox(height: 20),

          // Gráfico de estado (pendientes vs subidos)
          if (total > 0)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                          color: Colors.orange,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Estado de Registros',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AspectRatio(
                    aspectRatio: 1,
                    child: _buildPieChartEstado(pendientes, subidos),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSelectorMes() {
    return Container(
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
            icon: const Icon(
              Icons.arrow_back,
              color: Color.fromARGB(235, 26, 43, 86),
            ),
            onPressed: () => _cambiarMes(-1),
          ),
          Text(
            DateFormat(
              'MMMM yyyy',
              Locale('es').toString(),
            ).format(_selectedMonth),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward, color: AppColors.primary),
            onPressed: () => _cambiarMes(1),
          ),
        ],
      ),
    );
  }

  Widget _buildResumenRegistros(int total, int pendientes, int subidos) {
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

  Widget _buildPieChartEstado(int pendientes, int subidos) {
    final sections = <PieChartSectionData>[];

    if (pendientes > 0) {
      sections.add(
        PieChartSectionData(
          color: Colors.orange.shade300,
          value: pendientes.toDouble(),
          title: 'Pend. ($pendientes)',
          titleStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          radius: 60,
        ),
      );
    }
    if (subidos > 0) {
      sections.add(
        PieChartSectionData(
          color: Colors.green.shade400,
          value: subidos.toDouble(),
          title: 'Sub. ($subidos)',
          titleStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          radius: 60,
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 1,
      child: PieChart(
        PieChartData(
          sections: sections,
          centerSpaceRadius: 60,
          sectionsSpace: 2,
        ),
        swapAnimationDuration: const Duration(milliseconds: 800),
        swapAnimationCurve: Curves.easeOutBack,
      ),
    );
  }

  void _cambiarMes(int delta) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
        1,
      );
    });
  }

  Widget _buildMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _getRegistrosMes(StorageService storage) {
    final inicio = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final fin = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final records = storage.getAllRecords(AppStrings.formType1);
    return records.where((r) {
      final f = r['fechaHoraRegistro'] as String?;
      if (f == null) return false;
      try {
        final fecha = DateFormat('yyyy-MM-dd').parse(f);
        return !fecha.isBefore(inicio) && !fecha.isAfter(fin);
      } catch (e) {
        return false;
      }
    }).toList();
  }
}

// === Gráficos ===

class BarChartEnvios extends StatelessWidget {
  final EnviosPorMes data;
  const BarChartEnvios(this.data, {super.key});

  @override
  Widget build(BuildContext context) {
    if (data.items.isEmpty) return const Center(child: Text("Sin datos"));

    return BarChart(
      BarChartData(
        barGroups: List.generate(data.items.length, (i) {
          final item = data.items[i];
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: item.total.toDouble(),
                width: 16,
                color: const Color(0xFF8b5cf6),
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx >= 0 && idx < data.items.length) {
                  return Text(
                    '${idx + 1}',
                    style: const TextStyle(fontSize: 10),
                  );
                }
                return const SizedBox();
              },
            ),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (context) => Colors.purpleAccent.withOpacity(0.8),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                data.items[groupIndex].total.toString(),
                const TextStyle(color: Colors.white),
              );
            },
          ),
        ),

        groupsSpace: 8,
      ),
      swapAnimationDuration: const Duration(milliseconds: 800),
      swapAnimationCurve: Curves.easeOutCubic,
    );
  }
}

class _PieChart extends StatelessWidget {
  final EstadoGeneral data;
  final bool isGeneral;
  const _PieChart(this.data, {required this.isGeneral});

  @override
  Widget build(BuildContext context) {
    final completadas = data.completadas;
    final pendientes = data.pendientes;
    final total = completadas + pendientes;
    if (total == 0) return const Center(child: Text("Sin datos"));

    final color1 = isGeneral
        ? Colors.blue
        : (data is Cualitativas ? Colors.green : Colors.blue);
    final color2 = isGeneral
        ? Colors.orange
        : (data is Cualitativas ? Colors.red : Colors.orange);
    final radius = isGeneral ? 60.0 : 30.0;

    return PieChart(
      PieChartData(
        sections: [
          PieChartSectionData(
            value: completadas.toDouble(),
            color: color1,
            radius: radius,
          ),
          PieChartSectionData(
            value: pendientes.toDouble(),
            color: color2,
            radius: radius,
          ),
        ],
        centerSpaceRadius: isGeneral ? 40 : 15,
        sectionsSpace: 2,
      ),
      swapAnimationDuration: const Duration(milliseconds: 800),
      swapAnimationCurve: Curves.easeOutBack,
    );
  }
}

class _HorizontalBarChart extends StatelessWidget {
  final TopList data;
  final bool showTooltip;
  const _HorizontalBarChart(this.data, {this.showTooltip = false});

  @override
  Widget build(BuildContext context) {
    if (data.items.isEmpty) return const Center(child: Text("Sin datos"));
    return BarChart(
      BarChartData(
        barGroups: List.generate(data.items.length, (i) {
          final item = data.items[i];
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: item.total.toDouble(),
                width: 16,
                color: const Color(0xFF8b5cf6),
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                return Text('${idx + 1}', style: const TextStyle(fontSize: 10));
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        barTouchData: showTooltip
            ? BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (context) => Colors.purpleAccent.withOpacity(0.8),
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    return BarTooltipItem(
                      data.items[groupIndex].total.toString(),
                      const TextStyle(color: Colors.white),
                    );
                  },
                ),
              )
            : BarTouchData(enabled: false),
        groupsSpace: 8,
      ),
      swapAnimationDuration: const Duration(milliseconds: 800),
      swapAnimationCurve: Curves.easeOutCubic,
    );
  }
}

// === Modelos y Fetch (sin cambios funcionales, solo para completitud) ===

class EnvioReciente {
  final String codEnvio;
  final String fecEnvio;
  final String estado;
  EnvioReciente(this.codEnvio, this.fecEnvio, this.estado);
  String fechaFormateada() {
    final parts = fecEnvio.split('-');
    if (parts.length == 3) return '${parts[2]}-${parts[1]}-${parts[0]}';
    return fecEnvio;
  }

  factory EnvioReciente.fromJson(Map<String, dynamic> json) =>
      EnvioReciente(json['codEnvio'], json['fecEnvio'], json['estado']);

  factory EnvioReciente.fromListarEnvio(Map<String, dynamic> json) =>
      EnvioReciente(
        json['codigoEnvio'] as String? ?? '',
        json['fechaEnvio'] as String? ?? '',
        'pendiente',
      );
}

Map<String, String> get _apiHeaders => {
  'Authorization': 'Bearer ${AppConstants.apiToken}',
  'Content-Type': 'application/json; charset=utf-8',
};

Future<List<dynamic>> _fetchListarEnvios() async {
  final uri = Uri.parse('${AppConstants.baseUrlSanidad}/listar_envios.php')
      .replace(queryParameters: {'page': '1'});
  final response = await http
      .get(uri, headers: _apiHeaders)
      .timeout(const Duration(seconds: 30));

  if (response.statusCode != 200) return [];

  final decoded = json.decode(response.body);
  if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
    return [];
  }

  return decoded['data'] as List<dynamic>? ?? [];
}

Future<List<EnvioReciente>> fetchEnviosRecientes(String year) async {
  try {
    final data = await _fetchListarEnvios();
    return data
        .where(
          (e) =>
              e is Map<String, dynamic> &&
              (e['fechaEnvio'] as String?)?.startsWith(year) == true,
        )
        .map((e) => EnvioReciente.fromListarEnvio(e as Map<String, dynamic>))
        .toList();
  } catch (e) {
    debugPrint('fetchEnviosRecientes error: $e');
    return [];
  }
}

DashboardData _emptyDashboardData() => DashboardData(
  EnviosPorMes([]),
  EstadoGeneral(0, 0),
  Cuantitativas(0, 0),
  Cualitativas(0, 0),
  TopList([]),
  TopList([]),
);

Future<Map<String, dynamic>?> _fetchDashboardEndpoint(
  String endpoint,
  String year,
) async {
  try {
    final response = await http
        .get(
          Uri.parse(
            '${AppConstants.baseUrl}${AppConstants.dashboardBasePath}/$endpoint?year=$year',
          ),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) return null;

    final decoded = json.decode(response.body);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

Future<DashboardData> fetchDashboardData(String year) async {
  try {
    final results = await Future.wait([
      _fetchDashboardEndpoint('envios-por-mes.php', year),
      _fetchDashboardEndpoint('estado-solicitudes.php', year),
      _fetchDashboardEndpoint('solicitudes-cuantitativas.php', year),
      _fetchDashboardEndpoint('solicitudes-cualitativas.php', year),
      _fetchDashboardEndpoint('top-muestras.php', year),
      _fetchDashboardEndpoint('top-analisis.php', year),
    ]);

    final envios = results[0];
    final estado = results[1];
    final cuant = results[2];
    final cuali = results[3];
    final muestras = results[4];
    final analisis = results[5];

    if (envios == null &&
        estado == null &&
        cuant == null &&
        cuali == null &&
        muestras == null &&
        analisis == null) {
      return _emptyDashboardData();
    }

    return DashboardData(
      EnviosPorMes.fromJson(envios?['data'] as List<dynamic>? ?? []),
      EstadoGeneral.fromJson(
        estado?['data'] as Map<String, dynamic>? ?? const {},
      ),
      Cuantitativas.fromJson(
        cuant?['data'] as Map<String, dynamic>? ?? const {},
      ),
      Cualitativas.fromJson(
        cuali?['data'] as Map<String, dynamic>? ?? const {},
      ),
      TopList.fromJson(muestras?['data'] as List<dynamic>? ?? []),
      TopList.fromJson(analisis?['data'] as List<dynamic>? ?? []),
    );
  } catch (e) {
    debugPrint('fetchDashboardData error: $e');
    return _emptyDashboardData();
  }
}

class DashboardData {
  final EnviosPorMes envios;
  final EstadoGeneral estado;
  final Cuantitativas cuantitativas;
  final Cualitativas cualitativas;
  final TopList topMuestras;
  final TopList topAnalisis;
  DashboardData(
    this.envios,
    this.estado,
    this.cuantitativas,
    this.cualitativas,
    this.topMuestras,
    this.topAnalisis,
  );
}

class EnviosPorMes {
  final List<EnvioMesItem> items;
  EnviosPorMes(this.items);
  factory EnviosPorMes.fromJson(List<dynamic> json) =>
      EnviosPorMes(json.map((e) => EnvioMesItem.fromJson(e)).toList());
}

class EnvioMesItem {
  final int anio, mes, total;
  EnvioMesItem(this.anio, this.mes, this.total);
  factory EnvioMesItem.fromJson(Map<String, dynamic> json) => EnvioMesItem(
    json['anio'] as int? ?? 0,
    json['mes'] as int? ?? 0,
    json['total'] as int? ?? 0,
  );
}

class EstadoGeneral {
  final int completadas, pendientes;
  EstadoGeneral(this.completadas, this.pendientes);
  factory EstadoGeneral.fromJson(Map<String, dynamic> json) => EstadoGeneral(
    json['completadas'] as int? ?? 0,
    json['pendientes'] as int? ?? 0,
  );
  int get total => completadas + pendientes;
}

class Cuantitativas extends EstadoGeneral {
  Cuantitativas(int c, int p) : super(c, p);
  factory Cuantitativas.fromJson(Map<String, dynamic> json) => Cuantitativas(
    json['completadas'] as int? ?? 0,
    json['pendientes'] as int? ?? 0,
  );
}

class Cualitativas extends EstadoGeneral {
  Cualitativas(int c, int p) : super(c, p);
  factory Cualitativas.fromJson(Map<String, dynamic> json) => Cualitativas(
    json['completadas'] as int? ?? 0,
    json['pendientes'] as int? ?? 0,
  );
}

class TopList {
  final List<TopItem> items;
  TopList(this.items);
  factory TopList.fromJson(List<dynamic> json) =>
      TopList(json.map((e) => TopItem.fromJson(e)).toList());
}

class TopItem {
  final String name;
  final int total;
  TopItem(this.name, this.total);
  factory TopItem.fromJson(Map<String, dynamic> json) => TopItem(
    (json['nomMuestra'] ?? json['nomAnalisis'] ?? '') as String,
    json['total'] as int? ?? 0,
  );
}
