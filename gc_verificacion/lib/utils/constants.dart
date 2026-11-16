import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFFF07D4A);
  static const Color primaryLight = Color(0xFFFFC9A8);
  static const Color primaryDark = Color(0xFFE36B45);
  static const Color primaryVibrant = Color(0xFFFF9A6B);

  static const Color aprobado = Color(0xFF22C55E);
  static const Color aprobadoDark = Color(0xFF15803D);
  static const Color rechazado = Color(0xFFEF4444);
  static const Color rechazadoDark = Color(0xFFB91C1C);
  static const Color analizando = Color(0xFFF5B82E);
  static const Color buscando = Color(0xFF38BDF8);

  static const Color background = Color(0xFF0B0F16);
  static const Color surface = Color(0xFF131A26);
  static const Color cardBackground = Color(0xFF151D2B);
  static const Color border = Color(0xFF26314A);

  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  static const Color backgroundLight = Color(0xFFF3F5F9);
  static const Color surfaceLight = Color(0xFFE7ECF3);
  static const Color cardLight = Colors.white;
  static const Color borderLight = Color(0xFFD7DEE8);

  static const Color textPrimaryLight = Color(0xFF131A26);
  static const Color textSecondaryLight = Color(0xFF526178);
  static const Color textMutedLight = Color(0xFF8494AB);
  static const Color textOnPrimary = Colors.white;

  static const Color error = Color(0xFFEF4444);
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF5B82E);

  static const double radiusSm = 10;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;

  static const LinearGradient headerGradient = LinearGradient(
    colors: [primaryDark, primary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const List<BoxShadow> strongShadow = [
    BoxShadow(color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 8)),
  ];

  static const List<BoxShadow> mediumShadow = [
    BoxShadow(color: Color(0x30000000), blurRadius: 12, offset: Offset(0, 5)),
  ];

  static const List<BoxShadow> lightShadow = [
    BoxShadow(color: Color(0x20000000), blurRadius: 8, offset: Offset(0, 2)),
  ];

  static List<BoxShadow> get primaryShadow => [
    BoxShadow(
      color: primary.withValues(alpha: 0.28),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}

class AppConstants {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://granjarinconadadelsur.com/sanidad/flutter',
  );
  static const String verificacionPath = '/verificacion';

  static const String apiToken = 'd9f7a6b3-4c8e-11ee-be56-0242ac120002';
  static const String appName = 'PROD_VERIFICACION';
  static const String appTitle = 'Verificación de ingreso';
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
  static const String keyCatalogos = 'veri_catalogos';
  static const String keyAppInfo = 'veri_g_app_info';

  static const String keyNominaVersion = 'veri_nomina_version';
  static const String keyNominaTotal = 'veri_nomina_total';
  static const String keyLastDownloadDate = 'veri_last_download_date';
  static const String keyLastSyncDate = 'veri_last_sync_date';

  static const String keyEventos = 'veri_eventos';
  static const String keyPuedeEnrolar = 'veri_puede_enrolar';
  static const String keyPlantillasPendientes = 'veri_plantillas_pendientes';

  static const String keyUmbral = 'veri_umbral';
  static const String keyMargen = 'veri_margen';
  static const String keySonido = 'veri_sonido';
  static const String keyVoz = 'veri_voz';
  static const String keyVibracion = 'veri_vibracion';

  static const String loginEndpoint = '/login.php';
  static const String registerDeviceEndpoint = '/registrardispositivo.php';
  static const String downloadEndpoint = '/download.php';
  static const String nominaEndpoint = '/get_nomina_movil.php';
  static const String guardarPlantillaEndpoint = '/guardar_plantilla_movil.php';
  static const String guardarEventosEndpoint = '/guardar_eventos_movil.php';

  static const double umbralDefecto = 0.45;
  static const double margenDefecto = 0.10;
  static const int votosRequeridos = 3;
  static const int ventanaVotos = 5;
  static const double giroMaxGrados = 15;
  static const int resultadoSegundos = 4;
  static const int syncIntervalMinutes = 15;
  static const String faceModel = 'arcface-w600k_mbf';
  static const double boxMinFrac = 0.22;
  static const double centroXTol = 0.18;
  static const double centroYTol = 0.2;
  static const double brilloMin = 60;
  static const double brilloMax = 215;
  static const double nitidezMin = 60;
  static const double vozVelocidad = 0.5;
  static const int idleDimSeconds = 45;
  static const double dimLevel = 0.15;
  static const int rechazosFinal11 = 8;

  static const int appVersionGraceDays = 4;
  static const int staleNominaDays = 3;
}

class AppStrings {
  static const String loginTitle = 'Iniciar sesión';
  static const String registerTitle = 'Registrar dispositivo';
  static const String menuVerificacion = 'Verificación';
  static const String menuEventos = 'Eventos del día';
  static const String menuPersonal = 'Personal';
  static const String menuEnrolar = 'Enrolar';
  static const String menuDiagnostico = 'Diagnóstico';
  static const String menuCerrarSesion = 'Cerrar sesión';
  static const String descargaExitosa = 'Información descargada con éxito';
  static const String actualiceNomina = 'Actualice la nómina';
  static const String subidaExitosa = 'Registros subidos correctamente';
  static const String sinConexion = 'No hay conexión a internet.';
  static const String sinNomina =
      'Sin nómina. Descargue desde el menú (Descargar).';
  static const String pendientes = 'Pendientes';
  static const String subidos = 'Subidos';
}
