import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/registro_envio_muestra_controller.dart';
import '../services/catalog_service.dart';
import '../services/storage_service.dart';
import '../utils/toast_helper.dart';
import '../widgets/app_bar.dart';
import '../widgets/solicitud_muestra_card.dart';
import '../widgets/resumen_modal.dart';
import '../widgets/app_drawer.dart';
import '../utils/constants.dart';
import '../widgets/app_bar.dart';

class RegistroEnvioMuestraScreen extends StatefulWidget {
  const RegistroEnvioMuestraScreen({super.key});

  @override
  State<RegistroEnvioMuestraScreen> createState() =>
      _RegistroEnvioMuestraScreenState();
}

class _RegistroEnvioMuestraScreenState
    extends State<RegistroEnvioMuestraScreen> {
  Object _providerKey = GlobalKey();
  late RegistroEnvioMuestraController controller;
  int _currentIndex = 0;
  String _numeroSolicitudesTemp = '';
  late TextEditingController _responsableController;
  late TextEditingController _autorizadoController;
  late TextEditingController _numeroSolicitudesController;

  @override
  void initState() {
    super.initState();

    final catalogService = context.read<CatalogService>();
    final storageService = context.read<StorageService>();

    final tiposMuestra =
        catalogService.catalogos['muestras'] as List<dynamic>? ?? [];
    final laboratorios =
        catalogService.catalogos['laboratorios'] as List<dynamic>? ?? [];
    final empresasTransporte =
        catalogService.catalogos['emp_trans'] as List<dynamic>? ?? [];

    final now = DateTime.now();
    final fechaEnvio =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final horaEnvio =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final usuarioRegistrador = storageService.getUserCodeSync() ?? 'user';

    controller = RegistroEnvioMuestraController(
      fechaEnvio: fechaEnvio,
      horaEnvio: horaEnvio,
      usuarioRegistrador: usuarioRegistrador,
      tiposMuestra: tiposMuestra.cast<Map<String, dynamic>>(),
      laboratorios: laboratorios.cast<Map<String, dynamic>>(),
      empresasTransporte: empresasTransporte.cast<Map<String, dynamic>>(),
    );
    _responsableController = TextEditingController(
      text: controller.usuarioResponsable,
    );
    _autorizadoController = TextEditingController(
      text: controller.autorizadoPor,
    );
    _numeroSolicitudesController = TextEditingController(
      text: controller.numeroSolicitudes == 0
          ? ''
          : controller.numeroSolicitudes.toString(),
    );
  }

  @override
  void dispose() {
    _responsableController.dispose();
    _autorizadoController.dispose();
    _numeroSolicitudesController.dispose();
    super.dispose();
  }

  Future<bool> _hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    }
  }

  Future<void> _refreshData() async {
    final catalogService = context.read<CatalogService>();
    final storageService = context.read<StorageService>();

    bool hasInternet = await _hasInternetConnection();

    if (hasInternet) {
      await catalogService.downloadCatalogos(
        tablas: [
          'laboratorios',
          'emp_trans',
          'muestras',
          'paquetes',
          'analisis',
          
        ],
      );
    } else {
      await catalogService.loadFromPrefs();
    }

    _limpiarFormulario();    
  }

  TimeOfDay? parseTimeOfDay(String? timeString) {
    if (timeString == null || timeString.isEmpty) return null;
    final parts = timeString.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      key: ValueKey(_providerKey),
      value: controller,
      child: Consumer<RegistroEnvioMuestraController>(
        builder: (context, controller, child) {
          final laboratorios = controller.laboratorios;
          final empresas = controller.empresasTransporte;
          return Scaffold(
            backgroundColor: const Color(0xFFF5F9FD),
            appBar: buildAppBar(context, 'Registro de Muestras', appIcon: Icons.inventory_outlined),
            drawer: const AppDrawer(),
            body: SafeArea(
              bottom:
                  false, 
              child: Column(
                children: [
                  // 👇 Zona desplazable: todo el contenido del formulario MENOS el botón
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _refreshData,
                      color: const Color(0xFF667EEA),
                      backgroundColor: Colors.white,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSection(
                              context,
                              'Información de Envío',
                              [
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildInputField(
                                        label: 'Fecha de Envío',
                                        value: controller.fechaEnvio
                                            .split('-')
                                            .reversed
                                            .join('-'),
                                        onTap: () async {
                                          final picked = await showDatePicker(
                                            context: context,
                                            initialDate:
                                                DateTime.tryParse(
                                                  controller.fechaEnvio,
                                                ) ??
                                                DateTime.now(),
                                            firstDate: DateTime(2000),
                                            lastDate: DateTime(2030),
                                          );
                                          if (picked != null) {
                                            controller.fechaEnvio =
                                                '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _buildInputField(
                                        label: 'Hora de Envío',
                                        value: controller.horaEnvio,
                                        onTap: () async {
                                          final TimeOfDay? picked =
                                              await showTimePicker(
                                                context: context,
                                                initialTime:
                                                    parseTimeOfDay(
                                                      controller.horaEnvio,
                                                    ) ??
                                                    TimeOfDay.now(),
                                              );
                                          if (picked != null) {
                                            controller.horaEnvio =
                                                '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildInputField(
                                        label: 'Código de Envío',
                                        value: controller.codigoEnvio,
                                        onChanged: null,
                                        enabled: false,
                                        textStyle: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF667EEA),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _buildInputField(
                                        label: 'Laboratorio',
                                        value: controller.laboratorioId,
                                        displayText: _getNombreFromCodigo(
                                          laboratorios,
                                          controller.laboratorioId,
                                          'nombre',
                                        ),
                                        onTap: () {
                                          _showLaboratorioDialog(
                                            context,
                                            laboratorios,
                                            controller,
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _buildSection(
                              context,
                              'Transporte y Responsables',
                              [
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildInputField(
                                        label: 'Emp. de Transporte',
                                        value: controller.empresaTransporteId,
                                        displayText: _getNombreFromCodigo(
                                          empresas,
                                          controller.empresaTransporteId,
                                          'nombre',
                                        ),
                                        onTap: () {
                                          _showEmpresaDialog(
                                            context,
                                            empresas,
                                            controller,
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _buildInputField(
                                        label: 'Usuario Registrador',
                                        value: controller.usuarioRegistrador,
                                        enabled: false,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildInputField(
                                        label: 'Responsable',
                                        textEditingController:
                                            _responsableController,
                                        onChanged: (v) =>
                                            controller.usuarioResponsable = v,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _buildInputField(
                                        label: 'Autorizado por',
                                        textEditingController:
                                            _autorizadoController,
                                        onChanged: (v) {
                                          controller.autorizadoPor = v;
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                _buildInputField(
                                  label: 'N° de Solicitudes',
                                  value: '',
                                  textEditingController:
                                      _numeroSolicitudesController,
                                  onChanged: (v) {},
                                  onSubmitted: (v) {
                                    int num = 0;
                                    if (v.isNotEmpty) {
                                      num = int.tryParse(v) ?? 0;
                                    }

                                    if (num >= 1 && num <= 20) {
                                      controller.numeroSolicitudes = num;
                                      if (_currentIndex >= num) {
                                        setState(() => _currentIndex = num - 1);
                                      }
                                      // Actualizamos el controlador con el valor válido
                                      _numeroSolicitudesController.text =
                                          num.toString();
                                    } else {
                                      controller.numeroSolicitudes = 0;
                                      showErrorToast(
                                        context,
                                        'Ingrese un número entre 1 y 20.',
                                      );
                                      _numeroSolicitudesController.text = '';
                                    }

                                    FocusScope.of(context).unfocus();
                                  },
                                  keyboardType: TextInputType.number,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (controller.numeroSolicitudes > 0 &&
                                controller.solicitudes.length >
                                    _currentIndex) ...[
                              _buildNavigation(controller, _currentIndex),
                              const SizedBox(height: 16),
                              SolicitudMuestraCard(
                                index: _currentIndex,
                                onEliminar: () => _confirmarEliminarSolicitud(
                                  context,
                                  controller,
                                  _currentIndex,
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: Colors.white.withOpacity(0.4),
                        indent: 12,
                        endIndent: 12,
                      ),
                      Padding(
                        padding: EdgeInsets.only(
                          left: 12,
                          right: 12,
                          bottom: MediaQuery.paddingOf(context).bottom + 8,
                        ),
                        child: _buildSubmitButton(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showLaboratorioDialog(
    BuildContext context,
    List<Map<String, dynamic>> laboratorios,
    RegistroEnvioMuestraController controller,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Seleccionar Laboratorio'),
        content: SizedBox(
          width: double.maxFinite,
          height: 200,
          child: SingleChildScrollView(
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: laboratorios.length,
              itemBuilder: (context, index) {
                final lab = laboratorios[index];
                final codigo = lab['codigo'].toString();
                final nombre = lab['nombre'] as String;
                return ListTile(
                  title: Text(nombre),
                  selected: controller.laboratorioId == codigo,
                  selectedTileColor: Colors.blue.withOpacity(0.1),
                  onTap: () {
                    controller.setLaboratorio(codigo, nombre);
                    Navigator.pop(ctx);
                    // 👇 Desenfocar cualquier TextField abierto
                    FocusScope.of(context).unfocus();
                  },
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              FocusScope.of(context).unfocus();
            },
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  void _showEmpresaDialog(
    BuildContext context,
    List<Map<String, dynamic>> empresas,
    RegistroEnvioMuestraController controller,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Seleccionar Empresa de Transporte'),
        content: SizedBox(
          width: double.maxFinite,
          height: 200,
          child: SingleChildScrollView(
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: empresas.length,
              itemBuilder: (context, index) {
                final emp = empresas[index];
                final codigo = emp['codigo'].toString();
                final nombre = emp['nombre'] as String;
                return ListTile(
                  title: Text(nombre),
                  selected: controller.empresaTransporteId == codigo,
                  selectedTileColor: Colors.blue.withOpacity(0.1),
                  onTap: () {
                    controller.setEmpresaTransporte(codigo, nombre);
                    Navigator.pop(ctx);
                    FocusScope.of(context).unfocus();
                  },
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              FocusScope.of(context).unfocus();
            },
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    List<Widget> fields,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          ...fields,
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      filled: true,
      fillColor: AppColors.cardBackground,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF667EEA), width: 1.5),
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    String? value,
    String? displayText,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
    VoidCallback? onTap,
    bool enabled = true,
    TextStyle? textStyle,
    TextInputType? keyboardType,
    TextEditingController? textEditingController,
  }) {
    final actualDisplayText = (displayText ?? value) ?? '';
    final hasTextField = onChanged != null || textEditingController != null;
    final hasTapAction = onTap != null;

    if (hasTextField) {
      return TextFormField(
        enabled: enabled,
        controller:
            textEditingController ?? TextEditingController(text: value ?? ''),
        onChanged: onChanged,
        onFieldSubmitted: onSubmitted,
        decoration: _fieldDecoration(label),
        style:
            textStyle ??
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        keyboardType: keyboardType,
        textInputAction: TextInputType.number == keyboardType
            ? TextInputAction.done
            : TextInputAction.next,
      );
    }

    return InkWell(
      onTap: hasTapAction ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: _fieldDecoration(label),
        child: Text(
          actualDisplayText.isEmpty ? 'Seleccionar...' : actualDisplayText,
          style:
              textStyle ??
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  String _getNombreFromCodigo(
    List<Map<String, dynamic>> lista,
    String codigo,
    String campoNombre,
  ) {
    if (codigo.isEmpty) return '';
    final item = lista.firstWhere(
      (item) => item['codigo'].toString() == codigo,
      orElse: () => {'nombre': '—'},
    );
    return item[campoNombre] as String;
  }

  Widget _buildNavigation(
    RegistroEnvioMuestraController controller,
    int currentIndex,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildCompactNavButton(
            icon: Icons.chevron_left,
            onPressed: currentIndex > 0
                ? () => setState(() => _currentIndex--)
                : null,
          ),
          Expanded(
            child: Text(
              'Solicitud ${currentIndex + 1} de ${controller.numeroSolicitudes}',
              style: const TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          if (controller.numeroSolicitudes > 1)
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: 'Eliminar solicitud',
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
              onPressed: () => _confirmarEliminarSolicitud(
                context,
                controller,
                currentIndex,
              ),
            )
          else
            const SizedBox(width: 36),
          _buildCompactNavButton(
            icon: Icons.chevron_right,
            onPressed: currentIndex < controller.numeroSolicitudes - 1
                ? () => setState(() => _currentIndex++)
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmarEliminarSolicitud(
    BuildContext context,
    RegistroEnvioMuestraController controller,
    int index,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar solicitud'),
        content: Text(
          '¿Eliminar la solicitud #${index + 1}? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    if (!controller.eliminarSolicitud(index)) {
      showErrorToast(context, 'Debe mantener al menos una solicitud.');
      return;
    }

    setState(() {
      if (_currentIndex >= controller.numeroSolicitudes) {
        _currentIndex = controller.numeroSolicitudes - 1;
      }
      _numeroSolicitudesController.text =
          controller.numeroSolicitudes.toString();
    });
  }

  Widget _buildCompactNavButton({
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      icon: Icon(icon, color: AppColors.primary),
      onPressed: onPressed,
    );
  }

  void _validarYMostrar(BuildContext context) {
    final controller = context.read<RegistroEnvioMuestraController>();

    if (!controller.esValido) {
      // Verifica campo por campo para dar mensaje útil
      if (controller.laboratorioId.isEmpty) {
        showErrorToast(context, 'Debe seleccionar un laboratorio.');
      } else if (controller.empresaTransporteId.isEmpty) {
        showErrorToast(context, 'Debe seleccionar una empresa de transporte.');
      } else if (controller.autorizadoPor.isEmpty) {
        showErrorToast(context, 'Debe ingresar quién autoriza.');
      } else if (controller.usuarioResponsable.isEmpty) {
        showErrorToast(context, 'Debe ingresar el responsable.');
      } else if (controller.numeroSolicitudes == 0) {
        showErrorToast(context, 'Debe ingresar al menos una solicitud.');
      } else {
        // Validar cada solicitud
        for (int i = 0; i < controller.numeroSolicitudes; i++) {
          final String? error = controller.obtenerErrorSolicitud(i);
          if (error != null) {
            showErrorToast(context, '📄 Solicitud ${i + 1}: $error');
            // Opcional: enfocar automáticamente esa solicitud
            setState(() {
              _currentIndex = i;
            });
            return;
          }
        }
      }
      return;
    }

    // Si todo está bien, mostrar resumen
    _showResumen(context);
  }

  Widget _buildSubmitButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF667EEA).withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: () {
            _validarYMostrar(context);
            FocusScope.of(context).unfocus();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.save_rounded, size: 20, color: Colors.white),
              SizedBox(width: 10),
              Text(
                'REGISTRAR',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _limpiarFormulario() {
    final now = DateTime.now();
    final nuevaFecha =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final nuevaHora =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final nuevoUsuario =
        context.read<StorageService>().getUserCodeSync() ?? 'user';

    // Reiniciar el controlador
    controller.reset(
      fechaEnvio: nuevaFecha,
      horaEnvio: nuevaHora,
      usuarioRegistrador: nuevoUsuario,
    );
    controller.generarCodigoEnvio();
    _responsableController.clear();
    _autorizadoController.clear();
    _numeroSolicitudesController.clear();

    // Reiniciar estado local de navegación
    setState(() {
      _currentIndex = 0;
    });
  }

  void _showResumen(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => ResumenModal(
        controller: controller,
        onGuardarExitoso: () {
          Navigator.pop(ctx); // cerrar el modal
          _limpiarFormulario();
        },
      ),
    );
  }
}
