import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import '../controllers/registro_envio_muestra_controller.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';
import '../utils/toast_helper.dart';

class ResumenModal extends StatefulWidget {
  final RegistroEnvioMuestraController controller;
  final VoidCallback? onGuardarExitoso;

  const ResumenModal({
    super.key,
    required this.controller,
    this.onGuardarExitoso,
  });

  @override
  State<ResumenModal> createState() => _ResumenModalState();
}

class _ResumenModalState extends State<ResumenModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  PdfControllerPinch? _pdfController;
  bool _loadingPdf = true;
  String? _pdfError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPreviewPdf();
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPreviewPdf() async {
    setState(() {
      _loadingPdf = true;
      _pdfError = null;
    });

    _pdfController?.dispose();
    _pdfController = null;

    try {
      final bytes = await ApiService().downloadPreviewPdf(
        widget.controller.buildPreviewFormFields(),
      );

      if (bytes == null || bytes.isEmpty) {
        setState(() {
          _pdfError = 'No se pudo generar la vista previa del PDF';
          _loadingPdf = false;
        });
        return;
      }

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/preview_envio_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      await file.writeAsBytes(bytes);

      final controller = PdfControllerPinch(
        document: PdfDocument.openFile(file.path),
      );

      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _pdfController = controller;
        _loadingPdf = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pdfError = 'Error al cargar PDF: $e';
        _loadingPdf = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final laboratorios = controller.laboratorios;
    final empresas = controller.empresasTransporte;

    String nombreLaboratorio(String codigo) {
      final item = laboratorios.firstWhere(
        (lab) => lab['codigo'].toString() == codigo,
        orElse: () => {'nombre': '—'},
      );
      return item['nombre'] as String;
    }

    String nombreEmpresa(String codigo) {
      final item = empresas.firstWhere(
        (emp) => emp['codigo'].toString() == codigo,
        orElse: () => {'nombre': '—'},
      );
      return item['nombre'] as String;
    }

    final cabeceraItems = [
      _buildResumenItem('Código de Envío', controller.codigoEnvio),
      _buildResumenItem(
        'Fecha de Envío',
        controller.fechaEnvio.split('-').reversed.join('-'),
      ),
      _buildResumenItem('Hora de Envío', controller.horaEnvio),
      _buildResumenItem(
        'Laboratorio',
        nombreLaboratorio(controller.laboratorioId),
      ),
      _buildResumenItem(
        'Empresa de Transporte',
        nombreEmpresa(controller.empresaTransporteId),
      ),
      _buildResumenItem('Usuario Registrador', controller.usuarioRegistrador),
      _buildResumenItem('Usuario Responsable', controller.usuarioResponsable),
      _buildResumenItem('Autorizado por', controller.autorizadoPor),
    ];

    final sheetHeight = MediaQuery.of(context).size.height * 0.88;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom,
      ),
      child: SizedBox(
        height: sheetHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Resumen del Envío',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF667EEA),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFF667EEA),
              tabs: const [
                Tab(text: 'Datos'),
                Tab(text: 'Vista PDF'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Información General',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...cabeceraItems,
                        const SizedBox(height: 16),
                        const Text(
                          'Solicitudes',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (var i = 0; i < controller.numeroSolicitudes; i++)
                          _buildSolicitudResumen(controller, i),
                      ],
                    ),
                  ),
                  _buildPdfTab(),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Editar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final guardadoExitoso = await controller.guardar();
                        if (guardadoExitoso) {
                          if (!context.mounted) return;
                          showSuccessToast(
                            context,
                            'Registro guardado localmente',
                          );
                          widget.onGuardarExitoso?.call();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF667EEA),
                      ),
                      child: const Text('Confirmar'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfTab() {
    if (_loadingPdf) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_pdfError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_pdfError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _loadPreviewPdf,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_pdfController == null) {
      return const Center(child: Text('Sin vista previa disponible'));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'Pellizca para hacer zoom',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ),
        Expanded(
          child: PdfViewPinch(
            controller: _pdfController!,
            padding: 8,
            scrollDirection: Axis.vertical,
          ),
        ),
      ],
    );
  }

  Widget _buildResumenItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSolicitudResumen(
    RegistroEnvioMuestraController controller,
    int index,
  ) {
    final muestra = controller.solicitudes[index];
    final config = controller.getConfiguracion(index);
    final tipoMuestraNombre = config?.tipoMuestra['nombre'] ?? '—';
    final origenLabel = controller.getEtiquetaOrigen(muestra.origenMuestra);
    final codigoRef = controller.getCodigoReferenciaFinal(index);
    final griEtiqueta = controller.getGriEtiqueta(index);
    final observaciones = muestra.observaciones;
    final Map<String, List<String>> analisisPorPaquete = {};

    for (final analisis in muestra.analisisSeleccionados) {
      final paqueteNombre = analisis.paqueteNombre.isEmpty
          ? 'Sin paquete'
          : analisis.paqueteNombre;
      analisisPorPaquete.putIfAbsent(paqueteNombre, () => []);
      analisisPorPaquete[paqueteNombre]!.add(analisis.analisisNombre);
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Solicitud #${index + 1}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          _buildResumenItem('Tipo de Muestra', tipoMuestraNombre),
          _buildResumenItem('Origen', origenLabel),
          _buildResumenItem('Código de Referencia', codigoRef),
          _buildResumenItem('N° Muestras', muestra.numeroMuestras.toString()),
          if (controller.necesitaGri(index) && griEtiqueta.isNotEmpty)
            _buildResumenItem('GRI', griEtiqueta),
          if (analisisPorPaquete.isNotEmpty)
            ...analisisPorPaquete.entries.map(
              (entry) => _buildResumenItem(
                entry.key,
                entry.value.join(', '),
              ),
            ),
          if (observaciones.isNotEmpty)
            _buildResumenItem('Observaciones', observaciones),
        ],
      ),
    );
  }
}
