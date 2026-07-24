import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import '../screens/dashboard_screen.dart';
import '../screens/login_screen.dart';
import '../screens/register_seguimiento_screen.dart';
import '../screens/reports_screen.dart';
import '../services/api_service.dart';
import '../services/catalog_service.dart';
import '../services/catalog_sync_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/dialog_helper.dart';
import '../utils/dialog_utils.dart';
import '../utils/record_id.dart';
import '../utils/theme_colors.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).unfocus();
    });

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
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(-0.3, 0.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

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

    _animationController.forward();
    _itemsController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _itemsController.dispose();
    super.dispose();
  }

  /// Contexto de la pantalla (Scaffold) que sigue montado al cerrar el drawer.
  BuildContext _screenContext(BuildContext drawerContext) =>
      Scaffold.of(drawerContext).context;

  Future<bool> _hasInternet() async {
    try {
      final r = await InternetAddress.lookup('google.com');
      return r.isNotEmpty;
    } on SocketException {
      return false;
    }
  }

  Future<void> _downloadCatalogs(BuildContext hostContext) async {
    final close = showChickenLoadingDialog(hostContext, 'Descargando Información...');
    try {
      final storage = hostContext.read<StorageService>();
      final catalog = hostContext.read<CatalogService>();
      final result = await CatalogSyncService().syncAll(
        storage: storage,
        catalog: catalog,
        forzar: true,
      );
      close();
      if (!hostContext.mounted) return;
      if (!result.hadInternet) {
        showErrorToast(
          hostContext,
          '${AppStrings.sinConexion} Se usan los catálogos guardados.',
        );
      } else if (result.downloadedAnything) {
        showSuccessToast(hostContext, AppStrings.descargaExitosa);
      } else {
        showErrorToast(
          hostContext,
          'No se pudo actualizar. Se usan los catálogos guardados.',
        );
      }
    } catch (e) {
      close();
      if (hostContext.mounted) {
        showErrorToast(hostContext, 'Error: $e');
      }
    }
  }

  Future<void> _uploadByDate(BuildContext hostContext) async {
    final date = await showDatePicker(
      context: hostContext,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date == null) return;
    if (!await _hasInternet()) {
      showErrorToast(hostContext, AppStrings.sinConexion);
      return;
    }

    final storage = hostContext.read<StorageService>();
    final records = storage.getRecordsByDate(date);
    if (records.isEmpty) {
      showInfoToast(hostContext, 'No hay registros para esa fecha.');
      return;
    }

    final close = showChickenLoadingDialog(hostContext, 'Subiendo registros...');
    final api = ApiService();
    var ok = 0;
    var fail = 0;

    try {
      for (final record in records) {
        final isUpdate = record['guardado_backend'] == true ||
            record['guardado_backend'] == 'true';
        final result = await api.uploadSeguimiento(record, isUpdate: isUpdate);
        if (result['success'] == true) {
          await storage.markRecordAsSynced({
            ...record,
            'id': EvidenciaRecordId.of(record),
            'guardado_backend': true,
          });
          ok++;
        } else {
          fail++;
        }
      }
      await storage.setLastSyncDate();
      close();
      if (fail == 0) {
        showSuccessToast(hostContext, AppStrings.subidaExitosa);
      } else {
        showWarningToast(
          hostContext,
          'Subidos: $ok, fallidos: $fail',
        );
      }
    } catch (e) {
      close();
      if (hostContext.mounted) {
        showErrorToast(hostContext, 'Error: $e');
      }
    }
  }

  Future<void> _logout(BuildContext hostContext) async {
    final confirm = await showAppDialog<bool>(
      context: hostContext,
      builder: (ctx) => AlertDialog(
        title: Text('Cerrar sesión', style: TextStyle(color: ctx.textThemePrimary)),
        content: Text(
          '¿Está seguro que desea cerrar sesión?',
          style: TextStyle(color: ctx.textThemeMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!hostContext.mounted) return;
    await hostContext.read<StorageService>().clearAll();
    Get.offAll(() => const LoginScreen());
  }

  void _showAcercaDe(BuildContext context) {
    showAppDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 12,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.accent.withValues(alpha: 0.2),
                    AppColors.accentLight.withValues(alpha: 0.1),
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
            Text(
              'Acerca de',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 19,
                color: ctx.textThemePrimary,
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
                color: ctx.isAppDark
                    ? const Color(0xFF1E1E1E)
                    : AppColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ctx.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppConstants.appTitle,
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
                          color: AppColors.accent.withValues(alpha: 0.15),
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
                        color: ctx.textThemeSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Desarrollado por ${AppConstants.appDeveloper}',
                          style: TextStyle(
                            color: ctx.textThemeSecondary,
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
                onPressed: () => Navigator.pop(ctx),
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

  @override
  Widget build(BuildContext context) {
    final isDark = context.isAppDark;
    final storage = context.watch<StorageService>();
    final pending = storage.getPendingCount();
    final userName = storage.getUserName() ?? 'USUARIO';

    return Drawer(
      elevation: 0,
      backgroundColor: context.scaffoldMuted,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: AppColors.headerGradient,
                    boxShadow: AppColors.strongShadow,
                  ),
                  child: Stack(
                    children: [
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.25),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.5),
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.1),
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
                                      errorBuilder: (context, error, stackTrace) {
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
                                            color:
                                                Colors.white.withOpacity(0.98),
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
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                Colors.white.withOpacity(0.2),
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
                              Row(
                                children: [
                                  Expanded(
                                    child: _SyncButton(
                                      icon: Icons.cloud_download_rounded,
                                      label: 'Descargar',
                                      lastDate: '--/--/--',
                                      onTap: () async {
                                        final hostContext = _screenContext(context);
                                        Navigator.pop(context);
                                        await _downloadCatalogs(hostContext);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: _SyncButton(
                                      icon: Icons.cloud_upload_rounded,
                                      label: 'Subir',
                                      lastDate: '--/--/--',
                                      pendingCount: pending,
                                      onTap: () async {
                                        final hostContext = _screenContext(context);
                                        Navigator.pop(context);
                                        await _uploadByDate(hostContext);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
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
                        colors: isDark
                            ? [
                                const Color(0xFF1A1A1A),
                                const Color(0xFF121212),
                              ]
                            : [
                                AppColors.background.withValues(alpha: 0.3),
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
                                    color: context.textThemePrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _DrawerItem(
                            icon: Icons.dashboard_rounded,
                            title: AppStrings.menuDashboard,
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF4CAF50),
                                Color(0xFF66BB6A),
                                Color(0xFF81C784),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!context.mounted) return;
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
                            icon: Icons.edit_note_rounded,
                            title: AppStrings.menuRegistro,
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF26A69A),
                                Color(0xFF4DB6AC),
                                Color(0xFF80CBC4),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!context.mounted) return;
                                Get.off(
                                  () => const RegisterSeguimientoScreen(),
                                  transition: Transition.fadeIn,
                                  duration: const Duration(milliseconds: 600),
                                  curve: Curves.easeInOut,
                                );
                              });
                            },
                          ),
                          _DrawerItem(
                            icon: Icons.assessment_outlined,
                            title: AppStrings.menuReportes,
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF42A5F5),
                                Color(0xFF64B5F6),
                                Color(0xFF90CAF9),
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
                                      colors: [
                                        AppColors.accent,
                                        AppColors.accentLight
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(2),
                                    boxShadow: AppColors.lightShadow,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Opciones',
                                  style: TextStyle(
                                    color: context.textThemePrimary,
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
                            title: 'Acerca de',
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF66BB6A),
                                Color(0xFF81C784),
                                Color(0xFFA5D6A7),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            onTap: () => _showAcercaDe(context),
                          ),
                          _DrawerItem(
                            icon: Icons.logout_rounded,
                            title: AppStrings.menuCerrarSesion,
                            gradient: const LinearGradient(
                              colors: [AppColors.error, AppColors.errorDark],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            onTap: () {
                              final hostContext = _screenContext(context);
                              Navigator.pop(context);
                              _logout(hostContext);
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
                                const Color(0xFF4CAF50).withOpacity(0.8),
                                const Color(0xFF66BB6A).withOpacity(0.6),
                              ]
                            : [
                                const Color(0xFF26A69A).withOpacity(0.8),
                                const Color(0xFF4DB6AC).withOpacity(0.6),
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
                  if (label == 'Subir' &&
                      pendingCount != null &&
                      pendingCount! > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
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
    final isDark = context.isAppDark;
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
              color: context.surfaceCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? context.borderSubtle
                    : AppColors.primary.withValues(alpha: 0.2),
                width: 1.5,
              ),
              boxShadow: context.cardShadow(blur: 8, dy: 2),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: gradient.colors[0].withValues(alpha: 0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.textThemePrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
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
