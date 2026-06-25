// lib/screens/dashboard_tracking_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:gc_puesto_mercado_tienda/utils/constants.dart';
import 'package:gc_puesto_mercado_tienda/widgets/app_drawer.dart';
import 'package:gc_puesto_mercado_tienda/services/storage_service.dart';
import '../models/dashboard_model.dart';
import '../widgets/app_bar.dart';

class DashboardTrackingScreen extends StatefulWidget {
  const DashboardTrackingScreen({super.key});

  @override
  State<DashboardTrackingScreen> createState() =>
      _DashboardTrackingScreenState();
}

class _DashboardTrackingScreenState extends State<DashboardTrackingScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;

  // Estado de los botones activos (Pestaña 1)
  String _periodoEnvios = 'mes'; // 'dia', 'semana', 'mes'
  String _unidadDemora = 'horas'; // 'horas', 'dias'

  // Futures para cada gráfico
  late Future<EnviosData> _enviosFuture;
  late Future<EstadoData> _estadoFuture;
  late Future<TopAnalisisData> _topAnalisisFuture;
  late Future<DemoraData> _demoraFuture;

  // Estado Pestaña 2
  DateTime _selectedMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _cargarDatos();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _cargarDatos() {
    _enviosFuture = _fetchEnvios(_periodoEnvios);
    _estadoFuture = _fetchEstado();
    _topAnalisisFuture = _fetchTopAnalisis();
    _demoraFuture = _fetchDemoras(_unidadDemora);
  }

  void _cambiarPeriodo(String nuevo) {
    setState(() {
      _periodoEnvios = nuevo;
    });
    _enviosFuture = _fetchEnvios(nuevo);
  }

  void _cambiarUnidad(String unidad) {
    setState(() {
      _unidadDemora = unidad;
    });
    _demoraFuture = _fetchDemoras(unidad);
  }

  // === API CALLS ===
  Future<EnviosData> _fetchEnvios(String periodo) async {
    final res = await http.get(
      Uri.parse(
        '${AppConstants.baseUrl}/modules/tracking/dashboard/get_envios_tracking.php?periodo=$periodo',
      ),
    );
    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      return EnviosData.fromMap(data);
    }
    throw Exception('Error al cargar envíos');
  }

  Future<EstadoData> _fetchEstado() async {
    final res = await http.get(
      Uri.parse(
        '${AppConstants.baseUrl}/modules/tracking/dashboard/get_estado_envios.php',
      ),
    );
    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      return EstadoData.fromMap(data);
    }
    throw Exception('Error al cargar estado');
  }

  Future<TopAnalisisData> _fetchTopAnalisis() async {
    final res = await http.get(
      Uri.parse(
        '${AppConstants.baseUrl}/modules/tracking/dashboard/get_top_analisis.php',
      ),
    );
    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      return TopAnalisisData.fromMap(data);
    }
    throw Exception('Error al cargar top análisis');
  }

  Future<DemoraData> _fetchDemoras(String unidad) async {
    final res = await http.get(
      Uri.parse(
        '${AppConstants.baseUrl}/modules/tracking/dashboard/get_demoras.php?unidad=$unidad',
      ),
    );
    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      return DemoraData.fromMap(data);
    }
    throw Exception('Error al cargar demoras');
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final registrosMes = _getRegistrosTrackingMes(storage);

    return Scaffold(
      appBar: buildAppBar(
        context,
        'Dashboard Tracking',
        appIcon: Icons.dashboard,
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          // Barra de Tabs
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
                Tab(text: 'Mis Recepciones'),
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
    );
  }

  // === PESTAÑA 1: ESTADÍSTICAS ===
  Widget _buildEstadisticasTab() {
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _cargarDatos();
        });
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ==== Top 10 análisis ====
            _buildCard(
              title: "Top 10 Análisis más solicitados",
              child: FutureBuilder<TopAnalisisData>(
                future: _topAnalisisFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 100,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (!snapshot.hasData)
                    return const Center(child: Text("Sin datos"));
                  final data = snapshot.data!;
                  return Column(
                    children: [
                      SizedBox(
                        height: 200,
                        child: _HorizontalBarChart(
                          labels: data.labels,
                          values: data.data,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildSimpleTopLegend(data.labels, data.data),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            // ==== Tiempo promedio por etapa ====
            _buildCard(
              title: "Tiempo promedio de demora por etapa",
              child: FutureBuilder<DemoraData>(
                future: _demoraFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 100,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (!snapshot.hasData)
                    return const Center(child: Text("Sin datos"));
                  final data = snapshot.data!;
                  final unidad = _unidadDemora == 'horas' ? 'h' : 'd';
                  return Column(
                    children: [
                      _buildUnidadSelector(),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 200,
                        child: _BarChartDemoras(
                          labels: data.labels,
                          values: data.data,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildDemoraLegend(data.labels, data.data, unidad),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            // ==== Envíos realizados ====
            _buildCard(
              title: "Envíos realizados",
              child: FutureBuilder<EnviosData>(
                future: _enviosFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 100,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (!snapshot.hasData)
                    return const Center(child: Text("Sin datos"));
                  final data = snapshot.data!;
                  return Column(
                    children: [
                      // _buildPeriodSelector(),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 200,
                        child: _BarChartEnvios(
                          labels: data.labels,
                          values: data.data,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildEnviosLegend(data.labels, data.data),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            // ==== Estado general ====
            _buildCard(
              title: "Estado general de envíos",
              child: FutureBuilder<EstadoData>(
                future: _estadoFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 100,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (!snapshot.hasData)
                    return const Center(child: Text("Sin datos"));
                  final data = snapshot.data!;
                  return Column(
                    children: [
                      SizedBox(
                        height: 140,
                        child: _PieChartEstado(
                          completados: data.completados,
                          pendientes: data.pendientes,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildEstadoLegend(data.completados, data.pendientes),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            const CalendarTrackingCard(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // === PESTAÑA 2: MIS RECEPCIONES ===
  Widget _buildRegistrosTab(List<Map<String, dynamic>> registros) {
    final total = registros.length;
    final completados = registros.where((r) => r['synced'] == true).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSelectorMes(),
          const SizedBox(height: 20),
          _buildResumenRegistros(total, completados),
          const SizedBox(height: 20),
          if (registros.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text(
                "No hay recepciones registradas este mes",
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: registros.length,
              itemBuilder: (context, index) {
                final r = registros[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF667EEA).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.local_shipping,
                        color: Color(0xFF667EEA),
                        size: 20,
                      ),
                    ),
                    title: Text(
                      r['codEnvio'] ?? 'S/C',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text("Receptor: ${r['tipoReceptor']}"),
                        Text("Fecha: ${r['fecEnvio']} ${r['horaEnvio']}"),
                      ],
                    ),
                    trailing: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 20),
                        SizedBox(height: 4),
                        Text(
                          "Enviado",
                          style: TextStyle(fontSize: 10, color: Colors.green),
                        ),
                      ],
                    ),
                    onTap: () => _mostrarDetalleRegistro(r),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // === HELPERS PESTAÑA 2 ===
  List<Map<String, dynamic>> _getRegistrosTrackingMes(StorageService storage) {
    final records = storage.getAllRecords('orden_tracking');
    return records
        .where((r) {
          try {
            final fechaStr = r['fechaHoraRegistro'] as String?;
            if (fechaStr == null) return false;
            final fecha = DateTime.parse(fechaStr);
            return fecha.year == _selectedMonth.year &&
                fecha.month == _selectedMonth.month;
          } catch (_) {
            return false;
          }
        })
        .toList()
        .reversed
        .toList(); // Mostrar más recientes primero
  }

  Widget _buildSelectorMes() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
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
            icon: const Icon(Icons.chevron_left, color: Color(0xFF667EEA)),
            onPressed: () => _cambiarMes(-1),
          ),
          Text(
            DateFormat('MMMM yyyy', 'es').format(_selectedMonth).toUpperCase(),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Color(0xFF667EEA)),
            onPressed: () => _cambiarMes(1),
          ),
        ],
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

  Widget _buildResumenRegistros(int total, int subidos) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade100,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMetricResumen(
            'Total',
            total.toString(),
            const Color(0xFF667EEA),
          ),
          //_buildMetricResumen('Sincronizados', subidos.toString(), Colors.green),
        ],
      ),
    );
  }

  Widget _buildMetricResumen(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  void _mostrarDetalleRegistro(Map<String, dynamic> r) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white, // Fondo blanco añadido
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          "Detalle de Recepción",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRowDetail("Código:", r['codEnvio']),
            _buildInfoRowDetail("Laboratorio:", r['nomLab']),
            _buildInfoRowDetail("Receptor:", r['tipoReceptor']),
            _buildInfoRowDetail(
              "Fecha Envío:",
              "${r['fecEnvio']} ${r['horaEnvio']}",
            ),
            if (r['observaciones'] != null &&
                r['observaciones'].toString().isNotEmpty)
              _buildInfoRowDetail("Obs:", r['observaciones']),
            const Divider(),
            _buildInfoRowDetail(
              "Registrado el:",
              DateFormat(
                'dd/MM/yyyy HH:mm',
              ).format(DateTime.parse(r['fechaHoraRegistro'])),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cerrar"),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRowDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Colors.grey,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  // === WIDGETS COMUNES Y MÉTODOS DE LA PESTAÑA 1 (ESTADÍSTICAS) ===

  Widget _buildSimpleTopLegend(List<String> labels, List<int> values) {
    if (labels.isEmpty) return const SizedBox();
    const int maxNameWidth = 24;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Top análisis:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        const SizedBox(height: 6),
        for (int i = 0; i < labels.length; i++)
          Text(
            '${(i + 1).toString().padLeft(2)}. ${labels[i].length > maxNameWidth ? "${labels[i].substring(0, maxNameWidth - 3)}..." : labels[i].padRight(maxNameWidth)} — ${values[i]}',
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
      ],
    );
  }

  Widget _buildDemoraLegend(
    List<String> labels,
    List<double> values,
    String unidad,
  ) {
    if (labels.isEmpty) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Etapas:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        const SizedBox(height: 6),
        for (int i = 0; i < labels.length; i++)
          Text(
            '${(i + 1).toString().padLeft(2)}. ${labels[i]} — ${values[i].toStringAsFixed(1)} $unidad',
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
      ],
    );
  }

  Widget _buildEnviosLegend(List<String> labels, List<int> values) {
    if (labels.isEmpty) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Períodos:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        const SizedBox(height: 6),
        for (int i = 0; i < labels.length; i++)
          Text(
            '${(i + 1).toString().padLeft(2)}. ${labels[i]} — ${values[i]}',
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
      ],
    );
  }

  Widget _buildEstadoLegend(int completados, int pendientes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Resumen:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Text(
          'Completados — $completados',
          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
        ),
        Text(
          'Pendientes  — $pendientes',
          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
        ),
      ],
    );
  }

  Widget _buildCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
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
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Row(
      children: [
        _buildToggleBtn(
          'Por día',
          _periodoEnvios == 'dia',
          () => _cambiarPeriodo('dia'),
        ),
        const SizedBox(width: 8),
        _buildToggleBtn(
          'Por semana',
          _periodoEnvios == 'semana',
          () => _cambiarPeriodo('semana'),
        ),
        const SizedBox(width: 8),
        _buildToggleBtn(
          'Por mes',
          _periodoEnvios == 'mes',
          () => _cambiarPeriodo('mes'),
        ),
      ],
    );
  }

  Widget _buildUnidadSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildToggleBtn(
          'En horas',
          _unidadDemora == 'horas',
          () => _cambiarUnidad('horas'),
        ),
        const SizedBox(width: 8),
        _buildToggleBtn(
          'En días',
          _unidadDemora == 'dias',
          () => _cambiarUnidad('dias'),
        ),
      ],
    );
  }

  Widget _buildToggleBtn(String label, bool active, VoidCallback onTap) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: active ? Colors.blue : Colors.grey.shade300,
        foregroundColor: active ? Colors.white : Colors.grey[800],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      onPressed: onTap,
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// === COMPONENTES DE GRÁFICOS (Extraídos para limpieza) ===

class _BarChartEnvios extends StatelessWidget {
  final List<String> labels;
  final List<int> values;
  const _BarChartEnvios({required this.labels, required this.values});

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const Center(child: Text("Sin datos"));
    return BarChart(
      BarChartData(
        barGroups: List.generate(
          labels.length,
          (i) => BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: values[i].toDouble(),
                width: 16,
                color: const Color(0xFF3b82f6),
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, m) => Text(
                (v.toInt() + 1).toString(),
                style: const TextStyle(fontSize: 10),
              ),
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
        barTouchData: BarTouchData(enabled: true),
      ),
      swapAnimationDuration: const Duration(milliseconds: 800),
      swapAnimationCurve: Curves.easeOutCubic,
    );
  }
}

class _PieChartEstado extends StatelessWidget {
  final int completados, pendientes;
  const _PieChartEstado({required this.completados, required this.pendientes});

  @override
  Widget build(BuildContext context) {
    final total = completados + pendientes;
    if (total == 0) return const Center(child: Text("Sin datos"));
    return PieChart(
      PieChartData(
        sections: [
          PieChartSectionData(
            value: completados.toDouble(),
            color: Colors.blue,
            radius: 40,
            title: '$completados',
            titleStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          PieChartSectionData(
            value: pendientes.toDouble(),
            color: Colors.orange,
            radius: 40,
            title: '$pendientes',
            titleStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
        centerSpaceRadius: 20,
      ),
      swapAnimationDuration: const Duration(milliseconds: 800),
      swapAnimationCurve: Curves.easeOutBack,
    );
  }
}

class _HorizontalBarChart extends StatelessWidget {
  final List<String> labels;
  final List<int> values;
  const _HorizontalBarChart({required this.labels, required this.values});

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const Center(child: Text("Sin datos"));
    return BarChart(
      BarChartData(
        barGroups: List.generate(
          labels.length,
          (i) => BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: values[i].toDouble(),
                width: 16,
                color: const Color(0xFFa855f7),
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, m) => Text(
                (v.toInt() + 1).toString(),
                style: const TextStyle(fontSize: 10),
              ),
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
      ),
      swapAnimationDuration: const Duration(milliseconds: 800),
      swapAnimationCurve: Curves.easeOutCubic,
    );
  }
}

class _BarChartDemoras extends StatelessWidget {
  final List<String> labels;
  final List<double> values;
  const _BarChartDemoras({required this.labels, required this.values});

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const Center(child: Text("Sin datos"));
    final colors = [
      const Color(0xFF3b82f6),
      const Color(0xFFfb923c),
      const Color(0xFF4ade80),
      const Color(0xFFa855f7),
    ];
    return BarChart(
      BarChartData(
        barGroups: List.generate(
          labels.length,
          (i) => BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: values[i],
                width: 16,
                color: colors[i % colors.length],
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, m) => Text(
                (v.toInt() + 1).toString(),
                style: const TextStyle(fontSize: 10),
              ),
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
      ),
      swapAnimationDuration: const Duration(milliseconds: 800),
      swapAnimationCurve: Curves.easeOutCubic,
    );
  }
}

class CalendarTrackingCard extends StatefulWidget {
  const CalendarTrackingCard({super.key});
  @override
  State<CalendarTrackingCard> createState() => _CalendarTrackingCardState();
}

class _CalendarTrackingCardState extends State<CalendarTrackingCard> {
  final TextEditingController _searchController = TextEditingController();
  List<Appointment> _appointments = [];
  bool _isLoading = false;
  CalendarView _calendarView = CalendarView.month;

  Future<void> _fetchCalendarEvents(DateTime start, DateTime end) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _appointments = [];
    });

    final startStr = DateFormat('yyyy-MM-dd 00:00:00').format(start);
    final endStr = DateFormat('yyyy-MM-dd 23:59:59').format(end);
    final url =
        '${AppConstants.baseUrl}/modules/tracking/dashboard/get_eventos_calendario.php'
        '?start=$startStr&end=$endStr'
        '${_searchController.text.isNotEmpty ? "&codEnvio=${Uri.encodeComponent(_searchController.text.trim())}" : ""}';

    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        final List data = json.decode(res.body);
        final List<Appointment> loadedAppointments = [];
        final Set<String> uniqueKeys = {};

        for (var item in data) {
          final String cod = item['extendedProps']['codEnvio'] ?? '';
          final String ubi = item['extendedProps']['ubicacion'] ?? '';
          final String timeStr = item['start'] ?? '';

          if (cod.isEmpty || timeStr.isEmpty) continue;

          DateTime eventTime;
          try {
            eventTime = DateTime.parse(timeStr);
          } catch (e) {
            continue;
          }

          // Clave única: código + ubicación + día
          final String dateKey = DateFormat('yyyy-MM-dd').format(eventTime);
          final String key = "${cod}_${ubi}_$dateKey";

          // Evitar duplicados exactos
          if (uniqueKeys.contains(key)) continue;
          uniqueKeys.add(key);

          final String colorHex =
              (item['color'] as String?)?.replaceAll('#', '') ?? '667EEA';

          loadedAppointments.add(
            Appointment(
              startTime: eventTime,
              endTime: eventTime.add(const Duration(hours: 1)),
              subject: item['title'] ?? 'Sin título',
              color: Color(int.parse('FF$colorHex', radix: 16)),
              notes: ubi,
              id: cod, // ← SOLO guardamos el código, no la clave completa
            ),
          );
        }

        if (mounted) setState(() => _appointments = loadedAppointments);
      }
    } catch (e) {
      debugPrint('Error cal: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Calendario de Tracking",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              if (_isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 550,
            child: SfCalendar(
              view: _calendarView,
              dataSource: AppointmentDataSource(_appointments),
              // ← CLAVE: deshabilitamos el indicador por defecto
              monthViewSettings: const MonthViewSettings(
                showAgenda: true,
                appointmentDisplayMode: MonthAppointmentDisplayMode.none, // ← Esto evita los puntos duplicados
              ),
              monthCellBuilder: (context, details) {
                // Contamos códigos únicos en este día
                final Map<String, Color> uniqueCodesMap = {};

                for (final a in details.appointments) {
                  if (a is! Appointment) continue;
                  final String code = a.id?.toString() ?? '';
                  if (code.isEmpty) continue;
                  
                  // Solo agregamos si no existe (primer color que encontremos)
                  if (!uniqueCodesMap.containsKey(code)) {
                    uniqueCodesMap[code] = a.color;
                  }
                }

                final int totalEvents = uniqueCodesMap.length;
                final List<Color> colors = uniqueCodesMap.values.toList();
                
                final bool isToday =
                    details.date.day == DateTime.now().day &&
                    details.date.month == DateTime.now().month &&
                    details.date.year == DateTime.now().year;

                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade200, width: 0.5),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: isToday
                              ? const Color(0xFF667EEA)
                              : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          details.date.day.toString(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isToday
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isToday ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (totalEvents > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: totalEvents == 1
                              ? Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: colors[0],
                                    shape: BoxShape.circle,
                                  ),
                                )
                              : totalEvents == 2
                                  ? Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: colors[0],
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 3),
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: colors[1],
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 5,
                                          height: 5,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF667EEA),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        Container(
                                          width: 5,
                                          height: 5,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF667EEA),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        const Text(
                                          "+",
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF667EEA),
                                            height: 1,
                                          ),
                                        ),
                                      ],
                                    ),
                        ),
                    ],
                  ),
                );
              },
              onViewChanged: (d) {
                if (d.visibleDates.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _fetchCalendarEvents(
                      d.visibleDates.first,
                      d.visibleDates.last,
                    ),
                  );
                }
              },
              onTap: (d) {
                if ((d.targetElement == CalendarElement.appointment ||
                        d.targetElement == CalendarElement.agenda) &&
                    d.appointments != null &&
                    d.appointments!.isNotEmpty) {
                  _mostrarInfoSimple(d.appointments!.first);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewBtn(String label, CalendarView view) {
    bool sel = _calendarView == view;
    return InkWell(
      onTap: () => setState(() => _calendarView = view),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF667EEA) : const Color(0xFFF5F9FD),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: sel ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  void _mostrarInfoSimple(Appointment app) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          "Info Envío",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Código: ${app.id}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Divider(),
            Text("Ubicación: ${app.notes}"),
            Text(
              "Fecha: ${DateFormat('dd/MM/yyyy HH:mm').format(app.startTime)}",
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cerrar"),
          ),
        ],
      ),
    );
  }
}

class AppointmentDataSource extends CalendarDataSource {
  AppointmentDataSource(List<Appointment> source) {
    appointments = source;
  }
}