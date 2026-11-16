import 'package:flutter/material.dart';

class AppColors {
  // ── Marca verde: SOLO header superior, botones de acción y checks ──
  static const Color primary = Color(0xFF4CAF50);
  static const Color primaryLight = Color(0xFF81C784);
  static const Color primaryDark = Color(0xFF388E3C);
  static const Color primaryVibrant = Color(0xFF66BB6A);

  static const Color accent = Color(0xFF4CAF50);

  // ── Superficies ─────────────────────────────────────────────────
  // Claro: gris pizarra muy claro; Oscuro: azul marino profundo.
  static const Color background = Color(0xFFF8FAFC);
  static const Color cardBackground = Colors.white;
  static const Color darkBackground = Color(0xFF0F172A);
  // Azul pizarra para cards/superficies en modo oscuro.
  static const Color darkSurface = Color(0xFF1E293B);
  static const Color darkCard = Color(0xFF1E293B);

  // ── Bordes ──────────────────────────────────────────────────────
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color darkBorder = Color(0xFF334155);

  // ── Textos ──────────────────────────────────────────────────────
  // Claro: texto principal pizarra oscuro, secundario gris medio.
  static const Color textPrimary = Color(0xFF1E293B);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textOnPrimary = Colors.white;
  // Oscuro: blanco humo y gris azulado.
  static const Color darkTextPrimary = Color(0xFFF1F5F9);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextMuted = Color(0xFF64748B);

  static const Color error = Color(0xFFE57373);
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color info = Color(0xFF2196F3);
  static const Color iconAccent = Color(0xFF4CAF50);

  // ── Sexos: Machos índigo suave, Hembras coral suave ────────────
  static const Color maleAccent = Color(0xFF818CF8);
  static const Color maleAccentDark = Color(0xFFA5B4FC);
  static const Color maleTint = Color(0xFFEEF2FF);
  static const Color femaleAccent = Color(0xFFFB7185);
  static const Color femaleAccentDark = Color(0xFFFDA4AF);
  static const Color femaleTint = Color(0xFFFFF1F2);
  // Alias compatibles con el uso previo (se mantienen para textos/iconos).
  static const Color maleDark = Color(0xFF818CF8);
  static const Color femaleDark = Color(0xFFFB7185);

  static const LinearGradient headerGradient = LinearGradient(
    colors: [primary, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient vibrantGradient = LinearGradient(
    colors: [primary, primaryVibrant],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, accent],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const List<BoxShadow> strongShadow = [
    BoxShadow(color: Color(0x20000000), blurRadius: 20, offset: Offset(0, 10)),
  ];

  static const List<BoxShadow> mediumShadow = [
    BoxShadow(color: Color(0x10000000), blurRadius: 12, offset: Offset(0, 6)),
  ];

  static const List<BoxShadow> lightShadow = [
    BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
}

class AppIcons {
  /// Fallback Material si no se puede usar [PoultryIcon].
  static const IconData avesFallback = Icons.egg_alt_rounded;
}

class AppConstants {
  static const String baseUrl = 'https://granjarinconadadelsur.com/produccionaves/app/public';
  static const String apiToken = 'd9f7a6b3-4c8e-11ee-be56-0242ac120002';
  static const String appName = 'PROD_MORTALIDAD';
  static const String appDeveloper = 'JLSF Soft Soluciones EIRL.';
  static const String companyName = 'Granja Rinconada del Sur';
  static const String appTitle = 'MORTALIDAD';
  static const String appVersion = '1.0.4';

  static const String keyIsLoggedIn = 'is_logged_in';
  static const String keyUserCode = 'user_code';
  static const String keyUserName = 'user_name';
  static const String keyDeviceId = 'device_id';
  static const String keyDeviceAuthorized = 'device_authorized';
  static const String keyThemeMode = 'theme_mode';
  static const String keyMortalityVisibility = 'mortality_visibility';
  static const String keyUsuarioCodigoSanidad = 'usuario_codigo_sanidad';

  static const String loginEndpoint = '/login.php';
  static const String registerDeviceEndpoint = '/registrardispositivo.php';
  static const String downloadEndpoint = '/download.php';
  static const String listarMortalidadEndpoint = '/mortalidad/listar_mortalidad_movil.php';
  static const String listarAuditoriaEndpoint = '/mortalidad/listar_auditoria_pendiente_movil.php';
  static const String listarMisAuditoriasEndpoint = '/mortalidad/listar_mis_auditorias_movil.php';
  static const String guardarAuditoriaEndpoint = '/mortalidad/guardar_auditoria_movil.php';

  static const int maxPhotos = 5;
}

class AppStrings {
  static const String formTypeMortalidad = 'mortalidad';
  static const String formTypeAuditoria = 'auditoria';
  static const String loginTitle = 'Iniciar Sesión';
  static const String registerTitle = 'Registro de Dispositivo';
  static const String dashboardTitle = 'Dashboard';
  static const String reportesTitle = 'Mis Registros';
  static const String reporteLiquidacionTitle = 'Reporte Liquidación';
  static const String auditoriaTitle = 'Registro Auditoría';
  static const String menuDashboard = 'Mi Dashboard';
  static const String menuRegistro = 'Registro Mortalidad';
  static const String menuReportes = 'Mis Registros';
  static const String menuReporteLiquidacion = 'Reporte Liquidación';
  static const String menuAuditoria = 'Auditoría';
  static const String menuAcercaDe = 'Acerca de';
  static const String menuCerrarSesion = 'Cerrar sesión';
  static const String menuTemaSistema = 'Tema del sistema';
  static const String menuModoOscuro = 'Modo oscuro';
  static const String menuModoClaro = 'Modo claro';
  static const String descargar = 'Descargar';
  static const String subir = 'Subir';
  static const String guardarRegistro = 'Guardar registro';
  static const String guardadoExitoso = 'Guardado y enviado con éxito';
  static const String guardadoLocal = 'Guardado localmente. Envíelo desde el menú lateral en una zona con conexión';
  static const String auditoriaGuardadaExitoso = 'Guardado y enviado con éxito';
  static const String auditoriaGuardadaLocal = 'Guardado localmente. Envíelo desde el menú lateral en una zona con conexión';
  static const String cancelar = 'Cancelar';
  static const String si = 'Sí';
  static const String cerrarSesionTitulo = 'Cerrar sesión';
  static const String cerrarSesionMensaje = '¿Desea cerrar sesión?';
  static const String sinConexion = 'Sin conexión a internet.';
  static const String descargaExitosa = 'Información actualizada correctamente';
  static const String errorDescarga = 'Error al descargar';
  static const String noHayRegistrosPendientes = 'No hay registros pendientes';
  static const String total = 'Total';
  static const String pendientes = 'Pendientes';
  static const String subidos = 'Subidos';
  static const String errorServidor =
      'Error al procesar. Inténtelo más tarde.';
}
