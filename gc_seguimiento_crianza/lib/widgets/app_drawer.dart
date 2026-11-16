import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../screens/dashboard_screen.dart';
import '../screens/login_screen.dart';
import '../screens/register_seguimiento_screen.dart';
import '../screens/reports_screen.dart';
import '../services/api_service.dart';
import '../services/app_version_service.dart';
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
        includeUsuariosConempre: true,
      );
      close();
      if (!hostContext.mounted) return;
      if (!result.hadInternet) {
        showErrorToast(
          hostContext,
          '${AppStrings.sinConexion} Se usarán los datos guardados.',
        );
      } else if (result.cencosOk && result.catalogosOk) {
        showSuccessToast(hostContext, AppStrings.descargaExitosa);
        if (result.fecIngWarning != null) {
          showWarningToast(hostContext, result.fecIngWarning!);
        }
      } else if (result.cencosOk || result.catalogosOk) {
        showWarningToast(
          hostContext,
          result.catalogosOk
              ? 'CENCOS/galpones no se actualizaron; usuarios sí.'
              : 'CENCOS actualizados; usuarios/conempre no se descargaron.',
        );
        if (result.fecIngWarning != null) {
          showWarningToast(hostContext, result.fecIngWarning!);
        }
      } else {
        showErrorToast(
          hostContext,
          result.errorMessage?.isNotEmpty == true
              ? 'No se pudo descargar: ${result.errorMessage}'
              : 'No se pudo descargar. Verifique conexión e intente de nuevo.',
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
    final storage = hostContext.read<StorageService>();

    // Conteos compactos por día: pendientes (P) y subidos (S)
    final counts = <String, ({int pend, int sub})>{};
    for (final r in storage.getMyRecords()) {
      final fecha = r['fecha']?.toString() ?? '';
      if (fecha.length < 10) continue;
      final key = fecha.substring(0, 10);
      final e = counts[key];
      final esSubido = r['synced'] == true;
      counts[key] = e == null
          ? (esSubido ? (pend: 0, sub: 1) : (pend: 1, sub: 0))
          : (esSubido
              ? (pend: e.pend, sub: e.sub + 1)
              : (pend: e.pend + 1, sub: e.sub));
    }

    final date = await _pickUploadDate(hostContext, counts);
    if (date == null) return;
    if (!await _hasInternet()) {
      showErrorToast(hostContext, AppStrings.sinConexion);
      return;
    }

    final records = storage.getMyRecordsByDate(date);
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
        debugPrint(
          '[subir desde drawer] respuesta: $result '
          '(id=${EvidenciaRecordId.of(record)})',
        );
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
      if (ok > 0) {
        await storage.setLastSyncDate();
      }
      close();
      if (fail == 0) {
        showSuccessToast(hostContext, AppStrings.subidaExitosa);
      } else {
        showWarningToast(
          hostContext,
          'Subidos: $ok, fallidos: $fail',
        );
      }
      // La subida nunca se bloquea por version: el avance del usuario no se
      // pierde. Solo se le recuerda que debe actualizar para seguir registrando.
      if (hostContext.mounted) {
        await AppVersionService.notifyIfNeeded(hostContext, storage);
      }
    } catch (e) {
      close();
      if (hostContext.mounted) {
        showErrorToast(hostContext, 'Error: $e');
      }
    }
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
        lastDate: DateTime.now(),
      ),
    );
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
    await hostContext.read<StorageService>().clearSession();
    await hostContext.read<CatalogService>().loadFromPrefs();
    Get.offAll(() => const LoginScreen());
  }

  Future<void> _showAcercaDe(BuildContext context) async {
    final storage = context.read<StorageService>();
    final sync = CatalogSyncService();
    if (await sync.hasInternet()) {
      await sync.syncAppInfo(storage: storage);
    }
    if (!context.mounted) return;

    final appInfo = storage.getAppInfo();
    final mejoras = AppVersionService.parseMejorasUsuario(appInfo);
    final versionServidor = (appInfo?['required_version'] ?? '').toString().trim();

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
                      if (versionServidor.isNotEmpty &&
                          versionServidor != AppConstants.appVersion) ...[
                        const SizedBox(width: 8),
                        Text(
                          '· disponible v$versionServidor',
                          style: TextStyle(
                            color: ctx.textThemeMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
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
                  if (mejoras.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Novedades',
                      style: TextStyle(
                        color: ctx.textThemePrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...mejoras.map(
                      (texto) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 16,
                              color: AppColors.accent.withValues(alpha: 0.9),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                texto,
                                style: TextStyle(
                                  color: ctx.textThemeSecondary,
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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
    final pending = storage.getMyPendingCount();
    final lastDownloadDate = storage.lastDownloadDateDisplay;
    final lastUploadDate = storage.lastSyncDateDisplay;
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
                                      lastDate: lastDownloadDate,
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
                                      lastDate: lastUploadDate,
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

  static bool _fechaTieneValor(String lastDate) =>
      lastDate.isNotEmpty && lastDate != '--/--/--';

  static String? _fechaSubtitulo(String label, String lastDate) {
    if (_fechaTieneValor(lastDate)) return lastDate;
    if (label == 'Subir') return '--/--/--';
    return 'Sin descargar';
  }

  @override
  Widget build(BuildContext context) {
    final subtituloFecha = _fechaSubtitulo(label, lastDate);
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
              if (subtituloFecha != null && subtituloFecha.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  subtituloFecha,
                  style: TextStyle(
                    color: _SyncButton._fechaTieneValor(lastDate)
                        ? Colors.white.withOpacity(0.95)
                        : Colors.white.withOpacity(0.55),
                    fontSize: 11,
                    fontWeight: _SyncButton._fechaTieneValor(lastDate)
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
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

/// Calendario compacto para la subida: muestra por día los registros
/// pendientes (P, naranja) y subidos (S, verde) del usuario actual.
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
                                : const Color(0xFF101D14),
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
          style: TextStyle(fontSize: 11, color: context.textThemeSecondary),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(_focus.year, _focus.month, 1);
    final offset = firstDay.weekday - 1; // semana inicia lunes
    final daysInMonth = DateTime(_focus.year, _focus.month + 1, 0).day;

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
      backgroundColor: context.dialogSurface,
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
                        color: context.textThemePrimary,
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
                            color: Theme.of(context).brightness ==
                                    Brightness.dark
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
                  _legendDot(AppColors.primary, 'Subidos'),
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
