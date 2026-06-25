import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gc_puesto_mercado_tienda/utils/toast_helper.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:url_launcher/url_launcher.dart';

import '../services/storage_service.dart';
import '../widgets/app_drawer.dart';
import '../utils/constants.dart';
import '../services/api_service.dart';
import '../widgets/app_bar.dart';

class ListadoEnviosScreen extends StatefulWidget {
  const ListadoEnviosScreen({super.key});

  @override
  State<ListadoEnviosScreen> createState() => _ListadoEnviosScreenState();
}

class _ListadoEnviosScreenState extends State<ListadoEnviosScreen> {
  final TextEditingController _searchController = TextEditingController();
  int _currentPage = 1;
  int _totalPages = 1;
  List<Map<String, dynamic>> _envios = [];
  bool _isLoading = false;
  String? _error;

  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _fetchEnvios();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_searchController.text.trim().isEmpty && _currentPage == 1) return;
    setState(() {
      _currentPage = 1;
    });
    _fetchEnvios();
  }

  Future<void> _fetchEnvios() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final query = _searchController.text.trim();

      // ✅ Construcción correcta de la URL, como en downloadCatalogos
      final url = Uri.parse('${AppConstants.baseUrlSanidad}/listar_envios.php')
          .replace(
            queryParameters: {
              if (query.isNotEmpty) 'q': query,
              'page': '$_currentPage',
            },
          );

      final response = await _apiService.getWithToken(url.toString());

      if (response['success'] == true) {
        final data = response['data'] as List?;
        final totalPages = response['total_pages'] as int? ?? 1;

        setState(() {
          _envios = (data ?? []).map((e) => e as Map<String, dynamic>).toList();
          _totalPages = totalPages;
        });
      } else {
        setState(() {
          _error = response['message'] ?? 'Error al cargar los registros';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error de conexión: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _launchPdf(String modo, String codigoEnvio) async {
    final baseUrl = AppConstants.baseUrlSanidad;
    final filename = modo == 'tabla'
        ? 'generar_pdf.php'
        : 'generar_pdf_resumen.php';

    // Construye la URL completa
    final uri = Uri.parse(
      '$baseUrl/$filename',
    ).replace(queryParameters: {'codigo': codigoEnvio});

    try {
      // Intenta lanzar en el navegador del sistema
      await launchUrl(
        uri,
        mode: LaunchMode
            .externalApplication, // ← Esto fuerza abrir en navegador externo
      );
    } catch (e) {
      showErrorToast(context, 'No se pudo abrir el PDF');
    }
  }

  Future<void> _launchQr(String codigoEnvio) async {
    final baseUrl = AppConstants.baseUrlSanidad;
    final filename = 'generar_qr_code.php';
    print('codigoEnvio: $codigoEnvio');
    // Construye la URL completa
    final uri = Uri.parse(
      '$baseUrl/$filename',
    ).replace(queryParameters: {'codigo': codigoEnvio});

    try {
      // Abre en navegador externo (asumiendo que genera una página con el QR)
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      showErrorToast(context, 'No se pudo abrir el código QR');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FD),
      appBar: buildAppBar(context, 'Reportes', appIcon: Icons.bar_chart_outlined),
      drawer: const AppDrawer(),
      body: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar por código de envío',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.grey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF667EEA),
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF667EEA)),
                  )
                : _error != null
                ? Center(
                    child: Text(
                      '⚠️ $_error',
                      style: const TextStyle(color: Colors.red),
                    ),
                  )
                : _envios.isEmpty
                ? const Center(child: Text('No se encontraron registros.'))
                : RefreshIndicator(
                    onRefresh: () async => _fetchEnvios(),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _envios.length,
                      itemBuilder: (context, index) {
                        final envio = _envios[index];
                        return _buildReportCard(envio);
                      },
                    ),
                  ),
          ),
            if (_totalPages > 1) _buildPagination(),
          ],
        ),
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> envio) {
    final codigoEnvio = envio['codigoEnvio'] as String;
    final fechaOriginal = envio['fechaEnvio'] as String;
    final hora = envio['horaEnvio'] as String;
    final laboratorio = envio['laboratorio'] as String;

    // Formatear fecha
    String fechaFormateada = _formatDate(fechaOriginal);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  codigoEnvio,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF667EEA),
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildInfoRow(
            'Fecha y Hora',
            '$fechaFormateada - ${hora.substring(0, 5)}',
          ),
          _buildInfoRow('Laboratorio', laboratorio),
          _buildInfoRow('Código de Envío', codigoEnvio),
          const SizedBox(height: 16),
          // === Botones compactos ===
          // === Botones en 2x2 con Expanded ===
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.picture_as_pdf,
                      label: 'Tabla',
                      color: const Color(0xFF667EEA),
                      onPressed: () => _launchPdf('tabla', codigoEnvio),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.description,
                      label: 'Resumen',
                      color: const Color(0xFF4ECDC4),
                      onPressed: () => _launchPdf('resumen', codigoEnvio),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.email,
                      label: 'Correo',
                      color: const Color(0xFFFF6B6B),
                      onPressed: () => _mostrarModalEnviarCorreo(codigoEnvio),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.qr_code,
                      label: 'QR',
                      color: Colors.green,
                      onPressed: () => _launchQr(codigoEnvio),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Botón compacto y estilizado
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(fontSize: 12, color: color)),
      style: OutlinedButton.styleFrom(
        backgroundColor: color.withOpacity(
          0.1,
        ), // ✅ más claro (0.1 en lugar de 0.15)
        side: BorderSide(
          color: color.withOpacity(0.3),
          width: 1,
        ), // ✅ borde suave
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        foregroundColor: color, // para compatibilidad
      ),
    );
  }

  // Formatear fecha
  String _formatDate(String fecha) {
    try {
      if (fecha.length >= 10) {
        final p = fecha.split('-');
        if (p.length == 3) return '${p[2]}-${p[1]}-${p[0]}';
      }
    } catch (_) {}
    return fecha;
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Botón Anterior (solo ícono)
          IconButton(
            onPressed: _currentPage > 1
                ? () => _goToPage(_currentPage - 1)
                : null,
            icon: Icon(
              Icons.chevron_left,
              size: 20,
              color: _currentPage > 1 ? const Color(0xFF667EEA) : Colors.grey,
            ),
          ),
          // Indicador de página
          Text(
            '$_currentPage / $_totalPages',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          // Botón Siguiente (solo ícono)
          IconButton(
            onPressed: _currentPage < _totalPages
                ? () => _goToPage(_currentPage + 1)
                : null,
            icon: Icon(
              Icons.chevron_right,
              size: 20,
              color: _currentPage < _totalPages
                  ? const Color(0xFF667EEA)
                  : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  void _goToPage(int page) {
    setState(() {
      _currentPage = page;
    });
    _fetchEnvios();
  }

  Future<void> _mostrarModalEnviarCorreo(String codigoEnvio) async {
    final storage = Provider.of<StorageService>(Get.context!, listen: false);
    final usuario = storage.getUserCodeSync() ?? '';
    if (usuario == null || usuario.isEmpty) {
      showErrorToast(context, 'Usuario no autenticado');
      return;
    }
    Get.to(EnviarCorreoWidget(codigoEnvio: codigoEnvio, usuario: usuario));   
  }
}

class EnviarCorreoWidget extends StatefulWidget {
  final String codigoEnvio;
  final String usuario;

  const EnviarCorreoWidget({
    super.key,
    required this.codigoEnvio,
    required this.usuario,
  });

  @override
  State<EnviarCorreoWidget> createState() => _EnviarCorreoWidgetState();
}

class _EnviarCorreoWidgetState extends State<EnviarCorreoWidget> {
  final TextEditingController _asuntoController = TextEditingController();
  final TextEditingController _mensajeController = TextEditingController();
  final FocusNode _asuntoFocus = FocusNode();
  final FocusNode _mensajeFocus = FocusNode();

  List<String> _destinatarios = [];
  List<File> _archivosAdicionales = [];

  List<Map<String, String>> _contactos = [];
  bool _isLoading = false;
  bool _isLoadingContactos = true;

  @override
  void initState() {
    super.initState();
    _cargarContactos();
  }

  @override
  void dispose() {
    _asuntoController.dispose();
    _mensajeController.dispose();
    _asuntoFocus.dispose();
    _mensajeFocus.dispose();
    super.dispose();
  }

  Future<void> _cargarContactos() async {
    try {
      final uri = Uri.parse(
        '${AppConstants.baseUrlSanidad}/obtener_contactos.php',
      ).replace(queryParameters: {'usuario': widget.usuario});

      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final contactos = data
            .where((item) => item is Map<String, dynamic>)
            .map(
              (item) => {
                'contacto': item['contacto'] as String? ?? '',
                'correo': item['correo'] as String? ?? '',
              },
            )
            .where((c) => c['correo'] != null && c['correo']!.isNotEmpty)
            .toList();

        if (mounted) {
          setState(() {
            _contactos = contactos.cast<Map<String, String>>();
            _isLoadingContactos = false;
          });
        }
      } else {
        throw Exception('Error al cargar contactos');
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context, 'Error al cargar contactos');
        setState(() {
          _isLoadingContactos = false;
        });
      }
    }
  }

  Future<void> _launchPdf(String modo, String codigoEnvio) async {
    final baseUrl = AppConstants.baseUrlSanidad;
    final filename = modo == 'tabla'
        ? 'generar_pdf.php'
        : 'generar_pdf_resumen.php';

    final uri = Uri.parse(
      '$baseUrl/$filename',
    ).replace(queryParameters: {'codigo': codigoEnvio});

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!context.mounted) return;
      showErrorToast(context, 'No se pudo abrir el PDF');
    }
  }

  void _agregarDestinatario(String email) {
    if (email.trim().isEmpty || _destinatarios.contains(email)) return;
    setState(() {
      _destinatarios.add(email);
    });
  }

  void _eliminarDestinatario(String email) {
    setState(() {
      _destinatarios.remove(email);
    });
  }

  Future<void> _adjuntarArchivos() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );

    if (result != null) {
      final files = result.files
          .where((file) => file.path != null)
          .map((file) => File(file.path!))
          .toList();

      if (files.isNotEmpty) {
        setState(() {
          _archivosAdicionales.addAll(files);
        });
      }
    }
  }

  void _eliminarArchivoAdicional(int index) {
    setState(() {
      _archivosAdicionales.removeAt(index);
    });
  }

 Future<void> _enviarCorreo() async {
  final asunto = _asuntoController.text.trim();
  final mensaje = _mensajeController.text.trim();
  final destinatarios = _destinatarios;

  if (asunto.isEmpty || mensaje.isEmpty || destinatarios.isEmpty) {
    showErrorToast(context, 'Completa todos los campos obligatorios');
    return;
  }

  setState(() {
    _isLoading = true;
  });

  try {
    final uri = Uri.parse(
      '${AppConstants.baseUrlSanidad}/enviar_correo_reporte.php',
    );
    final request = http.MultipartRequest('POST', uri);

    // Campos obligatorios
    request.fields['usuario'] = widget.usuario;
    request.fields['subject'] = asunto;
    request.fields['body'] = mensaje;
    request.fields['codigo'] = widget.codigoEnvio;

    // Agregar destinatarios
    for (final email in destinatarios) {
      request.fields['para[]'] = email;
    }

    // Archivos adicionales (el PDF principal lo genera el backend)
    for (final file in _archivosAdicionales) {
      request.files.add(
        await http.MultipartFile.fromPath('archivos_adjuntos[]', file.path),
      );
    }

    debugPrint('=== INICIANDO ENVÍO DE CORREO ===');
    debugPrint('URL: ${uri.toString()}');
    debugPrint('Usuario: ${widget.usuario}');
    debugPrint('Código: ${widget.codigoEnvio}');
    debugPrint('Destinatarios: ${destinatarios.join(", ")}');

    final streamResponse = await request.send();
    
    // Obtener el código de estado HTTP
    final statusCode = streamResponse.statusCode;
    debugPrint('Status Code: $statusCode');
    
    // Leer la respuesta completa como string
    final respStr = await streamResponse.stream.bytesToString();
    
    // IMPRIMIR LA RESPUESTA COMPLETA ANTES DE PARSEAR
    debugPrint('=== RESPUESTA COMPLETA DEL SERVIDOR ===');
    debugPrint('Longitud: ${respStr.length} caracteres');
    debugPrint('Primeros 500 caracteres: ${respStr.substring(0, respStr.length > 500 ? 500 : respStr.length)}');
    debugPrint('Respuesta completa:');
    debugPrint(respStr);
    debugPrint('=== FIN RESPUESTA ===');
    
    // Verificar si la respuesta es JSON válido
    if (respStr.trim().isEmpty) {
      throw Exception('Respuesta vacía del servidor');
    }
    
    // Intentar parsear como JSON
    dynamic response;
    try {
      response = jsonDecode(respStr);
      debugPrint('JSON parseado exitosamente:');
      debugPrint(response.toString());
    } catch (e) {
      debugPrint('ERROR AL PARSEAR JSON: $e');
      debugPrint('La respuesta no es JSON válido. Contenido:');
      debugPrint(respStr);
      throw Exception('El servidor no devolvió JSON válido. Respuesta: ${respStr.substring(0, 200)}...');
    }
    
    if (response['success'] == true) {
      if (!context.mounted) return;
      showSuccessToast(context, response['message'] ?? 'Correo enviado con éxito');
    } else {
      throw Exception(response['message'] ?? 'Error desconocido');
    }
  } catch (e) {
    debugPrint('=== ERROR CAPTURADO ===');
    debugPrint('Tipo: ${e.runtimeType}');
    debugPrint('Mensaje: ${e.toString()}');
    if (e is FormatException) {
      debugPrint('Es un FormatException - El servidor probablemente devolvió HTML en lugar de JSON');
    }
    debugPrint('Stack trace:');
    debugPrint(StackTrace.current.toString());
    
    if (!context.mounted) return;
    showErrorToast(context, 'Error al enviar: ${e.toString()}');
  } finally {
    if (context.mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }
}
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FD),
      appBar: buildAppBar(
        context,
        'Enviar Reporte por Correo',
        appIcon: Icons.email,
        showBackButton: true,
      ),
     
      body: Padding(
        padding: EdgeInsets.only(
          left: 16.0,
          right: 16.0,
          top: 16.0,
          bottom: MediaQuery.paddingOf(context).bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Destinatarios
              const Text(
                'Para *',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 6,
                  horizontal: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ..._destinatarios.map((email) {
                      return Chip(
                        label: Text(email),
                        onDeleted: () => _eliminarDestinatario(email),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        backgroundColor: Colors.blue.withOpacity(0.1),
                        labelStyle: const TextStyle(
                          color: Colors.blue,
                          fontSize: 12,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                      );
                    }),
                    if (_destinatarios.isEmpty)
                      const Text(
                        'Ningún destinatario',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Selector de contactos guardados
              if (!_isLoadingContactos && _contactos.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Contactos guardados',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _contactos.map((c) {
                        final nombre = c['contacto']!;
                        final correo = c['correo']!;
                        final etiqueta = nombre.isNotEmpty
                            ? '$nombre <$correo>'
                            : correo;

                        return ActionChip(
                          label: Text(
                            etiqueta,
                            style: const TextStyle(fontSize: 12),
                          ),
                          onPressed: () => _agregarDestinatario(correo),
                          backgroundColor: Colors.grey.shade100,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),

              // Mientras carga
              if (_isLoadingContactos)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: CircularProgressIndicator()),
                ),

              // Asunto
              TextField(
                controller: _asuntoController,
                focusNode: _asuntoFocus,
                decoration: _textFieldDecoration(
                  'Asunto *',
                  _asuntoFocus.hasFocus,
                ),
              ),
              const SizedBox(height: 16),

              // Mensaje
              TextField(
                controller: _mensajeController,
                focusNode: _mensajeFocus,
                maxLines: 5,
                decoration: _textFieldDecoration(
                  'Mensaje *',
                  _mensajeFocus.hasFocus,
                ),
              ),
              const SizedBox(height: 16),

              // Archivos adjuntos
              _buildAdjuntosSection(),

              const SizedBox(height: 24),

              // Botón enviar
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _enviarCorreo,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Enviar correo',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _textFieldDecoration(String label, bool focused) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.grey),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.grey, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.blue, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );
  }

  Widget _buildAdjuntosSection() {
    final nombrePdf = 'Reporte_${widget.codigoEnvio}.pdf';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Archivos adjuntos',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),

        // PDF predeterminado
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              const Icon(Icons.picture_as_pdf, color: Colors.red),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  nombrePdf,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove_red_eye, size: 18),
                onPressed: () => _launchPdf('tabla', widget.codigoEnvio),
                splashRadius: 20,
              ),
            ],
          ),
        ),

        // Archivos adicionales
        if (_archivosAdicionales.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (int i = 0; i < _archivosAdicionales.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.insert_drive_file, color: Colors.grey),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _archivosAdicionales[i].path.split('/').last,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Colors.red),
                    onPressed: () => _eliminarArchivoAdicional(i),
                    splashRadius: 20,
                  ),
                ],
              ),
            ),
        ],

        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _adjuntarArchivos,
          icon: const Icon(Icons.attach_file, color: Colors.grey),
          label: const Text(
            'Adjuntar otros archivos',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      ],
    );
  }
}
