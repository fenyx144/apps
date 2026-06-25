import 'package:flutter/material.dart';
import 'package:gc_puesto_mercado_tienda/utils/toast_helper.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

import '../utils/constants.dart';
import '../widgets/app_bar.dart';
import '../widgets/app_drawer.dart';
import '../widgets/seguimiento_envio_modal.dart';

class SeguimientoEnvioScreen extends StatefulWidget {
  const SeguimientoEnvioScreen({super.key});

  @override
  State<SeguimientoEnvioScreen> createState() => _SeguimientoEnvioScreenState();
}

class _SeguimientoEnvioScreenState extends State<SeguimientoEnvioScreen>
    with TickerProviderStateMixin {
  final TextEditingController _orderNumberController = TextEditingController();

  // Estado para los datos de la orden

  String _selectedYear = DateTime.now().year.toString().substring(2);
  // Estado para el selector de receptor

  // Controlador del escáner
  QRViewController? _controller;

  // Estado para saber si el escáner está activo
  bool _isScanning = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // Inicia en la pestaña "N° de orden" (índice 1)
    _tabController = TabController(length: 2, initialIndex: 0, vsync: this);
    _tabController.addListener(() {
      // Pausar la cámara cuando se cambia de pestaña
      if (_tabController.index != 0 && _isScanning) {
        _stopScanning();
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    _tabController.dispose();
    super.dispose();
  }

  List<DropdownMenuItem<String>> _buildYearItems() {
    final currentYear = DateTime.now().year;
    final years = List.generate(
      4,
      (index) => currentYear - index,
    ); // [2026, 2025, 2024, 2023]
    return years.map((year) {
      final twoDigit = year.toString().substring(2); // "2026" → "26"
      return DropdownMenuItem<String>(value: twoDigit, child: Text(twoDigit));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildAppBar(
        context,
        'Seguimiento de envíos',
        appIcon: Icons.local_shipping_outlined,
      ),
      drawer: const AppDrawer(),
      body: Padding(
        padding: EdgeInsets.only(
          left: 16.0,
          right: 16.0,
          top: 16.0,
          bottom: MediaQuery.paddingOf(context).bottom + 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pestañas
            TabBar(
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
                Tab(text: 'Cámara'),
                Tab(text: 'N° de orden'),
              ],
              dividerHeight: 0,
            ),
            const SizedBox(height: 24),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_buildCameraTab(), _buildOrderNumberTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: _isScanning
                ? Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: QRView(
                      key:
                          GlobalKey(), // No necesitas key global si no la usas externamente
                      onQRViewCreated: _onQRViewCreated,
                      overlay: QrScannerOverlayShape(
                        borderColor: const Color(0xFF667EEA),
                        borderRadius: 10,
                        borderLength: 30,
                        borderWidth: 10,
                        cutOutSize: MediaQuery.of(context).size.width * 0.6,
                      ),
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text(
                        'Presiona "Iniciar Escaneo" para activar la cámara',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isScanning
                    ? [
                        Color(0xFFE53935),
                        Color(0xFFB71C1C),
                      ] // Rojo intenso → rojo oscuro
                    : [
                        Color(0xFF4CAF50),
                        Color(0xFF2E7D32),
                      ], // Verde fresco → verde oscuro
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(11),
              boxShadow: [
                BoxShadow(
                  color:
                      (_isScanning
                              ? const Color(0xFFE53935)
                              : const Color(0xFF4CAF50))
                          .withOpacity(0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: InkWell(
              onTap: () {
                if (_isScanning) {
                  _stopScanning();
                } else {
                  _startScanning();
                }
              },
              borderRadius: BorderRadius.circular(11),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isScanning ? Icons.stop : Icons.play_arrow,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isScanning ? 'Detener Escaneo' : 'Iniciar Escaneo',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderNumberTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ingrese el número de orden',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        // Envuelve el Row en un SizedBox con ancho máximo
        SizedBox(
          width: double.infinity,
          child: Row(
            children: [
              // Prefijo "SAN-" - ahora con altura consistente
              Container(
                constraints: const BoxConstraints(
                  minHeight: 48, // Misma altura que el TextField
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'SAN-',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              // Selector de año (con altura fija y color de texto corregido)
              Container(
                width: 60,
                height: 48, // Misma altura que el TextField
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: ButtonTheme(
                    alignedDropdown: true,
                    child: DropdownButton<String>(
                      value: _selectedYear,
                      items: _buildYearItems()
                          .map(
                            (item) => DropdownMenuItem<String>(
                              value: item.value,
                              child: Text(
                                item.value ?? '',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black, // Color negro para texto
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedYear = value;
                          });
                        }
                      },
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down, size: 20),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black, // Color para el texto seleccionado
                      ),
                      dropdownColor:
                          Colors.white, // Fondo blanco para el dropdown
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Campo de número de orden
              Expanded(
                child: SizedBox(
                  height: 48, // Altura fija
                  child: TextField(
                    controller: _orderNumberController,
                    decoration: InputDecoration(
                      hintText: '0001',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Botón de búsqueda - con altura fija
              SizedBox(
                height: 48, // Misma altura que los demás
                child: ElevatedButton.icon(
                  onPressed: _searchOrder,
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Buscar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF667EEA),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    textStyle: const TextStyle(fontSize: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _onQRViewCreated(QRViewController controller) {
    _controller = controller;

    // Solo escuchar si estamos en modo escaneo (por seguridad)
    controller.scannedDataStream.listen((scanData) {
      if (scanData.code != null && _isScanning) {
        _searchOrder(scanData.code);
      }
    });
  }

  void _startScanning() {
    setState(() {
      _isScanning = true;
    });
    // La cámara se activará automáticamente porque QRView se construye ahora
  }

  void _stopScanning() {
    // Liberar recursos de la cámara
    _controller?.dispose();
    _controller = null;

    setState(() {
      _isScanning = false;
    });
  }

  Future<void> _searchOrder([String? scannedCode]) async {
    FocusManager.instance.primaryFocus?.unfocus();

    if (_isScanning) {
      _stopScanning();
    }

    String codigoCompleto = scannedCode ?? '';
    if (scannedCode == null) {
      final number = _orderNumberController.text.trim();
      if (number.isEmpty) {
        showErrorToast(context, 'Por favor, ingrese el número de orden.');
        return;
      }
      codigoCompleto = 'SAN-0$_selectedYear$number';
    }

    try {
      final response = await http.post(
        Uri.parse(
          '${AppConstants.baseUrl}/modules/tracking/seguimiento_envios/tracking_envio.php',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'codigo': codigoCompleto}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] == true) {
          _showModal(data['envio'], data['historial']);
        } else {
          showErrorToast(context, 'Orden no encontrada.');
        }
      } else {
        throw Exception('Error en la red');
      }
    } catch (e) {
      showErrorToast(context, 'Error al conectar con el servidor.');
    }
  }

  void _showModal(Map<String, dynamic> envio, List<dynamic> historial) {
    showDialog(
      context: context,
      builder: (context) =>
          SeguimientoEnvioModal(envio: envio, historial: historial),
    );
  }
}
