import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../screens/diagnostico_screen.dart';
import '../screens/enrolar_screen.dart';
import '../screens/login_screen.dart';
import '../screens/eventos_screen.dart';
import '../screens/personal_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/verificacion_screen.dart';
import '../services/api_service.dart';
import '../services/app_version_service.dart';
import '../services/eventos_sync_service.dart';
import '../services/nomina_store.dart';
import '../services/nomina_sync_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/dialog_helper.dart';
import '../utils/dialog_utils.dart';
import '../utils/theme_colors.dart';
import '../utils/toast_helper.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(-0.08, 0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

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

  Future<void> _download(BuildContext hostContext) async {
    final storage = hostContext.read<StorageService>();
    final store = hostContext.read<NominaStore>();
    if (!await _hasInternet()) {
      if (hostContext.mounted) {
        showErrorToast(hostContext, AppStrings.sinConexion);
      }
      return;
    }
    final close = showAppLoadingDialog(hostContext, 'Descargando...');
    try {
      final api = ApiService();
      final res = await api.downloadCatalogos(tablas: ['usuarios', 'conempre']);
      var ok = false;
      if (res['success'] == true && res['data'] is Map) {
        final raw = Map<String, dynamic>.from(res['data'] as Map);
        final actual = storage.getCatalogos();
        for (final t in ['usuarios', 'conempre']) {
          if (raw.containsKey(t)) actual[t] = raw[t];
        }
        await storage.saveCatalogos(actual);
        ok = true;
      }
      final info = await api.downloadAppInfo(
        versionWarningDesde: AppVersionService.warningDesdeForApi(storage),
      );
      if (info['success'] == true && info['data'] is Map) {
        await AppVersionService.mergeServerPayload(
          storage,
          Map<String, dynamic>.from(info['data'] as Map),
        );
      }
      final nomina = await NominaSyncService().syncAll(
        storage: storage,
        store: store,
      );
      if (ok) await storage.setLastDownloadDate();
      close();
      if (!hostContext.mounted) return;
      if (!nomina.hadInternet) {
        showErrorToast(hostContext, AppStrings.sinConexion);
        return;
      }
      if (nomina.errorMessage != null) {
        showErrorToast(
          hostContext,
          nomina.errorMessage ?? 'No se pudo descargar.',
        );
        return;
      }
      final partes = [
        'Altas: ${nomina.altas}',
        'Bajas: ${nomina.bajas}',
        'Total: ${nomina.total}',
      ];
      if (nomina.omitidos > 0) partes.add('Omitidas: ${nomina.omitidos}');
      showSuccessToast(hostContext, partes.join(' · '));
    } catch (e) {
      close();
      if (hostContext.mounted) showErrorToast(hostContext, 'Error: $e');
    }
  }

  Future<void> _upload(BuildContext hostContext) async {
    final storage = hostContext.read<StorageService>();
    if (storage.eventosPendientesCount() == 0) {
      showInfoToast(hostContext, 'Sin registros.');
      return;
    }
    if (!await _hasInternet()) {
      if (hostContext.mounted) {
        showErrorToast(hostContext, AppStrings.sinConexion);
      }
      return;
    }
    final close = showAppLoadingDialog(hostContext, 'Subiendo...');
    try {
      final r = await EventosSyncService.enviar(storage);
      close();
      if (!hostContext.mounted) return;
      if (r.fallidos == 0 && r.subidos > 0) {
        showSuccessToast(hostContext, AppStrings.subidaExitosa);
      } else if (r.subidos > 0) {
        showWarningToast(
          hostContext,
          'Subidos: ${r.subidos}, fallidos: ${r.fallidos}',
        );
      } else {
        showErrorToast(hostContext, r.errorMessage ?? 'No se pudo subir.');
      }
    } catch (e) {
      close();
      if (hostContext.mounted) showErrorToast(hostContext, 'Error: $e');
    }
  }

  Future<void> _logout(BuildContext hostContext) async {
    final confirm = await showAppDialog<bool>(
      context: hostContext,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Cerrar sesión',
          style: TextStyle(color: ctx.textThemePrimary),
        ),
        content: Text(
          '¿Cerrar sesión?',
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
    if (confirm != true || !hostContext.mounted) return;
    await hostContext.read<StorageService>().clearSession();
    Get.offAll(() => const SplashScreen());
  }

  Future<void> _acercaDe(BuildContext hostContext) async {
    final storage = hostContext.read<StorageService>();
    if (await _hasInternet()) {
      final info = await ApiService().downloadAppInfo(
        versionWarningDesde: AppVersionService.warningDesdeForApi(storage),
      );
      if (info['success'] == true && info['data'] is Map) {
        await AppVersionService.mergeServerPayload(
          storage,
          Map<String, dynamic>.from(info['data'] as Map),
        );
      }
    }
    if (!hostContext.mounted) return;
    final appInfo = storage.getAppInfo();
    final mejoras = AppVersionService.parseMejorasUsuario(appInfo);
    final versionServidor = (appInfo?['required_version'] ?? '')
        .toString()
        .trim();
    final context = hostContext;
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
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.info_rounded,
                color: AppColors.primaryDark,
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
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ctx.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    AppConstants.appTitle,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: AppColors.primaryDark,
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
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'v${AppConstants.appVersion}',
                          style: const TextStyle(
                            color: AppColors.primaryDark,
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
                            const Icon(
                              Icons.check_circle_outline,
                              size: 16,
                              color: AppColors.primary,
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

  bool _activa(String route) => Get.currentRoute == route;

  void _ir(BuildContext drawerContext, String route, Widget Function() page) {
    Navigator.pop(drawerContext);
    if (_activa(route)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route == '/verificacion') {
        Get.offAll(page, routeName: route);
      } else {
        Get.to(page, routeName: route);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final pending = storage.eventosPendientesCount();
    final logged = storage.isLoggedInSync;
    final userName = logged
        ? (storage.getUserName() ?? 'USUARIO')
        : 'MODO ESCÁNER';

    return Drawer(
      elevation: 0,
      backgroundColor: context.scaffoldMuted,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
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
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  width: 2,
                                ),
                              ),
                              child: Image.asset(
                                'assets/images/logo_grs.png',
                                width: 46,
                                height: 46,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.face_rounded,
                                  size: 40,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    userName.toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      height: 1.3,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.2,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      AppConstants.companyName,
                                      style: TextStyle(
                                        color: Colors.white,
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
                        if (logged) ...[
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: _SyncCloud(
                                  icon: Icons.cloud_download_rounded,
                                  label: 'Descargar',
                                  lastDate: storage.lastDownloadDateDisplay,
                                  aviso: storage.needsNominaUpdate,
                                  onTap: () async {
                                    final host = _screenContext(context);
                                    Navigator.pop(context);
                                    await _download(host);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _SyncCloud(
                                  icon: Icons.cloud_upload_rounded,
                                  label: 'Subir',
                                  lastDate: storage.lastSyncDateDisplay,
                                  pendingCount: pending,
                                  onTap: () async {
                                    final host = _screenContext(context);
                                    Navigator.pop(context);
                                    await _upload(host);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.only(
                    top: 12,
                    bottom: 24 + MediaQuery.of(context).viewPadding.bottom,
                  ),
                  children: [
                    _item(
                      icon: Icons.face_rounded,
                      title: AppStrings.menuVerificacion,
                      gradient: AppColors.primaryGradient,
                      activo:
                          _activa('/verificacion') || Get.currentRoute == '/',
                      onTap: () => _ir(
                        context,
                        '/verificacion',
                        () => const VerificacionScreen(),
                      ),
                    ),
                    // Sin sesión el drawer es reducido: solo escaneo,
                    // login y Acerca de. El resto es del supervisor.
                    if (logged) ...[
                      _item(
                        icon: Icons.history_rounded,
                        title: AppStrings.menuEventos,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF164072), Color(0xFF1A7FA8)],
                        ),
                        activo: _activa('/eventos'),
                        onTap: () => _ir(
                          context,
                          '/eventos',
                          () => const EventosScreen(),
                        ),
                      ),
                      _item(
                        icon: Icons.people_rounded,
                        title: AppStrings.menuPersonal,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1A7FA8), Color(0xFF56BFE4)],
                        ),
                        activo: _activa('/personal'),
                        onTap: () => _ir(
                          context,
                          '/personal',
                          () => const PersonalScreen(),
                        ),
                      ),
                      if (storage.getPuedeEnrolar())
                        _item(
                          icon: Icons.person_add_rounded,
                          title: AppStrings.menuEnrolar,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF15803D), Color(0xFF22C55E)],
                          ),
                          activo: _activa('/enrolar'),
                          onTap: () => _ir(
                            context,
                            '/enrolar',
                            () => const EnrolarScreen(),
                          ),
                        ),
                      _item(
                        icon: Icons.monitor_heart_rounded,
                        title: AppStrings.menuDiagnostico,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7C6CF2), Color(0xFFA78BFA)],
                        ),
                        activo: _activa('/diagnostico'),
                        onTap: () => _ir(
                          context,
                          '/diagnostico',
                          () => const DiagnosticoScreen(),
                        ),
                      ),
                      _sectionLabel(context, 'Sonido'),
                      _switch(
                        icon: Icons.volume_up_rounded,
                        title: 'Sonido',
                        value: storage.getSonido(),
                        onChanged: (v) => storage.saveSonido(v),
                      ),
                      _switch(
                        icon: Icons.record_voice_over_rounded,
                        title: 'Voz',
                        value: storage.getVoz(),
                        onChanged: (v) => storage.saveVoz(v),
                      ),
                      _switch(
                        icon: Icons.vibration_rounded,
                        title: 'Vibración',
                        value: storage.getVibracion(),
                        onChanged: (v) => storage.saveVibracion(v),
                      ),
                    ],
                    _sectionLabel(context, 'Opciones'),
                    _item(
                      icon: Icons.info_rounded,
                      title: 'Acerca de',
                      gradient: const LinearGradient(
                        colors: [Color(0xFF5FB8DE), Color(0xFF35A7D4)],
                      ),
                      onTap: () {
                        final host = _screenContext(context);
                        Navigator.pop(context);
                        _acercaDe(host);
                      },
                    ),
                    if (!logged)
                      _item(
                        icon: Icons.login_rounded,
                        title: AppStrings.loginTitle,
                        gradient: AppColors.primaryGradient,
                        onTap: () =>
                            _ir(context, '/login', () => const LoginScreen()),
                      )
                    else
                      _item(
                        icon: Icons.logout_rounded,
                        title: AppStrings.menuCerrarSesion,
                        gradient: const LinearGradient(
                          colors: [AppColors.error, AppColors.rechazadoDark],
                        ),
                        onTap: () {
                          final host = _screenContext(context);
                          Navigator.pop(context);
                          _logout(host);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              color: context.textThemePrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _switch({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: context.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.borderSubtle, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 16),
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
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _item({
    required IconData icon,
    required String title,
    required LinearGradient gradient,
    required VoidCallback onTap,
    bool activo = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: activo
                  ? AppColors.primary.withValues(alpha: 0.18)
                  : context.surfaceCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: activo
                    ? AppColors.primary.withValues(alpha: 0.6)
                    : context.borderSubtle,
                width: 1.5,
              ),
              boxShadow: context.cardShadow(blur: 8, dy: 2),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: gradient.colors[0].withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: activo ? FontWeight.w700 : FontWeight.w600,
                      color: activo
                          ? AppColors.primary
                          : context.textThemePrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.2),
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

class _SyncCloud extends StatelessWidget {
  const _SyncCloud({
    required this.icon,
    required this.label,
    required this.lastDate,
    required this.onTap,
    this.pendingCount,
    this.aviso = false,
  });

  final IconData icon;
  final String label;
  final String lastDate;
  final VoidCallback onTap;
  final int? pendingCount;
  final bool aviso;

  @override
  Widget build(BuildContext context) {
    final tiene = lastDate.isNotEmpty && lastDate != '--/--/--';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: Colors.white, size: 30),
                if (aviso)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDE68A),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.priority_high_rounded,
                        color: Color(0xFFE36B45),
                        size: 12,
                      ),
                    ),
                  ),
                if (pendingCount != null && pendingCount! > 0)
                  Positioned(
                    right: -8,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3730A3),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text(
                        pendingCount! > 99 ? '99+' : '$pendingCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              tiene
                  ? lastDate
                  : (label == 'Descargar' ? 'Sin descargar' : '--/--/--'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (aviso)
              const Text(
                AppStrings.actualiceNomina,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFFDE68A),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
