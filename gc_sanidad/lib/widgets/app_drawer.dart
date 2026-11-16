import 'package:flutter/material.dart';
import 'package:gc_puesto_mercado_tienda/screens/listado_envios_screen.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../screens/dashboard_tracking_screen.dart';
import '../screens/registro_envio_muestra_screen.dart';

import '../screens/resultado_analisis_screen.dart';
import '../screens/scan_screen.dart';
import '../screens/seguimiento_envio.dart';
import '../services/catalog_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../screens/dashboard_screen.dart';
import '../screens/login_screen.dart';
import '../services/api_service.dart';
import '../utils/toast_helper.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _itemsController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  final List<Animation<double>> _itemAnimations = [];
  final List<Animation<Offset>> _itemSlideAnimations = [];

  bool _isExpanded = false;
  String? _userRol;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _itemsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, .6, curve: Curves.easeOut),
      ),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(-0.3, 0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    for (int i = 0; i < 6; i++) {
      final delay = i * 0.1;
      _itemAnimations.add(
        Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(
            parent: _itemsController,
            curve: Interval(delay, .6 + delay, curve: Curves.easeOutCubic),
          ),
        ),
      );
      _itemSlideAnimations.add(
        Tween<Offset>(begin: const Offset(-0.5, 0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _itemsController,
            curve: Interval(delay, .6 + delay, curve: Curves.easeOutCubic),
          ),
        ),
      );
    }
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    final storage = context.read<StorageService>();
    final rol = await storage.getRol();
    if (!mounted) return;

    setState(() {
      _userRol = rol;
    });

    // Iniciar animaciones después de cargar el rol
    _animationController.forward();
    _itemsController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _itemsController.dispose();
    super.dispose();
  }

  Future<void> _syncPendingRecords(BuildContext context) async {
    final bool hasInternet = await _checkInternetConnection();
    if (!hasInternet) {
      if (!mounted) return;
      showErrorToast(context, 'No hay conexión a internet');
      return;
    }

    final storage = context.read<StorageService>();
    final pendingRecords = storage.getRecordsPendientes(AppStrings.formType1);

    if (pendingRecords.isEmpty) {
      if (!mounted) return;
      showInfoToast(context, 'No hay registros pendientes por subir');
      return;
    }

    if (!mounted) return;
    showInfoToast(context, 'Subiendo ${pendingRecords.length} registros...');

    try {
      final String userCode = await storage.getUserCodeSync() ?? 'app_movil';
      final now = _formatDateTime(DateTime.now());

      final updatedList = pendingRecords.map((r) {
        final updated = Map<String, dynamic>.from(r);
        updated['usuarioTransferencia'] = userCode;
        updated['fechaHoraTransferencia'] = now;
        return updated;
      }).toList();

      final payload = {AppStrings.formType1: updatedList};
      final apiService = ApiService();
      final result = await apiService.uploadMultiple(payload);

      if (!mounted) return;
      if (result['success'] == true) {
        final generados =
            result['detalle']['envios_muestras']['codigosGenerados'] as List;

        if (generados.isNotEmpty) {
          // Crear un mapa: id_local codigoEnvio_real
          final Map<String, String> codigoPorId = {};
          for (var item in generados) {
            final id = item['id'] as String?;
            final codigo = item['codigoEnvio'] as String?;
            if (id != null && codigo != null) {
              codigoPorId[id] = codigo;
            }
          }

          // 1. Obtén la lista COMPLETA de registros (no solo los pendientes)
          final allRecords = storage.getAllRecords(AppStrings.formType1);

          // 2. Crea una nueva lista con los registros actualizados donde aplique
          final updatedAllRecords = <Map<String, dynamic>>[];

          for (final record in allRecords) {
            final id = record['id'] as String?;
            if (id != null && codigoPorId.containsKey(id)) {
              // Este registro fue enviado: actualiza sus campos
              final updatedRecord = Map<String, dynamic>.from(record);
              updatedRecord['codigoEnvio'] = codigoPorId[id];
              updatedRecord['synced'] = true;
              updatedAllRecords.add(updatedRecord);
            } else {
              // No fue enviado (o ya estaba sincronizado): mantén tal cual
              updatedAllRecords.add(record);
            }
          }

          // 3. Guarda la lista completa actualizada (sin duplicar, sin perder nada)
          await storage.updateRecords(AppStrings.formType1, updatedAllRecords);
        }

        await storage.setLastSyncDate();
        if (!mounted) return;
        showSuccessToast(context, 'Información subida correctamente.');
      } else {
        if (!mounted) return;
        showErrorToast(context, 'Ocurrió un error al subir la información.');
      }
    } catch (e) {
      if (!mounted) return;
      showErrorToast(context, 'Ocurrió un error al subir la información.');
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

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
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
                    'GC SANIDAD',
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
                          textAlign: TextAlign.center,
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

  Widget _buildTransporteMenu() {
    return ListView(
      padding: EdgeInsets.only(
        top: 20,
        bottom: MediaQuery.paddingOf(context).bottom + 20,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'TRACKING',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        _DrawerItem(
          icon: Icons.dashboard,
          title: 'Dashboard Tracking',
          gradient: const LinearGradient(
            colors: [Color(0xFFD1F0E0), Color(0xFF3ABE8F)],
          ),
          onTap: () {
            Navigator.pop(context);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              Get.off(() => const DashboardTrackingScreen());
            });
          },
        ),
        _DrawerItem(
          icon: Icons.qr_code_scanner,
          title: 'Escaneo',
          gradient: const LinearGradient(
            colors: [Color(0xFFE6D5F2), Color(0xFF8A4FFF)],
          ),
          onTap: () {
            Navigator.pop(context);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              Get.off(() => const ScanScreen());
            });
          },
        ),
        _DrawerItem(
          icon: Icons.local_shipping_outlined,
          title: 'Seguimiento de Envío',
          gradient: const LinearGradient(
            colors: [Color(0xFF26C6DA), Color(0xFF4361EE)],
          ),
          onTap: () {
            Navigator.pop(context);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              Get.off(() => const SeguimientoEnvioScreen());
            });
          },
        ),
        const SizedBox(height: 24),
        // OPCIONES
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF6B6B), Color(0xFFFFE66D)],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'OPCIONES',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        _DrawerItem(
          icon: Icons.info_outline,
          title: AppStrings.menuAcercaDe,
          gradient: const LinearGradient(
            colors: [Color(0xFF4ECDC4), Color(0xFF2AB29F)],
          ),
          onTap: () => _showAcercaDe(context),
        ),
        _DrawerItem(
          icon: Icons.logout_outlined,
          title: AppStrings.menuCerrarSesion,
          gradient: const LinearGradient(
            colors: [Color(0xFFF85A5A), Color(0xFFE63946)],
          ),
          onTap: () => _handleCerrarSesion(context),
        ),
      ],
    );
  }

  Widget _buildMenuCompleto() {
    return ListView(
      padding: EdgeInsets.only(
        top: 20,
        bottom: MediaQuery.paddingOf(context).bottom + 20,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'PRINCIPAL',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        _DrawerItem(
          icon: Icons.dashboard,
          title: 'Dashboard',
          gradient: const LinearGradient(
            colors: [Color(0xFFD56EC8), Color(0xFFF28FB8)],
          ),
          onTap: () async {
            Navigator.pop(context);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              Get.off(() => const DashboardScreen());
            });
          },
        ),
        _DrawerItem(
          icon: Icons.inventory_outlined,
          title: 'Registro de Muestras',
          gradient: const LinearGradient(
            colors: [Color(0xFF4ECDC4), Color(0xFF2AB29F)],
          ),
          onTap: () async {
            Navigator.pop(context);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              Get.off(() => RegistroEnvioMuestraScreen());
            });
          },
        ),
        _DrawerItem(
          icon: Icons.science,
          title: 'Respuesta Laboratorio',
          gradient: const LinearGradient(
            colors: [Color(0xFFFB4A42), Color(0xFFF28C3E)],
          ),
          onTap: () async {
            Navigator.pop(context);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              Get.off(() => ResultadoAnalisisScreen());
            });
          },
        ),
        _DrawerItem(
          icon: Icons.bar_chart_outlined,
          title: 'Reportes',
          gradient: const LinearGradient(
            colors: [Color(0xFFA0D2FF), Color(0xFF3A86FF)],
          ),
          onTap: () async {
            Navigator.pop(context);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              Get.off(() => const ListadoEnviosScreen());
            });
          },
        ),
        _DrawerItem(
          icon: Icons.gps_fixed,
          title: 'Tracking',
          gradient: const LinearGradient(
            colors: [Color(0xFFFADADD), Color(0xFFE95184)],
          ),
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          trailing: Icon(
            _isExpanded ? Icons.expand_less : Icons.expand_more,
            color: AppColors.textSecondary,
            size: 20,
          ),
        ),
        if (_isExpanded) ...[
          _SubDrawerItem(
            icon: Icons.dashboard,
            title: 'Dashboard Tracking',
            gradient: const LinearGradient(
              colors: [Color(0xFFD1F0E0), Color(0xFF3ABE8F)],
            ),
            onTap: () {
              Navigator.pop(context);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) return;
                Get.off(() => const DashboardTrackingScreen());
              });
            },
          ),
          _SubDrawerItem(
            icon: Icons.qr_code_scanner,
            title: 'Escaneo',
            gradient: const LinearGradient(
              colors: [Color(0xFFE6D5F2), Color(0xFF8A4FFF)],
            ),
            onTap: () {
              Navigator.pop(context);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) return;
                Get.off(() => const ScanScreen());
              });
            },
          ),
          _SubDrawerItem(
            icon: Icons.local_shipping_outlined,
            title: 'Seguimiento de Envío',
            gradient: const LinearGradient(
              colors: [Color(0xFF26C6DA), Color(0xFF4361EE)],
            ),
            onTap: () {
              Navigator.pop(context);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) return;
                Get.off(() => const SeguimientoEnvioScreen());
              });
            },
          ),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.grey.shade300,
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF6B6B), Color(0xFFFFE66D)],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'OPCIONES',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        _DrawerItem(
          icon: Icons.info_outline,
          title: AppStrings.menuAcercaDe,
          gradient: const LinearGradient(
            colors: [Color(0xFF4ECDC4), Color(0xFF2AB29F)],
          ),
          onTap: () => _showAcercaDe(context),
        ),
        _DrawerItem(
          icon: Icons.logout_outlined,
          title: AppStrings.menuCerrarSesion,
          gradient: const LinearGradient(
            colors: [Color(0xFFF85A5A), Color(0xFFE63946)],
          ),
          onTap: () => _handleCerrarSesion(context),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              children: [
                // CABECERA CON GRADIENTE (original)
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
                          child: FutureBuilder<String?>(
                            future: Future.value(
                              context.read<StorageService>().getUserName(),
                            ),
                            builder: (context, snapshot) {
                              final userName = snapshot.data ?? 'USUARIO';
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withOpacity(
                                              0.3,
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
                                              'SANIDAD',
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
                                                userName,
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

                                  if (_userRol != 'TRANSPORTE') ...[
                                     const SizedBox(height: 28),
                                    // BOTONES DE SINCRONIZACIÓN
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
                                                          final bool
                                                          hasInternet =
                                                              await _checkInternetConnection();

                                                          if (!mounted) return;

                                                          if (!hasInternet) {
                                                            showErrorToast(
                                                              context,
                                                              'No hay conexión a internet',
                                                            );
                                                            return;
                                                          }

                                                          final catalogService =
                                                              context
                                                                  .read<
                                                                    CatalogService
                                                                  >();
                                                          bool
                                                          success = await catalogService
                                                              .downloadCatalogos(
                                                                tablas: [
                                                                  'laboratorios',
                                                                  'emp_trans',
                                                                  'muestras',
                                                                  'paquetes',
                                                                  'analisis',
                                                                ],
                                                              );
                                                          if (!mounted) return;

                                                          if (success) {
                                                            await storage
                                                                .setLastDownloadDate();
                                                            if (!mounted)
                                                              return;
                                                            showSuccessToast(
                                                              context,
                                                              'Información descargada con éxito',
                                                            );
                                                          } else {
                                                            showErrorToast(
                                                              context,
                                                              'Error al descargar información',
                                                            );
                                                          }
                                                        },
                                                      ),
                                                    ),

                                                    const SizedBox(width: 20),

                                                    Expanded(
                                                      child: _SyncButton(
                                                        icon: Icons
                                                            .cloud_upload_rounded,
                                                        label: 'Subir',
                                                        lastDate: lastSync,
                                                        pendienteCount: storage
                                                            .getRecordsPendientes(
                                                              AppStrings
                                                                  .formType1,
                                                            )
                                                            .length,
                                                        onTap: () async {
                                                          await _syncPendingRecords(
                                                            context,
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
                        colors: [AppColors.background, Colors.white],
                      ),
                    ),
                    child: (_userRol == 'TRANSPORTE')
                        ? _buildTransporteMenu() // Widget cuando es TRANSPORTE
                        : _buildMenuCompleto(), // Widget cuando es otro rol
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
  final int? pendienteCount;
  final VoidCallback onTap;

  const _SyncButton({
    required this.icon,
    required this.label,
    required this.lastDate,
    this.pendienteCount, // opcional
    required this.onTap,
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
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withOpacity(0.25),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 26),
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
              const SizedBox(height: 4),
              Text(
                lastDate,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              // NUEVO: mensaje de registros pendientes
              if (pendienteCount != null && pendienteCount! > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '$pendienteCount registro${pendienteCount! > 1 ? 's' : ''} pendiente${pendienteCount! > 1 ? 's' : ''}',
                    style: TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Item principal del menú (como antes)
class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final LinearGradient gradient;
  final VoidCallback onTap;
  final Widget? trailing;

  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.gradient,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Icono con gradiente
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: gradient.colors[0].withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 16),
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
                // Trailing (opcional)
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Subitem (para submenús)
class _SubDrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final LinearGradient gradient;
  final VoidCallback onTap;

  const _SubDrawerItem({
    required this.icon,
    required this.title,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 4, 16, 4), // Indentado
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border(
                left: BorderSide(
                  color: gradient.colors.first.withOpacity(0.6),
                  width: 4,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              children: [
                // Icono con fondo redondeado
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                // Título
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.2,
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
