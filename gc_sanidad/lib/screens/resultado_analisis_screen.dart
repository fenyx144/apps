// screens/resultado_analisis_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/resultado_analisis_controller.dart';
import '../screens/resultado_solicitud_screen.dart';
import '../utils/constants.dart';
import '../widgets/app_drawer.dart';
import '../widgets/app_bar.dart';

class ResultadoAnalisisScreen extends StatefulWidget {
  const ResultadoAnalisisScreen({super.key});

  @override
  State<ResultadoAnalisisScreen> createState() =>
      _ResultadoAnalisisScreenState();
}

class _ResultadoAnalisisScreenState extends State<ResultadoAnalisisScreen> {
  late ResultadoAnalisisController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ResultadoAnalisisController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.cargarGrupos();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildEstadoIcon(String estado) {
    return Icon(
      estado == 'completado' ? Icons.check_circle : Icons.hourglass_empty,
      color: estado == 'completado' ? Colors.green : Colors.orange,
      size: 18,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Consumer<ResultadoAnalisisController>(
        builder: (context, controller, child) {
          return Scaffold(
            backgroundColor: const Color(0xFFF5F9FD),
            appBar: buildAppBar(context, 'Respuesta de Laboratorio', appIcon: Icons.science),
            drawer: const AppDrawer(),
            body: SafeArea(
              top: false, // el AppBar ya maneja el padding superior
              bottom: true,
              child: Column(
                children: [
                  _buildFilters(controller),
                  const SizedBox(height: 16),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () => controller.cargarGrupos(limpiar: true),
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification.metrics.extentAfter < 500 &&
                              !controller.isLoading &&
                              controller.hasMore) {
                            controller.cargarGrupos();
                          }
                          return false;
                        },
                        child: ListView.builder(
                          padding: EdgeInsets.fromLTRB(
                            12,
                            0,
                            12,
                            MediaQuery.of(context).padding.bottom + 12,
                          ),
                          itemCount:
                              controller.grupos.length +
                              (controller.hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= controller.grupos.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }

                            final grupo = controller.grupos[index];

                            // Determinar el color del borde: verde si ambos están completos, sino naranja
                            final colorBorde = grupo.estaCompleto
                                ? Colors.green
                                : Colors.orange;

                            return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ResultadoSolicitudScreen(
                                      codEnvio: grupo.codEnvio,
                                      posSolicitud: grupo.posSolicitud,                                    
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border(
                                    left: BorderSide(
                                      color: colorBorde,
                                      width: 4,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Código de Envío: ${grupo.codEnvio}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Solicitud: ${grupo.posSolicitud}',
                                      style: const TextStyle(color: Colors.grey),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Text('Cualitativo: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                                        _buildEstadoIcon(grupo.estadoCualitativo),
                                        const SizedBox(width: 16),
                                        Text('Cuantitativo: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                                        _buildEstadoIcon(grupo.estadoCuantitativo),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      grupo.estaCompleto ? '✅ Completado' : '⚠️ Pendiente',
                                      style: TextStyle(
                                        color: colorBorde,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: const [
                                        Text('Ver detalles', style: TextStyle(color: Colors.blue, fontSize: 12)),
                                        Icon(
                                          Icons.arrow_forward_ios,
                                          size: 14,
                                          color: Colors.blue,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: Builder(
            builder: (context) => IconButton(
              icon: Icon(Icons.menu_rounded, color: Colors.white),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.checklist,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Respuesta de Laboratorio',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters(ResultadoAnalisisController controller) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F9FD),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(
              hintText: 'Buscar por código de envío...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => controller.setBusqueda(v),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildFiltroButton(controller, 'todos', 'Todos'),
              _buildFiltroButton(controller, 'pendiente', 'Pendientes'),
              _buildFiltroButton(controller, 'completado', 'Completos'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFiltroButton(
    ResultadoAnalisisController controller,
    String valor,
    String texto,
  ) {
    final isActive = controller.filtroEstado == valor;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive ? Colors.blue : Colors.grey.shade200,
        foregroundColor: isActive ? Colors.white : Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      onPressed: () => controller.setFiltro(valor),
      child: Text(texto, style: const TextStyle(fontSize: 12)),
    );
  }
}