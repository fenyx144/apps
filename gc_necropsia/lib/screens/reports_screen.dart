import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/storage_service.dart';
import '../services/report_service.dart';
import '../utils/constants.dart';
import '../utils/toast_helper.dart';
import '../utils/dialog_helper.dart';
import '../widgets/app_bar.dart';
import '../widgets/app_drawer.dart';
import 'register_necropcia_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _reportService = ReportService();
  List<Map<String, dynamic>> _necropsias = [];
  bool _isLoading = false;
  bool _isGeneratingReport = false; // Protección contra múltiples clics
  
  // Filtros de fecha
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;

  @override
  void initState() {
    super.initState();
    _loadNecropsias();
    // Pre-inicializar la librería PDF en background para evitar demoras
    _preInitializePdfLibrary();
  }

  DateTime? _getFechaRegistroDateTime(Map<String, dynamic> record) {
    final fecha =
        record['tdate_trans']?.toString() ??
        record['tdate']?.toString() ??
        record['diareg']?.toString() ??
        '';
    final hora =
        record['ttime_trans']?.toString() ??
        record['ttime']?.toString() ??
        '';

    if (fecha.isEmpty) return null;

    final timePart = hora.isNotEmpty ? hora : '00:00:00';
    try {
      return DateTime.parse('$fecha $timePart');
    } catch (_) {
      try {
        // Fallback si hora viene rara o fecha viene en ISO con T
        return DateTime.parse(fecha);
      } catch (_) {
        return null;
      }
    }
  }
  
  /// Pre-inicializa la librería PDF en background para que la primera generación sea más rápida
  void _preInitializePdfLibrary() {
    // Ejecutar en background sin bloquear la UI
    Future.microtask(() async {
      try {
        debugPrint('🔄 Pre-inicializando librería PDF en background...');
        await _reportService.initializePdfLibrary();
        debugPrint('✅ Pre-inicialización de PDF completada');
      } catch (e) {
        debugPrint('⚠️ Error pre-inicializando PDF (no crítico): $e');
      }
    });
  }

  Future<void> _loadNecropsias({bool refresh = false}) async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final storage = context.read<StorageService>();
      final allRecords = storage.getAllRecords(AppStrings.formType1);

      // Log para debugging: verificar estado de sincronización de los registros
      debugPrint('📋 _loadNecropsias - Cargando registros desde storage:');
      debugPrint('   - Total registros: ${allRecords.length}');
      for (var record in allRecords.take(3)) { // Mostrar solo los primeros 3 para no saturar
        debugPrint('   - Registro: tuuid=${record['tuuid']}, synced=${record['synced']} (tipo: ${record['synced'].runtimeType}), guardado_backend=${record['guardado_backend']}');
      }

      // Usar directamente los records (ya tienen toda la info agrupada)
      List<Map<String, dynamic>> filteredNecropsias = allRecords.where((record) {
        final numreg = record['numreg']?.toString() ?? '';
        final granja = record['granja']?.toString() ?? '';
        final galpon = record['galpon']?.toString() ?? '';
        final fectra = record['fectra']?.toString() ?? '';
        return numreg.isNotEmpty && granja.isNotEmpty && galpon.isNotEmpty && fectra.isNotEmpty;
      }).toList();

      // Aplicar filtros de fecha
      if (_fechaDesde != null) {
        filteredNecropsias = filteredNecropsias.where((record) {
          final recordDateString = record['fectra']?.toString();
          if (recordDateString == null || recordDateString.isEmpty) return false;
          try {
            final recordDate = DateTime.parse(recordDateString);
            return recordDate.isAfter(_fechaDesde!.subtract(const Duration(days: 1)));
          } catch (e) {
            return false;
          }
        }).toList();
      }
      if (_fechaHasta != null) {
        filteredNecropsias = filteredNecropsias.where((record) {
          final recordDateString = record['fectra']?.toString();
          if (recordDateString == null || recordDateString.isEmpty) return false;
          try {
            final recordDate = DateTime.parse(recordDateString);
            return recordDate.isBefore(_fechaHasta!.add(const Duration(days: 1)));
          } catch (e) {
            return false;
          }
        }).toList();
      }

      // Ordenar por fecha descendente
      filteredNecropsias.sort((a, b) {
        final aReg = _getFechaRegistroDateTime(a);
        final bReg = _getFechaRegistroDateTime(b);
        if (aReg != null && bReg != null) return bReg.compareTo(aReg);
        if (aReg != null && bReg == null) return -1;
        if (aReg == null && bReg != null) return 1;

        // Fallback: fecha de necropsia si no hay fecha de registro
        final fechaA = a['fectra']?.toString() ?? '';
        final fechaB = b['fectra']?.toString() ?? '';
        return fechaB.compareTo(fechaA);
      });

      setState(() {
        _necropsias = filteredNecropsias;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        showErrorToast(context, 'Error al cargar reportes: ${e.toString()}');
      }
    }
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: (isStartDate ? _fechaDesde : _fechaHasta) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.primary,
            ),
            dialogBackgroundColor: Colors.white,
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _fechaDesde = picked;
        } else {
          _fechaHasta = picked;
        }
        _loadNecropsias(); // Recargar con el nuevo filtro
      });
    }
  }

  Future<void> _showEditModal(Map<String, dynamic> necropsia) async {
    // SIMPLIFICADO: Usar una única bandera guardado_backend
    // Si guardado_backend == true, el registro ya existe en el backend → usar actualizar_necropsia_movil.php
    // Si guardado_backend == false o no existe, el registro es nuevo → usar guardar_necropsia_movil.php
    final guardadoBackend = necropsia['guardado_backend'];
    final bool guardadoBackendBool = guardadoBackend == true || 
                                     guardadoBackend == 'true' || 
                                     guardadoBackend == 1;

    // Crear una copia mutable de los datos para pasar al editor
    final Map<String, dynamic> initialDataForEdit = Map.from(necropsia);
    
    // Preservar guardado_backend del registro original
    if (guardadoBackendBool) {
      initialDataForEdit['guardado_backend'] = true;
    } else {
      initialDataForEdit['guardado_backend'] = false;
    }
    
    debugPrint('📝 _showEditModal - Preparando edición:');
    debugPrint('   - tuuid: ${necropsia['tuuid']}');
    debugPrint('   - guardado_backend: $guardadoBackend (tipo: ${guardadoBackend.runtimeType})');
    if (guardadoBackendBool) {
      debugPrint('   ⚠️ IMPORTANTE: Este registro ya existe en el backend (guardado_backend=true)');
      debugPrint('   → Al sincronizar, se usará actualizar_necropsia_movil.php');
    } else {
      debugPrint('   ℹ️ Este registro NO existe en el backend (guardado_backend=false)');
      debugPrint('   → Al sincronizar, se usará guardar_necropsia_movil.php');
    }

    // ValueNotifier para comunicar el callback de guardado
    final saveNotifier = ValueNotifier<VoidCallback?>(null);

    // Navegar a una pantalla normal en lugar de un modal
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => ValueListenableBuilder<VoidCallback?>(
          valueListenable: saveNotifier,
          builder: (context, saveCallback, _) {
            return Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                title: Text(
                  'Editar Registro',
                  style: TextStyle(color: AppColors.primary),
                ),
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                actions: [
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 1,
                        ),
                      ),
                      child: Icon(Icons.save, color: AppColors.iconAccent, size: 20),
                    ),
                    onPressed: () {
                      // Llamar al callback de guardado si está disponible
                      if (saveCallback != null) {
                        saveCallback();
                      } else {
                        if (mounted) {
                          showErrorToast(context, 'Error: No se pudo acceder al formulario');
                        }
                      }
                    },
                    tooltip: 'Guardar',
                  ),
                ],
              ),
              body: RegisterNecropciaScreen(
                initialData: initialDataForEdit,
                isEditing: true,
                saveNotifier: saveNotifier,
              ),
            );
          },
        ),
      ),
    );

    if (result != null) {
      // Verificar el estado antes de guardar
      debugPrint('📝 _showEditModal - Datos recibidos después de editar:');
      debugPrint('   - tuuid: ${result['tuuid']}');
      debugPrint('   - synced: ${result['synced']} (tipo: ${result['synced'].runtimeType})');
      debugPrint('   - guardado_backend: ${result['guardado_backend']} (tipo: ${result['guardado_backend']?.runtimeType})');
      
      // Si se guardó, actualizar el registro en el storage
      await _updateRecordInStorage(result);
      
      // Verificar el estado después de guardar
      final storage = context.read<StorageService>();
      final allRecords = storage.getAllRecords(AppStrings.formType1);
      final recordGuardado = allRecords.firstWhere(
        (r) => r['tuuid']?.toString() == result['tuuid']?.toString(),
        orElse: () => {},
      );
      
      if (recordGuardado.isNotEmpty) {
        debugPrint('📝 _showEditModal - Estado del registro después de guardar en storage:');
        debugPrint('   - tuuid: ${recordGuardado['tuuid']}');
        debugPrint('   - synced: ${recordGuardado['synced']} (tipo: ${recordGuardado['synced'].runtimeType})');
        debugPrint('   - guardado_backend: ${recordGuardado['guardado_backend']} (tipo: ${recordGuardado['guardado_backend']?.runtimeType})');
      }
      
      if (mounted) {
        showSuccessToast(context, 'Registro actualizado exitosamente.');
        _loadNecropsias(refresh: true); // Recargar la lista de reportes
      }
    }
  }

  Future<void> _updateRecordInStorage(Map<String, dynamic> updatedData) async {
    final storage = context.read<StorageService>();
    await storage.updateRecord(AppStrings.formType1, updatedData);
  }

  Future<void> _generateReport(String tipo, Map<String, dynamic> necropsia) async {
    // Protección contra múltiples clics simultáneos
    if (_isGeneratingReport) return;
    
    setState(() => _isGeneratingReport = true);
    
    // Mostrar diálogo de carga
    final closeDialog = showChickenLoadingDialog(
      context,
      tipo == '1' ? 'Generando Reporte Tabla...' : 'Generando Reporte Imagenes...',
    );

    // Pequeño delay para asegurar que el diálogo se muestre antes de iniciar el proceso pesado
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      // Usar directamente el record (ya tiene toda la info agrupada)
      final numreg = necropsia['numreg']?.toString() ?? '';
      final granja = necropsia['granja']?.toString() ?? '';
      final galpon = necropsia['galpon']?.toString() ?? '';
      final fectra = necropsia['fectra']?.toString() ?? '';
      
      // Extraer registros del array 'registros' si existe
      List<Map<String, dynamic>> registros = [];
      if (necropsia.containsKey('registros') && necropsia['registros'] is List) {
        registros = (necropsia['registros'] as List).cast<Map<String, dynamic>>();
      }

      // Preparar cabecera para el reporte
      final cabecera = {
        'tdate': fectra,
        'tgranja': granja,
        'tcampania': necropsia['campania']?.toString() ?? '',
        'tgalpon': galpon,
        'tedad': necropsia['edad']?.toString() ?? '',
        'tcencos': necropsia['tcencos']?.toString() ?? '',
        'numreg': numreg,
        'fectra': fectra,
        'tfecreghorainicio': necropsia['tfecreghorainicio']?.toString() ?? '',
        'tfecreghorafin': necropsia['tfecreghorafin']?.toString() ?? '',
        'diagnostico_presuntivo': necropsia['diagnostico_presuntivo']?.toString() ?? '',
      };

      if (tipo == '1') {
        try {
          await _reportService.generateReport1(
            cabecera: cabecera,
            registros: registros,
            context: context,
          );
        } catch (e) {
          // El error ya se maneja en generateReport1, pero aquí podemos agregar más contexto
          debugPrint('Error en _generateReport para tipo 1: $e');
          rethrow;
        }
      } else if (tipo == 'pdf') {
        // Obtener evidencias completas
        final evidenciasCompletas = necropsia['evidencias_completas'] as Map<String, dynamic>? ?? {};
        
        // Verificar si hay imágenes registradas
        bool hasImages = false;
        for (var nivelKey in evidenciasCompletas.keys) {
          final imagenes = evidenciasCompletas[nivelKey] as List<dynamic>? ?? [];
          if (imagenes.isNotEmpty) {
            // Verificar que al menos una imagen tenga un path válido
            for (var imagen in imagenes) {
              if (imagen is Map<String, dynamic>) {
                final path = imagen['path']?.toString() ?? '';
                if (path.isNotEmpty) {
                  hasImages = true;
                  break;
                }
              } else if (imagen is String && imagen.isNotEmpty) {
                hasImages = true;
                break;
              }
            }
            if (hasImages) break;
          }
        }
        
        // Si no hay imágenes, mostrar diálogo y salir
        if (!hasImages) {
          closeDialog();
          if (mounted) {
            await showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  title: const Text(
                    'No hay imágenes registradas',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  content: const Text(
                    'No se encontraron imágenes registradas para este reporte.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'Aceptar',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          }
          return;
        }
        
        await _reportService.generateReportPDF(
          cabecera: cabecera,
          registros: registros,
          evidenciasCompletas: evidenciasCompletas,
          context: context,
        );
      }
      
      // Cerrar diálogo de carga
      closeDialog();
    } catch (e) {
      // Cerrar diálogo de carga en caso de error
      closeDialog();
      if (mounted) {
        showErrorToast(context, 'Error al generar reporte: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingReport = false);
      }
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'No especificado';
    try {
      final date = DateTime.parse(dateString);
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final year = date.year.toString();
      return '$day/$month/$year';
    } catch (e) {
      return dateString;
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: color),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        side: BorderSide(color: color, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> necropsia) {
    final fechaNecropsia = necropsia['fectra']?.toString() ?? '';
    final galpon = necropsia['galpon']?.toString() ?? '';
    final tcencos = necropsia['tcencos']?.toString() ?? '';
    final numreg = necropsia['numreg']?.toString() ?? '';
    final codigoNecropsia =
        necropsia['codigoNecropsia']?.toString().trim() ?? '';
    final campania = necropsia['campania']?.toString() ?? '';
    final edad = necropsia['edad']?.toString() ?? '';
    
    // Fecha y hora de registro
    final fechaRegistro =
        necropsia['tdate_trans']?.toString() ??
        necropsia['tdate']?.toString() ??
        necropsia['diareg']?.toString() ??
        '';
    final horaRegistro =
        necropsia['ttime_trans']?.toString() ??
        necropsia['ttime']?.toString() ??
        '';
    
    String fechaNecropsiaFormateada = _formatDate(fechaNecropsia);
    String fechaHoraRegistro = '';
    if (fechaRegistro.isNotEmpty && horaRegistro.isNotEmpty) {
      try {
        // Formatear fecha y hora juntos
        String horaFormateada = horaRegistro;
        // Si la hora viene en formato HHMMSS, convertir a HH:MM:SS
        if (horaRegistro.length == 6 && horaRegistro.contains(RegExp(r'^\d+$'))) {
          horaFormateada = '${horaRegistro.substring(0, 2)}:${horaRegistro.substring(2, 4)}:${horaRegistro.substring(4, 6)}';
        } else if (horaRegistro.length == 5 && !horaRegistro.contains(':')) {
          // Si viene en formato HHMM
          horaFormateada = '${horaRegistro.substring(0, 2)}:${horaRegistro.substring(2, 4)}:00';
        }
        final fechaFormateada = _formatDate(fechaRegistro);
        fechaHoraRegistro = '$fechaFormateada $horaFormateada';
      } catch (e) {
        fechaHoraRegistro = '$fechaRegistro $horaRegistro';
      }
    } else if (fechaRegistro.isNotEmpty) {
      fechaHoraRegistro = _formatDate(fechaRegistro);
    }

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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    
                    _buildInfoRow('Fecha Necropsia', fechaNecropsiaFormateada),
                    if (fechaHoraRegistro.isNotEmpty)
                      _buildInfoRow('Registro', fechaHoraRegistro),
                    if (codigoNecropsia.isNotEmpty)
                      _buildInfoRow('Código', codigoNecropsia),
                    _buildInfoRow('N° Reg', numreg),
                    _buildInfoRow('Granja', tcencos),
                    _buildInfoRow('Campaña', campania),
                    _buildInfoRow('Galpón', galpon),
                    if (edad.isNotEmpty)
                      _buildInfoRow('Edad', '$edad días'),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.edit, color: AppColors.primary, size: 20),
                onPressed: () => _showEditModal(necropsia),
                tooltip: 'Editar registro',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.description,
                  label: 'Rep.  Tabla',
                  color: AppColors.primary,
                  onPressed: () => _generateReport('1', necropsia),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.picture_as_pdf,
                  label: 'Rep. Imágenes',
                  color: Colors.red,
                  onPressed: () => _generateReport('pdf', necropsia),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildAppBar(
        context,
       'Reportes',
        appIcon: Icons.assessment_outlined,
      ),
      drawer: const AppDrawer(),
      body: SafeArea(
        top: false,
        bottom: true,
        child: RefreshIndicator(
          onRefresh: () => _loadNecropsias(refresh: true),
          color: AppColors.primary,
          child: Column(
            children: [
            // Filtros de fecha
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Desde',
                        hintText: 'Seleccionar fecha',
                        suffixIcon: Icon(Icons.calendar_today, color: AppColors.primary),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onTap: () => _selectDate(context, true),
                      controller: TextEditingController(
                        text: _fechaDesde != null ? _formatDate(_fechaDesde!.toIso8601String()) : '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Hasta',
                        hintText: 'Seleccionar fecha',
                        suffixIcon: Icon(Icons.calendar_today, color: AppColors.primary),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onTap: () => _selectDate(context, false),
                      controller: TextEditingController(
                        text: _fechaHasta != null ? _formatDate(_fechaHasta!.toIso8601String()) : '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _fechaDesde = null;
                        _fechaHasta = null;
                      });
                      _loadNecropsias();
                    },
                    child: const Text('Limpiar'),
                  ),
                ],
              ),
            ),
            // Lista de reportes
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _necropsias.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.description_outlined, size: 64, color: AppColors.textMuted),
                              const SizedBox(height: 16),
                              Text(
                                'No hay reportes disponibles',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.only(
                            left: 16,
                            right: 16,
                            top: 16,
                            bottom: 16 + MediaQuery.of(context).padding.bottom,
                          ),
                          itemCount: _necropsias.length,
                          itemBuilder: (context, index) {
                            return _buildReportCard(_necropsias[index]);
                          },
                        ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}
