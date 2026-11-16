import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../services/resultado_solicitud_service.dart';
import '../models/resultado_solicitud.dart';
import '../utils/constants.dart';

import '../widgets/app_bar.dart';
import '../widgets/app_drawer.dart';

class ResultadoSolicitudScreen extends StatefulWidget {
  final String codEnvio;
  final int posSolicitud;

  const ResultadoSolicitudScreen({
    super.key,
    required this.codEnvio,
    required this.posSolicitud,
  });

  @override
  State<ResultadoSolicitudScreen> createState() =>
      _ResultadoSolicitudScreenState();
}

class _ResultadoSolicitudScreenState extends State<ResultadoSolicitudScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<ResultadoAnalisisCuali> _analisisCualitativos = [];
  List<ResultadoAnalisisCuanti> _analisisCuantitativos = [];
  List<DocumentoPdf> _docsCualitativos = [];
  List<DocumentoPdf> _docsCuantitativos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      List<ResultadoAnalisisCuali> analisisCual =
          await ResultadoSolicitudService.fetchAnalisisCuali(
            codEnvio: widget.codEnvio,
            posSolicitud: widget.posSolicitud,
          );
      print('_analisisCualitativos:');
      analisisCual.asMap().forEach((index, item) {
        print(
          '  [$index] nombre: ${item.nombre}, resultado: ${item.resultado}, observacion: ${item.observaciones}',
        );
      });
      List<ResultadoAnalisisCuanti> analisisCuant =
          await ResultadoSolicitudService.fetchAnalisisCuanti(
            codEnvio: widget.codEnvio,
            posSolicitud: widget.posSolicitud,
          );
      final docs = await ResultadoSolicitudService.fetchDocumentosSeparados(
        codEnvio: widget.codEnvio,
        posSolicitud: widget.posSolicitud,
      );

      // Verifica que el widget sigue montado
      if (!mounted) return;

      setState(() {
        _analisisCualitativos = analisisCual;
        _analisisCuantitativos = analisisCuant;
        _docsCualitativos = docs['cualitativos'] ?? [];
        _docsCuantitativos = docs['cuantitativos'] ?? [];
        _isLoading = false;

        // Este print ahora SÍ dRebería aparecer
        print(
          '✅ setState ejecutado: _analisisCualitativos.length = ${_analisisCualitativos.length}',
        );
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // === Descarga de archivos (igual que antes) ===
  Future<void> _downloadAndOpen(String nombre, String ruta) async {
    try {
      final url = Uri.parse('${AppConstants.baseUrl}/$ruta');
      final response = await http.get(url);
      if (response.statusCode != 200)
        throw Exception('HTTP ${response.statusCode}');

      final nombreArchivo = ruta.split('/').last;
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$nombreArchivo');
      await file.writeAsBytes(response.bodyBytes);

      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done)
        throw Exception(result.message ?? 'Error al abrir');
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al abrir archivo: $e')));
    }
  }

  Icon _getFileIcon(String nombre) {
    final ext = nombre.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return const Icon(Icons.picture_as_pdf, color: Colors.red);
      case 'doc':
      case 'docx':
        return const Icon(Icons.article, color: Colors.blue);
      case 'xls':
      case 'xlsx':
        return const Icon(Icons.grid_view, color: Colors.green);
      case 'txt':
        return const Icon(Icons.text_snippet, color: Colors.grey);
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return const Icon(Icons.image, color: Colors.purple);
      default:
        return const Icon(Icons.insert_drive_file, color: Colors.grey);
    }
  }

  // === UI Principal ===
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: buildAppBar(context, 'Resultado de solicitud', showBackButton: true),

      body: Column(
        children: [
          _buildMainTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildCualitativoTab(), _buildCuantitativoTab()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainTabBar() {
    return Container(
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
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        tabs: const [
          Tab(text: 'Cualitativo'),
          Tab(text: 'Cuantitativo'),
        ],
        dividerHeight: 0,
      ),
    );
  }

  // === TAB: Cualitativo (Análisis + Documentos) ===
  Widget _buildCualitativoTab() {
    return _buildAnalisisYDocumentosTab(
      analisis: _analisisCualitativos,
      documentos: _docsCualitativos,
      tipo: 'cualitativo',
    );
  }

  // === TAB: Cuantitativo (Análisis + Documentos) ===
  Widget _buildCuantitativoTab() {
    return _buildAnalisisYDocumentosTab(
      analisis: _analisisCuantitativos
          .map(
            (bb) => ResultadoAnalisisCuali(
              codigo: bb.codigo,
              nombre: bb.nombre,
              resultado: '', // no se usa en BB
              observaciones: '',
            ),
          )
          .toList(),
      documentos: _docsCuantitativos,
      tipo: 'cuantitativo',
      esCuantitativo: true,
      analisisBB: _analisisCuantitativos,
    );
  }

  // === Widget reutilizable ===
  Widget _buildAnalisisYDocumentosTab({
    required List<ResultadoAnalisisCuali> analisis,
    required List<DocumentoPdf> documentos,
    required String tipo,
    bool esCuantitativo = false,
    List<ResultadoAnalisisCuanti>? analisisBB,
  }) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            height: 40,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200, width: 1),
            ),
            child: TabBar(
              indicatorColor: Colors.transparent,
              labelColor: Colors.blue,
              unselectedLabelColor: Colors.grey,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              unselectedLabelStyle: const TextStyle(fontSize: 14),
              tabs: const [
                Tab(text: 'Análisis'),
                Tab(text: 'Documentos'),
              ],
              dividerHeight: 0,
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                // Análisis
                if (!esCuantitativo)
                  _buildAnalisisList(analisis)
                else
                  _buildAnalisisCuantitativoList(analisisBB!),
                // Documentos
                _buildDocumentosList(documentos),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalisisList(List<ResultadoAnalisisCuali> analisis) {
    print('analisis: $analisis');
    if (analisis.isEmpty)
      return const Center(child: Text('Sin análisis cualitativos.'));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: analisis.length,
      itemBuilder: (context, index) {
        final a = analisis[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                a.nombre,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              if (a.resultado.isNotEmpty) Text('Resultado: ${a.resultado}'),
              if (a.observaciones.isNotEmpty) Text('Obs: ${a.observaciones}'),
              if (a.resultado.isEmpty && a.observaciones.isEmpty)
                const Text('Sin resultados registrados.'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAnalisisCuantitativoList(List<ResultadoAnalisisCuanti> items) {
    if (items.isEmpty)
      return const Center(child: Text('Sin análisis cuantitativos.'));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) => _buildBBAnalisisCard(items[index]),
    );
  }

  Widget _buildDocumentosList(List<DocumentoPdf> documentos) {
    if (documentos.isEmpty)
      return const Center(child: Text('No hay documentos.'));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: documentos.length,
      itemBuilder: (context, index) {
        final doc = documentos[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: ListTile(
            leading: _getFileIcon(doc.nombre),
            title: Text(doc.nombre),
            trailing: IconButton(
              icon: const Icon(Icons.download_rounded, color: Colors.blue),
              onPressed: () => _downloadAndOpen(doc.nombre, doc.ruta),
            ),
          ),
        );
      },
    );
  }

  // === Tarjeta de análisis cuantitativo (reutilizada) ===
  Widget _buildBBAnalisisCard(ResultadoAnalisisCuanti item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Análisis: ${item.nombre}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.blueGrey,
            ),
          ),
          const SizedBox(height: 12),
          _buildMetricRow('GMEAN', item.gmean, 'valor'),
          _buildMetricRow('CV (%)', item.cv, 'porcentaje'),
          _buildMetricRow('Desviación (SD)', item.sd, 'valor'),
          _buildMetricRow('Muestras', item.countMuestras?.toDouble(), 'entero'),
          const SizedBox(height: 12),

          // === Niveles S ===
          const Text(
            'Niveles (S1 – S6)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: List.generate(6, (i) {
              final valor = item.nivelesS[i];
              return _buildLevelBadge('S${i + 1}', valor);
            }),
          ),
          const SizedBox(height: 16),

          // === Niveles T ===
          const Text(
            'Niveles (T1 – T25)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: List.generate(25, (i) {
              final valor = item.nivelesT[i];
              return _buildLevelBadge('T${i + 1}', valor);
            }),
          ),
        ],
      ),
    );
  }

  // Widget reutilizable para evitar repetición
  Widget _buildLevelBadge(String label, double? valor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: valor != null ? Colors.green.shade50 : Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: valor != null ? Colors.green.shade200 : Colors.grey.shade300,
        ),
      ),
      child: Text(
        '$label: ${valor != null ? valor.toStringAsFixed(2) : '—'}',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: valor != null ? Colors.green.shade800 : Colors.grey[700],
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, num? value, String tipo) {
    String display = value == null
        ? '—'
        : tipo == 'porcentaje'
        ? '${value.toStringAsFixed(2)}%'
        : tipo == 'entero'
        ? value.toInt().toString()
        : value.toStringAsFixed(2);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(
            display,
            style: TextStyle(
              fontWeight: value != null ? FontWeight.bold : null,
              color: value != null ? null : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
