import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF4CAF50);
  static const Color primaryLight = Color(0xFF81C784);
  static const Color primaryDark = Color(0xFF388E3C);
  static const Color primaryVibrant = Color(0xFF66BB6A);

  static const Color accent = Color(0xFF66BB6A);
  static const Color accentLight = Color(0xFFA5D6A7);
  static const Color accentDark = Color(0xFF43A047);
  static const Color accentBright = Color(0xFF8BC34A);

  static const Color background = Color(0xFFF1F8E9);
  static const Color cardBackground = Colors.white;
  static const Color textPrimary = Color(0xFF2E7D32);
  static const Color textSelectedValue = Color(0xFF66BB6A);
  static const Color textSecondary = Color(0xFF66BB6A);
  static const Color textMuted = Color(0xFF81C784);
  static const Color dialogBackground = Colors.white;
  static const Color textOnPrimary = Colors.white;

  static const Color surface = Color(0xFFF5F5F5);

  static const Color error = Color(0xFFE57373);
  static const Color errorLight = Color(0xFFEF9A9A);
  static const Color errorDark = Color(0xFFD32F2F);
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color info = Color(0xFF2196F3);

  static const Color iconAccent = Color(0xFF4FC3F7);

  static const LinearGradient headerGradient = LinearGradient(
    colors: [primary, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, accent],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient iconGradient = LinearGradient(
    colors: [primary, primaryVibrant, accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient softGradient = LinearGradient(
    colors: [primaryLight, accentLight],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient vibrantGradient = LinearGradient(
    colors: [primary, primaryVibrant],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const List<BoxShadow> strongShadow = [
    BoxShadow(
      color: Color(0x20000000),
      blurRadius: 20,
      offset: Offset(0, 10),
    ),
  ];

  static const List<BoxShadow> mediumShadow = [
    BoxShadow(
      color: Color(0x10000000),
      blurRadius: 12,
      offset: Offset(0, 6),
    ),
  ];

  static const List<BoxShadow> lightShadow = [
    BoxShadow(
      color: Color(0x08000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get primaryShadow => [
        BoxShadow(
          color: primary.withOpacity(0.3),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];
}

class AppConstants {
  static const String baseUrl = 'http://10.28.139.5/sanidad/flutter';
  static const String seguimientoPath = '/seguimiento_crianza';
  static const String apiToken = 'd9f7a6b3-4c8e-11ee-be56-0242ac120002';
  static const String appName = 'PROD_SEGUIMIENTO_CRIANZA';
  static const String appTitle = 'Seguimiento de crianza';
  static const String appDeveloper = 'JLSF Soft Soluciones EIRL.';
  static const String companyName = 'Granja Rinconada del Sur';
  static const String appVersion = '1.0.0';
  static const String offlineSalt = 'M0rt4l1d4d_S4lt_2026';

  static const String keyIsLoggedIn = 'is_logged_in';
  static const String keyUserCode = 'user_code';
  static const String keyUserName = 'user_name';
  static const String keyDeviceId = 'device_id';
  static const String keyDeviceAuthorized = 'device_authorized';
  static const String keyOfflineHash = 'offline_hash';
  static const String keyLoginEnom = 'login_enom';

  static const String loginEndpoint = '/login.php';
  static const String registerDeviceEndpoint = '/registrardispositivo.php';
  static const String downloadEndpoint = '/download.php';

  static const String keyCencosGalpones = 'sc_cencos_galpones';
  static const String keyGalponesPorCenco = 'sc_galpones_por_cenco';
  static const String keyGalponesPorGranja = 'sc_galpones_por_granja';
  static const String keyCencosLista = 'sc_cencos_lista';
  static const String keyProyeccion = 'sc_proyeccion';
}

class AppStrings {
  static const String recordsTable = 'seguimiento_crianza_records';
  static const String loginTitle = 'Iniciar Sesión';
  static const String registerTitle = 'Registro de Dispositivo';
  static const String dashboardTitle = 'Dashboard';
  static const String menuDashboard = 'Mi Dashboard';
  static const String menuRegistro = 'Registro de Seguimiento';
  static const String menuReportes = 'Reportes';
  static const String menuCerrarSesion = 'Cerrar sesión';
  static const String resumenSemanal = 'Resumen Semanal';
  static const String reportesTitle = 'Reportes';
  static const String desde = 'Desde';
  static const String hasta = 'Hasta';
  static const String guardarRegistro = 'Guardar Registro';
  static const String descargaExitosa = 'Información descargada con éxito';
  static const String subidaExitosa = 'Registros subidos correctamente';
  static const String sinConexion = 'No hay conexión a internet.';
  static const String pendientes = 'Pendientes';
  static const String subidos = 'Subidos';
}
