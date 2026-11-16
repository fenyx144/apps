import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../screens/dashboard_screen.dart';
import '../screens/login_screen.dart';
import '../screens/mortality_type_select_screen.dart';
import '../screens/auditoria_screen.dart';
import '../screens/liquidacion_report_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/config_screen.dart';
import '../services/api_service.dart';
import '../services/catalog_download_service.dart';
import '../services/catalog_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/theme_extensions.dart';
import '../utils/dialog_helper.dart';
import '../utils/toast_helper.dart';
import 'drawer_item.dart';
import 'mortality_register_icon.dart';
import 'poultry_icon.dart';
import 'sync_button.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final _apiService = ApiService();
  final _catalogDownload = CatalogDownloadService();

  Future<bool> _checkInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    }
  }

  Future<void> _downloadCatalogs() async {
    if (!await _checkInternet()) {
      if (mounted) showErrorToast(context, AppStrings.sinConexion);
      return;
    }

    final closeDialog = showChickenLoadingDialog(context, 'Actualizando información...');
    final storage = context.read<StorageService>();
    final catalogService = context.read<CatalogService>();

    try {
      final result = await _catalogDownload.downloadAll(
        storage: storage,
        catalogService: catalogService,
      );
      if (!mounted) return;

      // También descargar liquidaciones y mis auditorías para offline
      await _downloadOfflineData(storage);
      closeDialog();
      if (!mounted) return;

      if (result.success && result.cencosOk && result.motivosOk) {
        showSuccessToast(context, AppStrings.descargaExitosa);
      } else if (result.cencosOk || result.motivosOk) {
        showWarningToast(context, result.message);
      } else {
        showErrorToast(context, result.message);
      }
    } catch (e) {
      closeDialog();
      if (mounted) showErrorToast(context, 'Error al descargar información.');
    }
  }

  Future<void> _downloadOfflineData(StorageService storage) async {
    final offlineErrors = <String>[];
    try {
      // Descargar liquidaciones de los últimos 7 días
      final hoy = DateTime.now();
      for (var i = 0; i < 7; i++) {
        final fecha = DateFormat('yyyy-MM-dd').format(hoy.subtract(Duration(days: i)));
        try {
          final res = await _apiService.listarMortalidadLiquidacion(fecha: fecha);
          if (res['success'] == true && res['registros'] is List) {
            final registros = (res['registros'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            if (registros.isNotEmpty) {
              final existentes = storage.getLiquidacionCache();
              final ids = existentes.map((r) => r['tuuid']?.toString()).toSet();
              for (final r in registros) {
                final id = r['tuuid']?.toString() ?? '';
                if (id.isNotEmpty && !ids.contains(id)) {
                  existentes.add(r);
                  ids.add(id);
                }
              }
              await storage.saveLiquidacionCache(existentes);
              await storage.saveLiquidacionCacheDate(fecha);
            }
          }
        } catch (e) {
          offlineErrors.add('Liquidacion $fecha: $e');
        }
      }

      // Descargar mis auditorías
      final usuario = storage.getUserCodeSync() ?? '';
      if (usuario.isNotEmpty) {
        try {
          final resAud = await _apiService.listarMisAuditorias(usuario: usuario);
          if (resAud['success'] == true) {
            final data = resAud['data'];
            final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
            final raw = map['auditorias'];
            if (raw is List) {
              await storage.saveMisAuditoriasCache(
                raw.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
              );
            }
          }
        } catch (e) {
          offlineErrors.add('Mis auditorias: $e');
        }

        // Descargar bloques de liquidación (auditorías como bloques)
        try {
          final resBloques = await _apiService.listarBloquesLiquidacion(usuario: usuario);
          if (resBloques['success'] == true) {
            final data = resBloques['data'];
            final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
            final raw = map['bloques'];
            if (raw is List) {
              await storage.saveBloquesLiquidacion(
                raw.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
              );
            }
          }
        } catch (e) {
          offlineErrors.add('Bloques liquidacion: $e');
        }

        // Descargar registros pendientes de auditoria (para uso offline)
        try {
          final resPend = await _apiService.listarAuditoriaPendiente();
          if (resPend['success'] == true) {
            final data = resPend['data'];
            final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
            final raw = map['registros'];
            if (raw is List) {
              await storage.saveAuditoriaPendienteCache(
                raw.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
              );
            }
          }
        } catch (e) {
          offlineErrors.add('Auditoria pendiente: $e');
        }
      }
    } catch (e) {
      offlineErrors.add('General: $e');
      debugPrint('Error descargando datos offline: $e');
    }

    // Descargar cantidades de pollos en lote
    try {
      await _downloadCantidadPollosBatch(storage);
    } catch (e) {
      offlineErrors.add('Cantidad pollos: $e');
      debugPrint('Error descargando cantidades batch: $e');
    }

    if (offlineErrors.isNotEmpty && mounted) {
      showWarningToast(
        context,
        'Datos offline: ${offlineErrors.join('; ')}',
        duration: const Duration(seconds: 5),
      );
    }
  }

  Future<void> _downloadCantidadPollosBatch(StorageService storage) async {
    try {
      final cencos = storage.getCencosLocal();
      if (cencos.isEmpty) {
        debugPrint('[CANTIDAD_BATCH] no hay cencos en cache, se omite');
        return;
      }
      // tcencos de 6 dígitos (movi_zonas/maes_zonas2 usa el código completo de ccos)
      final tcencosList = cencos
          .map((c) => (c['codigo']?.toString() ?? '').trim())
          .where((c) => c.isNotEmpty)
          .toSet()
          .toList();
      if (tcencosList.isEmpty) return;

      final hoy = DateFormat('yyyy-MM-dd').format(DateTime.now());
      debugPrint('[CANTIDAD_BATCH] descargando para ${tcencosList.length} tcencos, fecha=$hoy');
      final res = await _apiService.downloadCantidadPollosBatch(
        tcencosList: tcencosList,
        fechaCentral: hoy,
      );
      if (res['success'] == true) {
        final items = res['items'] as Map<String, List<Map<String, dynamic>>>;
        final existing = storage.getCantidadPollos();
        existing.addAll(items);
        // Copia sin fecha para el día de hoy (compatibilidad con pantallas)
        final hoyStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
        for (final key in items.keys) {
          if (key.endsWith('_$hoyStr')) {
            final baseKey = key.substring(0, key.length - hoyStr.length - 1);
            existing[baseKey] = items[key]!;
          }
        }
        await storage.saveCantidadPollos(existing);
        debugPrint('[CANTIDAD_BATCH] descarga exitosa: ${items.length} claves');
      } else {
        debugPrint('[CANTIDAD_BATCH] error: ${res['message']}');
      }
    } catch (e) {
      debugPrint('[CANTIDAD_BATCH] error inesperado: $e');
    }
  }

  /// Conteos por día de registros locales: pendientes y subidos.
  Map<String, ({int pend, int sub})> _buildUploadCounts() {
    final storage = context.read<StorageService>();
    final counts = <String, ({int pend, int sub})>{};
    for (final tabla in [
      AppStrings.formTypeMortalidad,
      AppStrings.formTypeAuditoria,
    ]) {
      for (final r in storage.getAllRecords(tabla)) {
        final raw = r['tdate_trans']?.toString() ??
            r['fecha']?.toString() ??
            '';
        if (raw.isEmpty) continue;
        final key =
            raw.contains('T') ? raw.split('T').first : raw.split(' ').first;
        final e = counts[key];
        final esSubido = r['synced'] == true;
        counts[key] = e == null
            ? (esSubido ? (pend: 0, sub: 1) : (pend: 1, sub: 0))
            : (esSubido
                ? (pend: e.pend, sub: e.sub + 1)
                : (pend: e.pend + 1, sub: e.sub));
      }
    }
    return counts;
  }

  Future<DateTime?> _pickUploadDate(
    BuildContext hostContext,
    Map<String, ({int pend, int sub})> counts,
  ) {
    return showDialog<DateTime>(
      context: hostContext,
      builder: (_) => _UploadDateDialog(
        counts: counts,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      ),
    );
  }

  Future<void> _uploadRecords() async {
    if (!await _checkInternet()) {
      if (mounted) showErrorToast(context, AppStrings.sinConexion);
      return;
    }

    final storage = context.read<StorageService>();

    // Conteos compactos por día: pendientes (P) y subidos (S)
    final counts = _buildUploadCounts();
    final selectedDate = await _pickUploadDate(context, counts);
    if (selectedDate == null || !mounted) return;

    final mortalidadRecords = storage.getRecordsByRegisterDate(
      AppStrings.formTypeMortalidad,
      selectedDate,
    );
    final auditoriaRecords = storage.getRecordsByRegisterDate(
      AppStrings.formTypeAuditoria,
      selectedDate,
    );

    if (mortalidadRecords.isEmpty && auditoriaRecords.isEmpty) {
      showInfoToast(context, 'No hay registros en esa fecha');
      return;
    }

    final closeDialog = showChickenLoadingDialog(context, 'Enviando registros...');
    var uploaded = 0;
    var duplicated = 0;
    var failed = 0;
    String? lastError;

    try {
      for (final record in mortalidadRecords) {
        final tuuid = record['tuuid']?.toString().trim() ?? '';
        if (tuuid.isEmpty) {
          failed++;
          lastError = 'Registro sin identificador (tuuid)';
          continue;
        }

        // guardar_mortalidad_movil.php san_fact_mortalidad_cab / san_fact_mortalidad_det
        final result = await _apiService.uploadMortalidadMovil(
          record: Map<String, dynamic>.from(record),
        );

        if (result['success'] == true) {
          final synced = Map<String, dynamic>.from(record);
          final data = result['data'];
          var yaExistia = false;
          if (data is Map) {
            final registros = data['registros'];
            if (registros is List && registros.isNotEmpty) {
              final first = registros.first;
              if (first is Map) {
                yaExistia = first['duplicado'] == true;
                for (final key in ['doc', 'serie', 'numero', 'codigo', 'id']) {
                  if (first[key] != null) {
                    synced[key] = first[key];
                  }
                }
              }
            }
          }
          await storage.markRecordAsSynced(
            AppStrings.formTypeMortalidad,
            synced,
          );
          if (yaExistia) {
            duplicated++;
          } else {
            uploaded++;
          }
        } else {
          failed++;
          lastError = result['message']?.toString() ?? 'Error al guardar en servidor';
        }
      }

      for (final record in auditoriaRecords) {
        if (record['synced'] == true) continue;

        final tuuid = record['tuuid']?.toString().trim() ?? '';
        if (tuuid.isEmpty) {
          failed++;
          lastError = 'Auditoría sin identificador (tuuid)';
          continue;
        }

        final regsRaw = record['registros'];
        if (regsRaw is! List || regsRaw.isEmpty) {
          failed++;
          lastError = 'Auditoría sin grupos para subir';
          continue;
        }

        final registros = regsRaw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        final usuario = record['usuario']?.toString().trim() ??
            storage.getUserCodeSync() ??
            '';
        if (usuario.isEmpty) {
          failed++;
          lastError = 'Auditoría sin usuario';
          continue;
        }

        final result = await _apiService.guardarAuditoriaMovil(
          usuario: usuario,
          registros: registros,
          observacionesGenerales: record['observaciones']?.toString() ?? '',
          tuuid: tuuid,
        );
        debugPrint('[AUDITORIA_SYNC_RES] tuuid=$tuuid ${jsonEncode(result)}');

        if (result['success'] == true) {
          await storage.markRecordAsSynced(
            AppStrings.formTypeAuditoria,
            Map<String, dynamic>.from(record),
          );
          uploaded++;
        } else {
          failed++;
          lastError = result['message']?.toString() ?? 'Error al guardar auditoría';
        }
      }

      if (uploaded > 0 || duplicated > 0) {
        await storage.setLastSyncDate();
      }
      closeDialog();

      if (!mounted) return;

      final procesados = uploaded + duplicated;
      if (procesados > 0 && failed == 0) {
        showSuccessToast(context, 'Se enviaron $procesados registros correctamente');
      } else if (procesados > 0) {
        showWarningToast(
          context,
          'Se enviaron $procesados registros ($failed con error)',
        );
      } else {
        showErrorToast(
          context,
          lastError ?? 'No se pudo enviar ningún registro',
        );
      }
    } catch (e) {
      closeDialog();
      if (mounted) showErrorToast(context, 'Error al enviar registros.');
    }
  }

  Future<void> _logout() async {
    final isDark = context.isDarkTheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkCard : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          AppStrings.cerrarSesionTitulo,
          style: TextStyle(color: isDark ? Colors.white : AppColors.textPrimary),
        ),
        content: Text(
          AppStrings.cerrarSesionMensaje,
          style: TextStyle(color: isDark ? Colors.white70 : AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppStrings.cancelar),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(AppStrings.si),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await context.read<StorageService>().clearSession();
    if (!mounted) return;
    Get.offAll(() => const LoginScreen());
  }

  void _showAcercaDe(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkCard : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 12,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF66BB6A),
                    Color(0xFF81C784),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.info_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Acerca de',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 19,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
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
                color: isDark ? AppColors.darkSurface : const Color(0xFFF1F8E9),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppConstants.appTitle,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: isDark ? const Color(0xFF81C784) : AppColors.primary,
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
                          color: (isDark ? const Color(0xFF81C784) : AppColors.accent)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'v${AppConstants.appVersion}',
                          style: TextStyle(
                            color: isDark ? const Color(0xFF81C784) : AppColors.accent,
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
                        color: isDark ? Colors.white54 : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Desarrollado por ${AppConstants.appDeveloper}',
                          style: TextStyle(
                            color: isDark ? Colors.white54 : AppColors.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.business_rounded,
                        size: 18,
                        color: isDark ? Colors.white54 : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          AppConstants.companyName,
                          style: TextStyle(
                            color: isDark ? Colors.white54 : AppColors.textSecondary,
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
                    color: AppColors.accent.withValues(alpha: 0.3),
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
                  'Cerrar',
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

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 24,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.accent, AppColors.primaryLight],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              color: context.primaryTextColor,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final userName = storage.getUserName() ?? 'Usuario';
    final pendientes = storage.getRecordsPendientes(AppStrings.formTypeMortalidad).length +
        storage.getRecordsPendientes(AppStrings.formTypeAuditoria).length;
    final isDark = context.isDarkTheme;
    final drawerBg = Theme.of(context).drawerTheme.backgroundColor ??
        (isDark ? AppColors.darkBackground : AppColors.background);
    final acceso = storage.getPermisos();

    return Drawer(
      elevation: 0,
      backgroundColor: drawerBg,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: AppColors.headerGradient,
              boxShadow: AppColors.strongShadow,
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2),
                          ),
                          child: Image.asset(
                            'assets/images/logo_grs.png',
                            width: 48,
                            height: 48,
                            errorBuilder: (_, __, ___) => const PoultryIcon(
                              size: 40,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                userName.toUpperCase(),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.98),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  AppConstants.companyName,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.95),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    FutureBuilder(
                      future: Future.wait([
                        storage.getLastDownloadDate(),
                        storage.getLastSyncDate(),
                      ]),
                      builder: (context, snapshot) {
                        final lastDownload = snapshot.data?[0] ?? '--/--/--';
                        final lastSync = snapshot.data?[1] ?? '--/--/--';
                        return Row(
                          children: [
                            Expanded(
                              child: SyncButton(
                                icon: Icons.cloud_download_rounded,
                                label: 'Descargar',
                                lastDate: lastDownload,
                                onTap: _downloadCatalogs,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: SyncButton(
                                icon: Icons.cloud_upload_rounded,
                                label: 'Subir',
                                lastDate: lastSync,
                                pendingCount: pendientes,
                                onTap: _uploadRecords,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: drawerBg,
              child: SafeArea(
                top: false,
                child: ListView(
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  children: [
                _sectionTitle('Navegación'),
                if (acceso['verDashboard'] == true)
                  DrawerItem(
                    icon: Icons.dashboard_rounded,
                    title: AppStrings.menuDashboard,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4CAF50), Color(0xFF66BB6A), Color(0xFF81C784)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Get.offAll(() => const DashboardScreen());
                    },
                  ),
                if (acceso['verRegMortalidad'] == true)
                  DrawerItem(
                    iconWidget: const MortalityRegisterIcon(size: 22, color: Colors.white),
                    title: AppStrings.menuRegistro,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF26A69A), Color(0xFF4DB6AC), Color(0xFF80CBC4)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Get.off(() => const MortalityTypeSelectScreen());
                    },
                  ),
                if (acceso['verAuditoria'] == true)
                  DrawerItem(
                    icon: Icons.fact_check_outlined,
                    title: 'Registro Auditoría',
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEF6C00), Color(0xFFFF9800), Color(0xFFFFB74D)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Get.to(() => const AuditoriaScreen());
                    },
                  ),
                if (acceso['verReportes'] == true)
                  DrawerItem(
                    icon: Icons.assessment_outlined,
                    title: AppStrings.menuReportes,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF42A5F5), Color(0xFF64B5F6), Color(0xFF90CAF9)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Get.to(() => const ReportsScreen());
                    },
                  ),
                if (acceso['verLiquidacion'] == true)
                  DrawerItem(
                    icon: Icons.receipt_long_rounded,
                    title: AppStrings.menuReporteLiquidacion,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7E57C2), Color(0xFF9575CD), Color(0xFFB39DDB)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Get.to(() => const LiquidacionReportScreen());
                    },
                  ),
                _sectionTitle('Opciones'),
                DrawerItem(
                  icon: Icons.settings_rounded,
                  title: 'Configuración',
                  gradient: const LinearGradient(
                    colors: [Color(0xFF78909C), Color(0xFF90A4AE)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ConfigScreen()));
                  },
                ),
                DrawerItem(
                  icon: Icons.logout_rounded,
                  title: AppStrings.menuCerrarSesion,
                  gradient: const LinearGradient(
                    colors: [AppColors.error, Color(0xFFD32F2F)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  onTap: _logout,
                ),
                _sectionTitle('Informaci\u00f3n'),
                DrawerItem(
                  icon: Icons.info_rounded,
                  title: 'Acerca de',
                  gradient: const LinearGradient(
                    colors: [Color(0xFF66BB6A), Color(0xFF81C784), Color(0xFFA5D6A7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  onTap: () => _showAcercaDe(context),
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
}

/// Calendario mensual con badges de pendientes (P) y subidos (S) por día.
class _UploadDateDialog extends StatefulWidget {
  const _UploadDateDialog({
    required this.counts,
    required this.firstDate,
    required this.lastDate,
  });

  final Map<String, ({int pend, int sub})> counts;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_UploadDateDialog> createState() => _UploadDateDialogState();
}

class _UploadDateDialogState extends State<_UploadDateDialog> {
  static const _weekdays = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  late DateTime _focus;
  DateTime? _selected;

  @override
  void initState() {
    super.initState();
    _focus = DateTime.now();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _changeMonth(int delta) {
    final next = DateTime(_focus.year, _focus.month + delta, 1);
    if (next.isBefore(
      DateTime(widget.firstDate.year, widget.firstDate.month, 1),
    )) {
      return;
    }
    if (next.isAfter(
      DateTime(widget.lastDate.year, widget.lastDate.month, 1),
    )) {
      return;
    }
    setState(() => _focus = next);
  }

  Widget _countBadge(int n, bool pend) {
    final bg = pend ? const Color(0xFFFFE0B2) : const Color(0xFFC8E6C9);
    final fg = pend ? const Color(0xFFE65100) : const Color(0xFF1B5E20);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        pend ? 'P: $n' : 'S: $n',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: fg,
          height: 1.1,
        ),
      ),
    );
  }

  Widget _dayCell(double width, int dayNumber) {
    final day = DateTime(_focus.year, _focus.month, dayNumber);
    final key = DateFormat('yyyy-MM-dd').format(day);
    final c = widget.counts[key];
    final now = DateTime.now();
    final isToday = _isSameDay(day, now);
    final isSelected = _selected != null && _isSameDay(day, _selected!);
    final first = DateTime(
      widget.firstDate.year,
      widget.firstDate.month,
      widget.firstDate.day,
    );
    final last = DateTime(
      widget.lastDate.year,
      widget.lastDate.month,
      widget.lastDate.day,
    );
    final disabled = day.isBefore(first) || day.isAfter(last);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: disabled
          ? null
          : () => setState(() => _selected = day),
      child: Container(
        width: width,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$dayNumber',
              style: TextStyle(
                fontSize: 13,
                height: 1.0,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                color: disabled
                    ? (isDark
                        ? const Color(0xFF6E6E6E)
                        : const Color(0xFF9E9E9E))
                    : isSelected
                        ? Colors.white
                        : isToday
                            ? AppColors.primaryDark
                            : isDark
                                ? const Color(0xFFF5F5F5)
                                : const Color(0xFF263238),
              ),
            ),
            if (c != null && (c.pend > 0 || c.sub > 0)) ...[
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (c.pend > 0) _countBadge(c.pend, true),
                    if (c.pend > 0 && c.sub > 0) const SizedBox(width: 3),
                    if (c.sub > 0) _countBadge(c.sub, false),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: context.secondaryTextColor),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(_focus.year, _focus.month, 1);
    final offset = firstDay.weekday - 1; // semana inicia lunes
    final daysInMonth = DateTime(_focus.year, _focus.month + 1, 0).day;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    var totalPend = 0;
    var totalSub = 0;
    for (var d = 1; d <= daysInMonth; d++) {
      final key = DateFormat('yyyy-MM-dd')
          .format(DateTime(_focus.year, _focus.month, d));
      final c = widget.counts[key];
      if (c != null) {
        totalPend += c.pend;
        totalSub += c.sub;
      }
    }

    final rawMonth = DateFormat('MMMM yyyy', 'es').format(_focus);
    final monthLabel = rawMonth.isEmpty
        ? rawMonth
        : rawMonth[0].toUpperCase() + rawMonth.substring(1);

    return Dialog(
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header: mes/año + navegación
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _changeMonth(-1),
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: Text(
                      monthLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.primaryTextColor,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => _changeMonth(1),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              // Totales del mes
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _countBadge(totalPend, true),
                  const SizedBox(width: 6),
                  _countBadge(totalSub, false),
                ],
              ),
              const SizedBox(height: 10),
              // Días de la semana
              Row(
                children: _weekdays
                    .map(
                      (w) => Expanded(
                        child: Text(
                          w,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? const Color(0xFFCFCFCF)
                                : const Color(0xFF263238),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 4),
              // Grilla del mes
              LayoutBuilder(
                builder: (context, constraints) {
                  final cellW = constraints.maxWidth / 7;
                  return Wrap(
                    children: [
                      for (var i = 0; i < offset; i++)
                        SizedBox(width: cellW, height: 52),
                      for (var d = 1; d <= daysInMonth; d++)
                        _dayCell(cellW, d),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              // Leyenda
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _legendDot(const Color(0xFFE65100), 'Pendientes'),
                  const SizedBox(width: 14),
                  _legendDot(const Color(0xFF2E7D32), 'Subidos'),
                ],
              ),
              const SizedBox(height: 12),
              // Acciones
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _selected == null
                        ? null
                        : () => Navigator.pop(context, _selected),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor:
                          AppColors.primary.withValues(alpha: 0.4),
                    ),
                    child: const Text(
                      'Subir',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
