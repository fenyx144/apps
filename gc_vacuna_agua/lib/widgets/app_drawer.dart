import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../screens/mi_granja_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/splash_screen.dart';
import '../services/api_service.dart';
import '../services/app_version_service.dart';
import '../services/catalog_service.dart';
import '../services/catalog_sync_service.dart';
import '../services/storage_service.dart';
import '../utils/bio_navigation.dart';
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

  /// Ítems animados del menú: dashboard + las secciones de los tres tipos de
  /// bioseguridad + reportes + «Mi granja» + «Acerca de» + «Cerrar sesión».
  ///
  /// El orden de los índices sigue el de `build`: 0 el dashboard, 1..N las
  /// secciones, y los cuatro últimos reportes, «Mi granja», «Acerca de» y
  /// «Cerrar sesión».
  int get _itemsAnimados =>
      5 + bioNavTipos.fold<int>(0, (total, tipo) => total + tipo.secciones.length);

  /// Grupos de bioseguridad desplegados en el menú.
  late final Set<String> _abiertos = _gruposIniciales();

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

    for (int i = 0; i < _itemsAnimados; i++) {
      // Arranque escalonado: cada ítem inicia un poco después del anterior.
      // El fin debe quedar dentro de [0, 1] o Curve lanza aserción.
      final begin = (i * 0.05).clamp(0.0, 1.0);
      final end = (begin + 0.6).clamp(0.0, 1.0);
      final curve = Interval(begin, end, curve: Curves.easeOutCubic);

      _itemAnimations.add(
        Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: _itemsController, curve: curve),
        ),
      );

      _itemSlideAnimations.add(
        Tween<Offset>(begin: const Offset(-0.5, 0.0), end: Offset.zero).animate(
          CurvedAnimation(parent: _itemsController, curve: curve),
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
    final close =
        showChickenLoadingDialog(hostContext, 'Descargando Información...');
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
      } else if (result.cencosOk &&
          result.catalogosOk &&
          result.vacunaCatalogosOk) {
        showSuccessToast(hostContext, AppStrings.descargaExitosa);
      } else if (result.cencosOk ||
          result.catalogosOk ||
          result.vacunaCatalogosOk) {
        // Se dice exactamente qué no se actualizó: antes salía «descarga
        // exitosa» aunque un catálogo hubiera fallado y el equipo se quedara
        // con los valores viejos.
        final faltan = <String>[
          if (!result.cencosOk) 'granjas/campañas',
          if (!result.catalogosOk) 'usuarios/conempre',
          if (!result.vacunaCatalogosOk) 'catálogos de Vacuna al Agua',
        ].join(', ');
        showWarningToast(hostContext, 'No se actualizaron: $faltan.');
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

    // Pendientes y ya enviados del día. Siempre va a guardar: el servidor
    // deduplica por el uuid (`id`), inserta lo nuevo y, si ya estaba, repara
    // las imágenes que no habían llegado.
    final records = storage.getMyRecordsByDate(date);
    if (records.isEmpty) {
      showInfoToast(hostContext, 'No hay registros para esa fecha.');
      return;
    }

    final close =
        showChickenLoadingDialog(hostContext, 'Subiendo registros...');
    final api = ApiService();
    var ok = 0;
    var fail = 0;

    try {
      for (final record in records) {
        final result = await api.uploadBioseguridad(record);
        debugPrint(
          '[subir desde drawer] respuesta: $result '
          '(id=${EvidenciaRecordId.of(record)})',
        );
        if (ApiService.subidaCompleta(result)) {
          await storage.markRecordAsSynced({
            ...record,
            'id': EvidenciaRecordId.of(record),
            'guardado_backend': true,
          });
          ok++;
        } else if (result['success'] == true) {
          // El uuid ya está en el servidor, pero faltan imágenes: queda
          // pendiente para que el próximo envío las repare.
          await storage.markRecordPending(record);
          fail++;
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
        showWarningToast(hostContext, 'Subidos: $ok, fallidos: $fail');
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
        title:
            Text('Cerrar sesión', style: TextStyle(color: ctx.textThemePrimary)),
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
    // Modo UI: no hay pantalla de login; se vuelve a entrar directo.
    Get.offAll(() => const SplashScreen());
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
    final versionServidor =
        (appInfo?['required_version'] ?? '').toString().trim();

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
                color: ctx.isAppDark
                    ? const Color(0xFF1E1E1E)
                    : AppColors.primary.withValues(alpha: 0.08),
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

  @override
  Widget build(BuildContext context) {
    final isDark = context.isAppDark;
    final storage = context.watch<StorageService>();
    final pending = storage.getMyPendingCount();
    final lastDownloadDate = storage.lastDownloadDateDisplay;
    final lastUploadDate = storage.lastSyncDateDisplay;
    final catalogStale = storage.needsCatalogUpdate;
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
                  decoration: const BoxDecoration(
                    gradient: AppColors.headerGradient,
                    boxShadow: AppColors.strongShadow,
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
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
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    width: 2,
                                  ),
                                ),
                                child: Image.asset(
                                  'assets/images/logo_grs.png',
                                  width: 46,
                                  height: 46,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.health_and_safety_rounded,
                                    size: 46,
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
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.98),
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        height: 1.3,
                                        letterSpacing: -0.3,
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
                                        color:
                                            Colors.white.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        AppConstants.companyName,
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.95),
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
                          const SizedBox(height: 18),
                          // Nubes compactas: sin recuadro por nube.
                          Row(
                            children: [
                              Expanded(
                                child: _SyncCloud(
                                  icon: Icons.cloud_download_rounded,
                                  label: 'Descargar',
                                  lastDate: lastDownloadDate,
                                  staleCatalogWarning: catalogStale,
                                  onTap: () async {
                                    final hostContext =
                                        _screenContext(context);
                                    Navigator.pop(context);
                                    await _downloadCatalogs(hostContext);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _SyncCloud(
                                  icon: Icons.cloud_upload_rounded,
                                  label: 'Subir',
                                  lastDate: lastUploadDate,
                                  etiquetaSinFecha: '--/--/--',
                                  pendingCount: pending,
                                  onTap: () async {
                                    final hostContext =
                                        _screenContext(context);
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
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: isDark
                            ? [const Color(0xFF1A1A1A), const Color(0xFF121212)]
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
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        children: [
                          _sectionLabel(context, 'Navegación', null),
                          _animatedItem(
                            0,
                            _DrawerItem(
                              icon: Icons.dashboard_rounded,
                              title: AppStrings.menuDashboard,
                              gradient: AppColors.primaryGradient,
                              activo: _rutaActiva(BioNavigation.rutas['dashboard']),
                              onTap: () => _goAndReset(context, 'dashboard'),
                            ),
                          ),
                         /* _sectionLabel(
                            context,
                            'Registros',
                            Icons.assignment_outlined,
                          ),*/
                          for (final tipo in bioNavTipos)
                            ..._grupo(context, tipo),
                          // Reportes va después de los tres grupos, no junto al
                          // dashboard. La línea de arriba lo despega del último
                          // grupo para que no se lea como una sección de
                          // bioseguridad biológica.
                          _animatedItem(
                            _itemsAnimados - 4,
                            _DrawerItem(
                              icon: Icons.assessment_outlined,
                              title: AppStrings.menuReportes,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF164072), Color(0xFF1A7FA8)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              activo: _rutaActiva(BioNavigation.rutas['reportes']),
                              divisoriaSuperior: true,
                              onTap: () {
                                Navigator.pop(context);
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  Get.to(
                                    () => const ReportsScreen(),
                                    routeName: BioNavigation.rutas['reportes'],
                                    transition: Transition.rightToLeft,
                                    duration: const Duration(milliseconds: 300),
                                  );
                                });
                              },
                            ),
                          ),
                          _sectionLabel(context, 'Opciones', null),
                          _animatedItem(
                            _itemsAnimados - 3,
                            _DrawerItem(
                              icon: Icons.home_work_rounded,
                              title: AppStrings.menuMiGranja,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF1A7FA8), Color(0xFF56BFE4)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              activo: _rutaActiva(BioNavigation.rutas['miGranja']),
                              onTap: () {
                                Navigator.pop(context);
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  Get.to(
                                    () => const MiGranjaScreen(),
                                    routeName: BioNavigation.rutas['miGranja'],
                                    transition: Transition.rightToLeft,
                                    duration: const Duration(milliseconds: 300),
                                  );
                                });
                              },
                            ),
                          ),
                          _animatedItem(
                            _itemsAnimados - 2,
                            _DrawerItem(
                              icon: Icons.info_rounded,
                              title: 'Acerca de',
                              gradient: const LinearGradient(
                                colors: [Color(0xFF5FB8DE), Color(0xFF35A7D4)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              onTap: () => _showAcercaDe(context),
                            ),
                          ),
                          _animatedItem(
                            _itemsAnimados - 1,
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

  Widget _sectionLabel(BuildContext context, String text, IconData? icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          if (icon != null) ...[
            Icon(icon, size: 15, color: AppColors.primary),
            const SizedBox(width: 6),
          ],
          // Expanded: «Bioseguridad biológica» es más ancho que el drawer, así
          // que el encabezado se reparte en dos líneas en vez de desbordar.
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: context.textThemePrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _animatedItem(int index, Widget child) {
    if (index >= _itemAnimations.length) return child;
    return FadeTransition(
      opacity: _itemAnimations[index],
      child: SlideTransition(
        position: _itemSlideAnimations[index],
        child: child,
      ),
    );
  }

  /// Un grupo plegable: encabezado tocable y, si está abierto, sus secciones.
  ///
  /// Los grupos vienen plegados salvo el del tipo activo, para que el menú no
  /// sea una lista larguísima: física aporta las cuatro secciones y química y
  /// biológica una cada una. Los tres grupos comparten «Anomalías»; el ítem viaja
  /// con su tipo para que la pantalla abra con ese tipo ya elegido.
  List<Widget> _grupo(BuildContext context, BioNavTipo tipo) {
    final abierto = _abiertos.contains(tipo.id);
    return [
      _EncabezadoGrupo(
        tipo: tipo,
        abierto: abierto,
        onTap: () => setState(() {
          if (abierto) {
            _abiertos.remove(tipo.id);
          } else {
            _abiertos.add(tipo.id);
          }
        }),
      ),
      if (abierto)
        for (var i = 0; i < tipo.secciones.length; i++)
          _animatedItem(
            _indiceSeccion(tipo, i),
            _DrawerItem(
              icon: tipo.secciones[i].icon,
              title: tipo.secciones[i].label,
              gradient: _gradiente(tipo.id, tipo.secciones[i].id),
              indent: true,
              activo: _rutaActiva(
                BioNavigation.rutaDe(tipo.secciones[i].id, tipo: tipo.id),
              ),
              // Sin divisoria tras el último hijo: el encabezado del grupo
              // siguiente ya separa, y una línea más vuelve a meterlo en la lista.
              divisoria: i < tipo.secciones.length - 1,
              onTap: () => _goAndReset(
                context,
                tipo.secciones[i].id,
                tipo: tipo.id,
              ),
            ),
          ),
    ];
  }

  /// Índice de animación de una sección, contando las secciones de todos los
  /// grupos anteriores. Se calcula en vez de acumularse para que el índice no
  /// dependa de qué grupos estén desplegados en ese momento.
  int _indiceSeccion(BioNavTipo tipo, int dentroDelGrupo) {
    var indice = 1; // 0 = Mi Dashboard.
    for (final t in bioNavTipos) {
      if (identical(t, tipo)) return indice + dentroDelGrupo;
      indice += t.secciones.length;
    }
    return indice + dentroDelGrupo;
  }

  /// `true` si [ruta] es la pantalla en la que está parado el usuario.
  ///
  /// La comparación usa la ruta completa, que en Anomalías incluye el tipo
  /// (`/bio/anomalias/quimica`): sin eso, las tres «Anomalías» quedarían
  /// resaltadas a la vez.
  static bool _rutaActiva(String? ruta) =>
      ruta != null && Get.currentRoute == ruta;

  /// Grupos de bioseguridad con los que abre el menú.
  ///
  /// Se deduce de la ruta actual para que el grupo en el que está parado el
  /// usuario aparezca desplegado; si no se reconoce, se abre física, que es el
  /// único con varias secciones.
  Set<String> _gruposIniciales() {
    final ruta = Get.currentRoute;
    for (final tipo in bioNavTipos) {
      if (ruta.endsWith('/${tipo.id}')) return {tipo.id};
    }
    return {bioNavTipos.first.id};
  }

  /// Gradiente del ítem según la sección.
  static LinearGradient _gradiente(String tipo, String seccion) {
    switch (seccion) {
      case BioSecciones.decloracion:
        return const LinearGradient(
          colors: [Color(0xFF164072), Color(0xFF35A7D4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case BioSecciones.vacunacion:
        return const LinearGradient(
          colors: [Color(0xFF1A7FA8), Color(0xFF56BFE4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      default:
        return const LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  /// Navega a una sección desde el drawer (equivale a «ir y reiniciar»).
  ///
  /// La tabla de rutas y de pantallas vive en [BioNavigation], que es la misma
  /// que usa el resto de la app.
  void _goAndReset(BuildContext drawerContext, String route, {String? tipo}) {
    // Cierra el drawer primero; la navegación va en el siguiente frame para
    // no disponer el Scaffold mientras el drawer se está cerrando.
    Navigator.pop(drawerContext);
    BioNavigation.irEnSiguienteFrame(route, tipo: tipo);
  }
}

/// Nube compacta de sincronización (sin recuadro).
class _SyncCloud extends StatelessWidget {
  const _SyncCloud({
    required this.icon,
    required this.label,
    required this.lastDate,
    required this.onTap,
    this.pendingCount,
    this.staleCatalogWarning = false,
    this.etiquetaSinFecha = 'Sin descargar',
  });

  final IconData icon;
  final String label;
  final String lastDate;
  final VoidCallback onTap;
  final int? pendingCount;

  /// Muestra el aviso de catálogos vencidos (ver [AppConstants.staleCatalogDays]).
  final bool staleCatalogWarning;

  /// Texto bajo la nube si aún no hay fecha. `null` = no mostrar nada (p. ej. Subir).
  final String? etiquetaSinFecha;

  static bool _fechaTieneValor(String lastDate) =>
      lastDate.isNotEmpty && lastDate != '--/--/--';

  @override
  Widget build(BuildContext context) {
    final tiene = _fechaTieneValor(lastDate);
    final subtituloFecha =
        tiene ? lastDate : etiquetaSinFecha;
    final aviso = staleCatalogWarning && label == 'Descargar';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  color: aviso
                      ? const Color(0xFFFFE082)
                      : Colors.white.withValues(alpha: 0.97),
                  size: 30,
                ),
                if (aviso)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9800),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.priority_high_rounded,
                        color: Colors.white,
                        size: 12,
                      ),
                    ),
                  ),
                if (pendingCount != null && pendingCount! > 0)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      constraints: const BoxConstraints(minWidth: 18),
                      child: Text(
                        pendingCount! > 99 ? '99+' : pendingCount.toString(),
                        textAlign: TextAlign.center,
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
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.98),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subtituloFecha != null && subtituloFecha.isNotEmpty)
              Text(
                subtituloFecha,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: tiene ? 0.9 : 0.6),
                  fontSize: 10.5,
                  fontWeight: tiene ? FontWeight.w600 : FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            if (aviso) ...[
              const SizedBox(height: 2),
              Text(
                AppStrings.actualiceCatalogos,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFFFE082),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Encabezado plegable de un grupo de bioseguridad.
///
/// La flecha apunta hacia abajo con el grupo abierto y hacia la derecha con el
/// grupo plegado, como un acordeón.
class _EncabezadoGrupo extends StatelessWidget {
  const _EncabezadoGrupo({
    required this.tipo,
    required this.abierto,
    required this.onTap,
  });

  final BioNavTipo tipo;
  final bool abierto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              children: [
                Icon(tipo.icon, size: 17, color: AppColors.primaryDark),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tipo.label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: context.textThemePrimary,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: abierto ? 0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: context.textThemeMuted,
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

/// Fila del menú.
///
/// Sin tarjeta ni borde: la jerarquía la marcan la sangría y el tamaño del ícono,
/// y entre hermanos del mismo nivel va una línea fina. La fila de la sección
/// activa se resalta con un tinte, la barrita izquierda y el texto en azul.
class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.gradient,
    required this.onTap,
    this.indent = false,
    this.activo = false,
    this.divisoria = false,
    this.divisoriaSuperior = false,
  });

  final IconData icon;
  final String title;
  final LinearGradient gradient;
  final VoidCallback onTap;

  /// Ítem de segundo nivel: entra con sangría y con todo más chico.
  final bool indent;

  /// Sección en la que está parado el usuario.
  final bool activo;

  /// Dibuja la línea divisoria inferior, solo entre hermanos del mismo nivel.
  final bool divisoria;

  /// Dibuja la línea divisoria superior. Se usa cuando el ítem cierra un bloque
  /// distinto (Reportes tras los grupos de bioseguridad) y sin ella se leería
  /// como la última fila de ese bloque.
  final bool divisoriaSuperior;

  /// Margen que despega de los bordes el tinte de la fila activa.
  static const double _margen = 8;

  /// Ancho del carril donde vive la barrita de la sección activa.
  static const double _carril = 9;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isAppDark;

    // Geometría por nivel. `izquierda` es el sangrado absoluto del contenido;
    // `textoX` es dónde arranca el texto y, por lo tanto, la sangría con la que
    // se alinea la línea divisoria.
    final izquierda = indent ? 38.0 : 16.0;
    final ladoIcono = indent ? 28.0 : 34.0;
    final ladoGlifo = indent ? 15.0 : 19.0;
    final separacion = indent ? 12.0 : 14.0;
    final textoX = izquierda + _carril + ladoIcono + separacion;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (divisoriaSuperior)
          Divider(
            height: 1,
            thickness: 1,
            indent: textoX,
            endIndent: 16,
            color: isDark
                ? context.borderSubtle
                : AppColors.primary.withValues(alpha: 0.15),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _margen),
          child: Material(
            // El tinte de la fila activa lo dibuja el Material: respeta el
            // redondeo y deja pasar el ripple.
            color: activo
                ? AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: EdgeInsets.only(
                  left: izquierda - _margen,
                  right: 14,
                  top: indent ? 8 : 10,
                  bottom: indent ? 8 : 10,
                ),
                child: Row(
                  children: [
                    // Carril de la barrita: se reserva siempre para que el ícono
                    // no se corra al cambiar de sección.
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Container(
                        width: 3,
                        height: 20,
                        decoration: BoxDecoration(
                          gradient: activo ? AppColors.primaryGradient : null,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Container(
                      width: ladoIcono,
                      height: ladoIcono,
                      decoration: BoxDecoration(
                        gradient: gradient,
                        borderRadius: BorderRadius.circular(indent ? 9 : 11),
                      ),
                      child: Icon(icon, color: Colors.white, size: ladoGlifo),
                    ),
                    SizedBox(width: separacion),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: indent ? 14.5 : 15.5,
                          fontWeight: activo
                              ? FontWeight.w700
                              : (indent ? FontWeight.w500 : FontWeight.w600),
                          color: activo
                              ? AppColors.primaryDark
                              : context.textThemePrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (divisoria)
          Divider(
            height: 1,
            thickness: 1,
            indent: textoX,
            endIndent: 16,
            color: isDark
                ? context.borderSubtle
                : AppColors.primary.withValues(alpha: 0.15),
          ),
      ],
    );
  }
}

/// Calendario compacto para la subida: por día muestra registros pendientes
/// (P, naranja) y subidos (S, verde) del usuario actual.
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
      onTap: disabled ? null : () => setState(() => _selected = day),
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
                                : const Color(0xFF0F172A),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _countBadge(totalPend, true),
                  const SizedBox(width: 6),
                  _countBadge(totalSub, false),
                ],
              ),
              const SizedBox(height: 10),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _legendDot(const Color(0xFFE65100), 'Pendientes'),
                  const SizedBox(width: 14),
                  _legendDot(AppColors.primary, 'Subidos'),
                ],
              ),
              const SizedBox(height: 12),
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
