import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../screens/dashboard_screen.dart';
import '../screens/register_necropcia_screen.dart';
import '../screens/reports_screen.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';

import '../screens/login_screen.dart';

import '../services/api_service.dart';
import '../services/catalog_service.dart';
import '../utils/toast_helper.dart';
import '../utils/dialog_helper.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

void _aplicarCodigoNecropsiaDesdeSync(
  Map<String, dynamic> record,
  Map<String, dynamic> result,
) {
  final numreg = record['numreg']?.toString() ?? '';
  dynamic codigos = result['codigosNecropsia'];
  if (codigos == null && result['detalle'] is Map) {
    codigos = (result['detalle'] as Map)['codigosNecropsia'];
  }
  if (codigos is Map && numreg.isNotEmpty) {
    final codigo = codigos[numreg];
    if (codigo != null && codigo.toString().trim().isNotEmpty) {
      record['codigoNecropsia'] = codigo.toString();
    }
  }
}

class _AppDrawerState extends State<AppDrawer> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _itemsController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  final List<Animation<double>> _itemAnimations = [];
  final List<Animation<Offset>> _itemSlideAnimations = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).unfocus();
    });
    // Controlador principal del drawer
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // Controlador para items individuales
    _itemsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // Animaciones principales
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(-0.3, 0.0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );

    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    // Crear animaciones para cada item del menú (6 items)
    for (int i = 0; i < 6; i++) {
      final delay = i * 0.1;

      _itemAnimations.add(
        Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _itemsController,
            curve: Interval(delay, 0.6 + delay, curve: Curves.easeOutCubic),
          ),
        ),
      );

      _itemSlideAnimations.add(
        Tween<Offset>(begin: const Offset(-0.5, 0.0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _itemsController,
            curve: Interval(delay, 0.6 + delay, curve: Curves.easeOutCubic),
          ),
        ),
      );
    }

    // Iniciar animaciones
    _animationController.forward();
    _itemsController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _itemsController.dispose();
    super.dispose();
  }
  String formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // Para ttime_trans (VARCHAR(8)): 'HH:mm:ss'
  String formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
  /// Muestra calendario y sube todos los registros de la fecha seleccionada (synced o no)
  Future<void> _showUploadDatePicker(BuildContext context) async {
    final DateTime? selectedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Seleccione la fecha a subir',
      cancelText: 'Cancelar',
      confirmText: 'Subir',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              surface: Colors.white,
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              headerBackgroundColor: Colors.white,
            ),
          ),
          child: SizedBox(
            height: 340,
            child: child,
          ),
        );
      },
    );
    if (selectedDate == null || !mounted) return;
    await _syncRecordsByDate(context, selectedDate);
  }

  /// Sube todos los registros de la fecha (sincronizados o no). Mantiene estado sync como actual.
  Future<void> _syncRecordsByDate(BuildContext context, DateTime selectedDate) async {
    final bool hasInternet = await _checkInternetConnection();
    if (!hasInternet) {
      if (!mounted) return;
      showErrorToast(context, 'No hay conexión a internet');
      return;
    }

    final storage = context.read<StorageService>();
    var recordsToUpload = storage.getRecordsByRegisterDate(
      AppStrings.formType1,
      selectedDate,
    );
    final eventualesPendientes = storage.getPlanEventualesPendientesByDate(
      selectedDate,
    );

    if (recordsToUpload.isEmpty && eventualesPendientes.isEmpty) {
      if (!mounted) return;
      final dateStr = '${selectedDate.day.toString().padLeft(2, '0')}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.year}';
      showInfoToast(context, 'No hay registros para subir del $dateStr');
      return;
    }

    if (!mounted) return;
    
    final closeDialog = showChickenLoadingDialog(
      context,
      'Subiendo registros...',
    );

    try {     
      String? userCode = storage.getUserCodeSync();      
      final String deviceId = await storage.getDeviceId() ?? 'app_movil';
      final now = DateTime.now();
      
      final apiService = ApiService();
      int eventualesExitosos = 0;
      int eventualesFallidos = 0;

      // 1) Subir primero registros eventuales para resolver planId reales antes de necropsias.
      for (final eventual in eventualesPendientes) {
        final payload = {
          'codPrograma': eventual['codPrograma'],
          'nomPrograma': eventual['nomPrograma'],
          'granja': eventual['granja'],
          'campania': eventual['campania'],
          'galpon': eventual['galpon'],
          'edad': eventual['edad'],
          'fecha': eventual['fecha'],
          'observaciones': eventual['observaciones'] ?? '',
          'usuario': userCode ?? 'app_movil',
        };
        final res = await apiService.savePlanificacionEventual(payload);
        if (res['success'] == true) {
          eventualesExitosos++;
          final localId = eventual['localPlanId']?.toString() ?? '';
          final realId = res['planId']?.toString() ?? '';
          if (localId.isNotEmpty && realId.isNotEmpty) {
            await storage.markPlanEventualAsSynced(
              localPlanId: localId,
              realPlanId: realId,
            );
            await storage.replacePlanIdInNecropsias(
              oldPlanId: localId,
              newPlanId: realId,
            );
            await storage.updatePlanCandidateId(
              oldPlanId: localId,
              newPlanId: realId,
            );
          }
        } else {
          eventualesFallidos++;
        }
      }
      // Releer registros luego de mapear planId locales -> planId reales.
      recordsToUpload = storage.getRecordsByRegisterDate(
        AppStrings.formType1,
        selectedDate,
      );
      
      int exitosos = 0;
      int fallidos = 0;
      int conflictosPlan = 0;
      final List<Map<String, dynamic>> registrosExitosos = [];
      
      final futures = recordsToUpload.map((record) async {
        try {
          // CRÍTICO: Crear una copia profunda del registro para preservar todos los campos incluyendo evidencias_completas
          final updated = Map<String, dynamic>.from(record);
          
          // Verificar que evidencias_completas esté presente y hacer copia profunda
          final evidenciasCompletas = record['evidencias_completas'];
          if (evidenciasCompletas != null) {
            // CRÍTICO: Hacer copia profunda de evidencias_completas incluyendo las listas internas
            if (evidenciasCompletas is Map) {
              final evidenciasCompletasDeep = <String, List<Map<String, dynamic>>>{};
              evidenciasCompletas.forEach((key, value) {
                if (value is List) {
                  // Copiar cada elemento de la lista (cada imagen)
                  evidenciasCompletasDeep[key] = value.map((item) {
                    if (item is Map<String, dynamic>) {
                      return Map<String, dynamic>.from(item);
                    } else if (item is Map) {
                      return Map<String, dynamic>.from(item);
                    } else {
                      return {'path': item.toString()};
                    }
                  }).toList().cast<Map<String, dynamic>>();
                } else {
                  // Si no es una lista, intentar convertir
                  evidenciasCompletasDeep[key] = [];
                }
              });
              updated['evidencias_completas'] = evidenciasCompletasDeep;
              debugPrint('   📸 evidencias_completas encontrado: ${evidenciasCompletasDeep.length} niveles');
              // Contar total de imágenes
              int totalImagenes = 0;
              evidenciasCompletasDeep.forEach((key, imagenes) {
                totalImagenes += imagenes.length;
              });
              debugPrint('   📸 Total de imágenes: $totalImagenes');
            } else {
              updated['evidencias_completas'] = evidenciasCompletas;
              debugPrint('   ⚠️ evidencias_completas no es Map, tipo: ${evidenciasCompletas.runtimeType}');
            }
          } else {
            debugPrint('   ⚠️ evidencias_completas NO encontrado en el registro');
          }
          
          updated['tuser'] = userCode;
          updated['tidandroid'] = deviceId;
          updated['tuser_trans'] = userCode;
          updated['tdate_trans'] = formatDate(now);
          updated['ttime_trans'] = formatTime(now);
          
          // SIMPLIFICADO: Usar una única bandera guardado_backend
          // Si guardado_backend == true, el registro ya existe en el backend → usar actualizar_necropsia_movil.php
          // Si guardado_backend == false o no existe, el registro es nuevo → usar guardar_necropsia_movil.php
          final guardadoBackend = record['guardado_backend'];
          final isUpdate = guardadoBackend == true || 
                          guardadoBackend == 'true' || 
                          guardadoBackend == 1;
        
          final endpoint = isUpdate ? 'actualizar_necropsia_movil.php' : 'guardar_necropsia_movil.php';
          debugPrint('   → Endpoint seleccionado: $endpoint');
          
          // Usar el endpoint apropiado según el tipo de registro
          final result = isUpdate
              ? await apiService.updateNecropsiasMovil([updated])
              : await apiService.uploadNecropsiasMovil([updated]);
          
          debugPrint('   ✓ Respuesta recibida del endpoint: $endpoint');
          
          if (result['success'] == true) {
            exitosos++;
            // Marcar que el registro fue guardado en el backend
            record['guardado_backend'] = true;
            _aplicarCodigoNecropsiaDesdeSync(record, result);
            await storage.updateRecord(AppStrings.formType1, record);
            registrosExitosos.add(record);
            return {'success': true, 'record': record};
          } else {
            if (result['code']?.toString() == 'PLAN_USADO') {
              conflictosPlan++;
              final fectraRaw = record['fectra']?.toString() ?? '';
              final baseDate =
                  DateTime.tryParse(fectraRaw) ?? DateTime.now();
              final desde = baseDate.subtract(const Duration(days: 30));
              final hasta = baseDate.add(const Duration(days: 30));
              final refresh = await apiService.downloadPlanMatchCandidates(
                desde: desde,
                hasta: hasta,
              );
              if (refresh['success'] == true) {
                final candidatos = (refresh['candidatos'] as List<dynamic>)
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList();
                await storage.savePlanMatchCandidates(
                  candidates: candidatos,
                  desde: desde,
                  hasta: hasta,
                );
              }
            }
            // Si el error es de duplicado, significa que el registro ya existe en el backend
            // En este caso, marcar guardado_backend = true para que la próxima vez use actualizar
            final errorMessage = result['message']?.toString().toLowerCase() ?? '';
            final detalle = result['detalle'] as Map<String, dynamic>?;
            final duplicados = detalle?['duplicados'] ?? 0;
            
            // Verificar si hay duplicados en la respuesta o en el mensaje
            if (errorMessage.contains('duplicate') || 
                errorMessage.contains('duplicado') || 
                (duplicados is int && duplicados > 0)) {
              debugPrint('⚠️ Registro duplicado detectado - El registro ya existe en el backend');
              debugPrint('   → Estableciendo guardado_backend=true');
              debugPrint('   → guardado_backend antes: ${record['guardado_backend']}');
              
              // CRÍTICO: Crear una copia completa del registro para actualizar
              final recordToUpdate = Map<String, dynamic>.from(record);
              recordToUpdate['guardado_backend'] = true;
              
              // Actualizar el registro en storage con este flag
              final updateSuccess = await storage.updateRecord(AppStrings.formType1, recordToUpdate);
              
              if (updateSuccess) {
                // También actualizar el record en memoria para que se use en la verificación
                record['guardado_backend'] = true;
                debugPrint('   ✓ Registro actualizado en storage con guardado_backend=true');
                
                // Verificar que se guardó correctamente
                final allRecords = storage.getAllRecords(AppStrings.formType1);
                final updatedRecord = allRecords.firstWhere(
                  (r) => r['tuuid']?.toString() == record['tuuid']?.toString(),
                  orElse: () => {},
                );
                if (updatedRecord.isNotEmpty) {
                  debugPrint('   ✓ Verificación: guardado_backend después = ${updatedRecord['guardado_backend']}');
                }
              } else {
                debugPrint('   ❌ Error al actualizar registro en storage');
              }
            }
            fallidos++;
            debugPrint('❌ Error al ${isUpdate ? "actualizar" : "enviar"} registro: ${result['message']}');
            return {'success': false, 'record': record, 'error': result['message']};
          }
        } catch (e) {
          fallidos++;
          debugPrint('❌ Excepción al procesar registro: $e');
          return {'success': false, 'record': record, 'error': e.toString()};
        }
      }).toList();
      
      // Esperar a que todos los envíos terminen (todos los "hilos")
      await Future.wait(futures);
   
      closeDialog();

      if (!mounted) return;
      
      // Marcar como sincronizados solo los registros exitosos
      if (exitosos > 0) {
        // Marcar cada registro exitoso individualmente
        for (var record in registrosExitosos) {
         
          await storage.markRecordAsSynced(AppStrings.formType1, record);
          
          // Verificar que se marcó correctamente
          final allRecords = storage.getAllRecords(AppStrings.formType1);
          final updatedRecord = allRecords.firstWhere(
            (r) => r['tuuid']?.toString() == record['tuuid']?.toString(),
            orElse: () => {},
          );
          if (updatedRecord.isNotEmpty) {
            debugPrint('   ✓ Verificación: synced después = ${updatedRecord['synced']}');
            debugPrint('   ✓ Verificación: guardado_backend después = ${updatedRecord['guardado_backend']}');
          }
        }
        await storage.setLastSyncDate();
      }
      
      // Mostrar resumen detallado
      if (exitosos > 0 && fallidos == 0) {
        showSuccessToast(
          context,
          '✅ Envío correcto${eventualesExitosos > 0 ? ' | Eventuales enviados' : ''}',
        );
      } else if (exitosos > 0 && fallidos > 0) {
        showInfoToast(
          context,
          '✅ Enviados: $exitosos | ⚠️ Pendientes: $fallidos${conflictosPlan > 0 ? ' | 🔁 PLAN_USADO: $conflictosPlan' : ''}${eventualesExitosos > 0 ? ' | EVT ok' : ''}${eventualesFallidos > 0 ? ' | EVT err' : ''}',
        );
      } else {
        if (eventualesExitosos > 0 && eventualesFallidos == 0) {
          showSuccessToast(
            context,
            '✅ Eventuales enviados',
          );
          return;
        }
        if (conflictosPlan > 0) {
          showInfoToast(
            context,
            'No se enviaron registros por conflicto de planificación (PLAN_USADO). Reabra y reseleccione planificación.',
          );
        } else {
          showErrorToast(
            context,
            '❌ No se pudo enviar ningún registro. Intente de nuevo.',
          );
        }
      }
    } catch (e) {
      // Cerrar diálogo de carga en caso de error
      closeDialog();
      if (!mounted) return;
      showErrorToast(context, 'Ocurrió un error: ${e.toString()}');
    }
  }

  Future<bool> _checkInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    }
  }

  Future<void> _handleCerrarSesion(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 12,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.redAccent.withOpacity(0.2),
                    Colors.red.withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: Colors.redAccent,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              AppStrings.cerrarSesionTitulo,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 19),
            ),
          ],
        ),
        content: const Text(
          AppStrings.cerrarSesionMensaje,
          style: TextStyle(fontSize: 15, color: Colors.black87, height: 1.5),
        ),
        actionsAlignment: MainAxisAlignment.end,
        actionsPadding: const EdgeInsets.only(right: 12, bottom: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey[700],
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            child: const Text(AppStrings.cancelar),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE63946), Color(0xFFD62828)],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.redAccent.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                elevation: 0,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                AppStrings.si,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (confirmed == true) {
      final storage = context.read<StorageService>();
      await storage.setLoggedIn(false);

      if (!mounted) return;

      Get.off(
        () => const LoginScreen(),
        transition: Transition.fadeIn,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    }
  }

  void _showAcercaDe(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 12,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.accent.withOpacity(0.2),
                    AppColors.accentLight.withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.info_rounded,
                color: AppColors.accent,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Acerca de',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 19),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.accent.withOpacity(0.1),
                    AppColors.accentLight.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'GC NECROPSIA',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: AppColors.primary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'v${AppConstants.appVersion}',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(
                        Icons.code_rounded,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Desarrollado por ${AppConstants.appDeveloper}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Center(
            child: Container(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  elevation: 0,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  AppStrings.cerrar,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      elevation: 0,
      backgroundColor: AppColors.background,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              children: [
                // ✨ HEADER PREMIUM CON DEGRADADO ELEGANTE
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: AppColors.headerGradient,
                    boxShadow: AppColors.strongShadow,
                  ),
                  child: Stack(
                    children: [
                      // Efecto de brillo sutil
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white.withOpacity(0.1),
                                Colors.transparent,
                                Colors.white.withOpacity(0.05),
                              ],
                            ),
                          ),
                        ),
                      ),

                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                          child: Builder(
                            builder: (context) {
                              final storage = context.read<StorageService>();
                              final userName = storage.getUserName() ?? 'USUARIO';
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.25),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withOpacity(
                                              0.5,
                                            ),
                                            width: 2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.1,
                                              ),
                                              blurRadius: 12,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: Image.asset(
                                          'assets/images/logo_grs.png',
                                          width: 56,
                                          height: 56,
                                          fit: BoxFit.contain,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                                return const Icon(
                                                  Icons.store_rounded,
                                                  size: 56,
                                                  color: Colors.white,
                                                );
                                              },
                                        ),
                                      ),
                                      const SizedBox(width: 18),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              userName.toUpperCase(),
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(
                                                  0.98,
                                                ),
                                                fontSize: 19,
                                                fontWeight: FontWeight.w700,
                                                height: 1.3,
                                                letterSpacing: -0.3,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(
                                                  0.2,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                AppConstants.companyName,
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withOpacity(0.95),
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 28),

                                  // ☁️ BOTONES DE SINCRONIZACIÓN
                                  Consumer<StorageService>(
                                    builder: (context, storage, _) {
                                      return FutureBuilder(
                                        future: Future.wait([
                                          storage.getLastDownloadDate(),
                                          storage.getLastSyncDate(),
                                        ]),
                                        builder:
                                            (
                                              context,
                                              AsyncSnapshot<List<String?>>
                                              snapshot,
                                            ) {
                                              if (!snapshot.hasData) {
                                                return Center(
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.all(
                                                          16,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white
                                                          .withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            16,
                                                          ),
                                                    ),
                                                    child:
                                                        const CircularProgressIndicator(
                                                          strokeWidth: 2.5,
                                                          color: Colors.white,
                                                        ),
                                                  ),
                                                );
                                              }

                                              final lastDownload =
                                                  snapshot.data![0] ??
                                                  '--/--/--';
                                              final lastSync =
                                                  snapshot.data![1] ??
                                                  '--/--/--';

                                              return Row(
                                                children: [
                                                  Expanded(
                                                    child: _SyncButton(
                                                      icon: Icons
                                                          .cloud_download_rounded,
                                                      label: 'Descargar',
                                                      lastDate: lastDownload,
                                                      onTap: () async {
                                                        final bool hasInternet =
                                                            await _checkInternetConnection();

                                                        if (!mounted) return;

                                                        if (!hasInternet) {
                                                          showErrorToast(
                                                            context,
                                                            'No hay conexión a internet, Inténtelo más tarde.',
                                                          );
                                                          return;
                                                        }

                                                        final apiService = ApiService();
                                                        
                                                        // Descargar CENCOS y galpones
                                                        final closeDialogCencos = showChickenLoadingDialog(
                                                          context,
                                                          'Descargando Información...',
                                                        );
                                                        
                                                        try {
                                                          final result = await apiService.downloadCencosGalpones();
                                                          closeDialogCencos();
                                                          
                                                          if (!mounted) return;
                                                          
                                                          if (result['success'] == true) {
                                                            // Guardar en storage local
                                                            final cencos = result['cencos'] as List;
                                                            final galponesPorCenco = result['galponesPorCenco'] as Map<String, List<dynamic>>;
                                                            
                                                            // Convertir a formato para storage
                                                            // Asegurar que todos los valores sean del tipo correcto
                                                            final cencosData = cencos.map((c) => {
                                                              'codigo': c.codigo?.toString() ?? '',
                                                              'nombre': c.nombre?.toString() ?? '',
                                                              'edad': c.edad?.toString() ?? '0',
                                                              'fec_ing_min': c.fecIngMin?.toString() ?? '',
                                                            }).toList();
                                                            
                                                            final galponesData = <String, List<Map<String, dynamic>>>{};
                                                            galponesPorCenco.forEach((codigo, galpones) {
                                                              galponesData[codigo] = galpones.map((g) => {
                                                                'tcencos': g.tcencos,
                                                                'tcodint': g.tcodint,
                                                                'fec_ing_min': g.fecIngMin?.toString() ?? '',
                                                              }).toList();
                                                            });
                                                            
                                                            await storage.saveCencosGalpones(
                                                              cencos: cencosData,
                                                              galponesPorCenco: galponesData,
                                                            );

                                                            final hoy = DateTime.now();
                                                            final desde = hoy.subtract(const Duration(days: 30));
                                                            final hasta = hoy.add(const Duration(days: 30));
                                                            final planResult = await apiService.downloadPlanMatchCandidates(
                                                              desde: desde,
                                                              hasta: hasta,
                                                            );
                                                            if (planResult['success'] == true) {
                                                              final candidatos = (planResult['candidatos'] as List<dynamic>)
                                                                  .whereType<Map>()
                                                                  .map((e) => Map<String, dynamic>.from(e))
                                                                  .toList();
                                                              await storage.savePlanMatchCandidates(
                                                                candidates: candidatos,
                                                                desde: desde,
                                                                hasta: hasta,
                                                              );
                                                            }
                                                            
                                                            await storage.setLastDownloadDate();
                                                            
                                                            // Descargar catálogo de usuarios para login offline
                                                            final catalogService = context.read<CatalogService>();
                                                            await catalogService.downloadCatalogos(tablas: ['usuarios']);
                                                            
                                                            if (!mounted) return;
                                                            showSuccessToast(
                                                              context,
                                                              'Información descargada correctamente',
                                                            );
                                                          } else {
                                                            showErrorToast(
                                                              context,
                                                              'Error al descargar. Inténtelo de nuevo.',
                                                            );
                                                          }
                                                        } catch (e) {
                                                          closeDialogCencos();
                                                          if (!mounted) return;
                                                         showErrorToast(
                                                              context,
                                                              'Error al descargar. Inténtelo de nuevo.',
                                                            );
                                                        }
                                                        
                                                        
                                                      },
                                                    ),
                                                  ),

                                                  const SizedBox(width: 20),

                                                  Expanded(
                                                    child: Builder(
                                                      builder: (context) {
                                                        final pendingRecords = storage.getRecordsPendientes(AppStrings.formType1);
                                                        final pendingCount = pendingRecords.length;
                                                        return _SyncButton(
                                                          icon: Icons
                                                              .cloud_upload_rounded,
                                                          label: 'Subir',
                                                          lastDate: lastSync,
                                                          pendingCount: pendingCount,
                                                          onTap: () async {
                                                            await _showUploadDatePicker(context);
                                                          },
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                ],
                                              );
                                            },
                                      );
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.background.withOpacity(0.3),
                          Colors.white,
                        ],
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      bottom: true,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                          child: Row(
                            children: [
                              Container(
                                width: 4,
                                height: 24,
                                decoration: BoxDecoration(
                                  gradient: AppColors.primaryGradient,
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: AppColors.lightShadow,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Navegación',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                         _DrawerItem(
                          icon: Icons.dashboard_rounded, // 📊 Dashboard
                          title: 'Dashboard',
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF4CAF50), // Verde principal
                              const Color(0xFF66BB6A), // Verde vibrante
                              const Color(0xFF81C784), // Verde claro
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!context.mounted) return;
                              // Forzar una instancia NUEVA del Dashboard para que las animaciones
                              // siempre arranquen desde 0, incluso si vienes de varias pantallas.
                              Get.offAll(
                                () => DashboardScreen(key: UniqueKey()),
                                transition: Transition.fadeIn,
                                duration: const Duration(milliseconds: 600),
                                curve: Curves.easeInOut,
                              );
                            });
                          },
                        ),
                        _DrawerItem(
                          icon: Icons.assignment_rounded, 
                          title: 'Registro de Necropsia',
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF26A69A), // Turquesa
                              const Color(0xFF4DB6AC), // Turquesa claro
                              const Color(0xFF80CBC4), // Turquesa muy claro
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!context.mounted) return;
                              Get.off(
                                () => const RegisterNecropciaScreen(),
                                transition: Transition.fadeIn,
                                duration: const Duration(milliseconds: 600),
                                curve: Curves.easeInOut,
                              );
                            });
                          },
                        ),
                        _DrawerItem(
                          icon: Icons.assessment_outlined,
                          title: 'Reportes',
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF42A5F5), // Azul
                              const Color(0xFF64B5F6), // Azul claro
                              const Color(0xFF90CAF9), // Azul muy claro
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!context.mounted) return;
                              Get.to(
                                () => const ReportsScreen(),
                                transition: Transition.rightToLeft,
                                duration: const Duration(milliseconds: 300),
                              );
                            });
                          },
                        ),
                      
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                          child: Row(
                            children: [
                              Container(
                                width: 4,
                                height: 24,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [AppColors.accent, AppColors.accentLight],
                                  ),
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: AppColors.lightShadow,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Opciones',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _DrawerItem(
                          icon: Icons.info_rounded,
                          title: AppStrings.menuAcercaDe,
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF66BB6A), // Verde claro
                              const Color(0xFF81C784), // Verde más claro
                              const Color(0xFFA5D6A7), // Verde muy claro
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          onTap: () {
                            _showAcercaDe(context);
                          },
                        ),
                        _DrawerItem(
                          icon: Icons.logout_rounded,
                          title: AppStrings.menuCerrarSesion,
                          gradient: LinearGradient(
                            colors: [AppColors.error, AppColors.errorDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          onTap: () {
                            _handleCerrarSesion(context);
                          },
                        ),
                       
                      ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class _SyncButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String lastDate;
  final VoidCallback onTap;
  final int? pendingCount;

  const _SyncButton({
    required this.icon,
    required this.label,
    required this.lastDate,
    required this.onTap,
    this.pendingCount,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.35),
                Colors.white.withOpacity(0.25),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withOpacity(0.6),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: label == 'Descargar'
                            ? [
                                const Color(0xFF4CAF50).withOpacity(0.8), // Verde
                                const Color(0xFF66BB6A).withOpacity(0.6), // Verde claro
                              ]
                            : [
                                const Color(0xFF26A69A).withOpacity(0.8), // Turquesa
                                const Color(0xFF4DB6AC).withOpacity(0.6), // Turquesa claro
                              ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.5),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                        BoxShadow(
                          color: Colors.white.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, -1),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: Colors.white, size: 26),
                  ),
                  // Badge de registros pendientes (solo para botón "Subir")
                  if (label == 'Subir' && pendingCount != null && pendingCount! > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        child: Text(
                          pendingCount! > 99 ? '99+' : pendingCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.98),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                lastDate,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final LinearGradient gradient;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary.withOpacity(0.2),
                width: 1.5,
              ),
              boxShadow: AppColors.lightShadow,
            ),
            child: Row(
              children: [
                // Icono con gradiente mejorado
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: gradient.colors[0].withOpacity(0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 18),
                // Título
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                // Flecha mejorada
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 12,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
