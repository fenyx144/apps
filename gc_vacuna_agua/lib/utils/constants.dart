import 'package:flutter/material.dart';

class AppColors {
  // ── Marca azul/celeste: header, botones de acción y checks ──
  /// Celeste / azul claro (equivale al `azulino` de la app antigua).
  static const Color primary = Color(0xFF2398C5);
  static const Color primaryLight = Color(0xFF5FB8DE);
  static const Color primaryDark = Color(0xFF1A7FA8);
  static const Color primaryVibrant = Color(0xFF35A7D4);

  static const Color accent = Color(0xFF35A7D4);
  static const Color accentLight = Color(0xFF8FD4EC);
  static const Color accentDark = Color(0xFF1A7FA8);
  static const Color accentBright = Color(0xFF56BFE4);

  // ── Colores de tabla (tomados de la app Android antigua) ──
  static const Color tableHeader = Color(0xFF2398C5); // azulino
  static const Color tableHeaderText = Colors.white; // blanco
  static const Color tableRowAlt = Color(0xFFAEE4E8); // azulclaro
  static const Color tableBorder = Color(0xFF7CB3E7); // celeste
  static const Color tableAccent = Color(0xFF164072); // azulOscuro2
  static const Color horaText = Color(0xFF008000); // verde

  // ── Superficies (paleta pizarra, igual que el resto de apps) ──
  static const Color background = Color(0xFFF8FAFC);
  static const Color cardBackground = Colors.white;
  static const Color darkBackground = Color(0xFF0F172A);
  static const Color darkSurface = Color(0xFF1E293B);
  static const Color darkCard = Color(0xFF1E293B);

  // ── Bordes ──
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color darkBorder = Color(0xFF334155);

  // ── Textos ──
  static const Color textPrimary = Color(0xFF1E293B);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textSelectedValue = Color(0xFF1E293B);
  static const Color darkTextPrimary = Color(0xFFF1F5F9);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextMuted = Color(0xFF64748B);
  static const Color dialogBackground = Colors.white;
  static const Color textOnPrimary = Colors.white;

  static const Color surface = Color(0xFFF5F5F5);

  static const Color error = Color(0xFFE57373);
  static const Color errorLight = Color(0xFFEF9A9A);
  static const Color errorDark = Color(0xFFD32F2F);
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color info = Color(0xFF2196F3);

  /// Acento de íconos: azul oscuro para buen contraste sobre blanco.
  static const Color iconAccent = Color(0xFF1A7FA8);

  /// Radios de diseño unificados
  static const double radiusSm = 10;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;

  static const LinearGradient headerGradient = LinearGradient(
    colors: [primary, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient iconGradient = LinearGradient(
    colors: [primaryDark, primary, primaryLight],
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
      color: Color(0x18000000),
      blurRadius: 18,
      offset: Offset(0, 8),
    ),
  ];

  static const List<BoxShadow> mediumShadow = [
    BoxShadow(
      color: Color(0x12000000),
      blurRadius: 12,
      offset: Offset(0, 5),
    ),
  ];

  static const List<BoxShadow> lightShadow = [
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
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
  // Se trabaja contra el XAMPP de la máquina de desarrollo, que el celular
  // alcanza por la red compartida (misma IP que usa Bioseguridad). Producción
  // queda comentada: el módulo de Vacuna al Agua todavía no está desplegado ahí
  // y sus endpoints devuelven 404 (la app recibía HTML en vez de JSON).
  static const String baseUrl = 'https://granjarinconadadelsur.com/sanidad/flutter';

  /// Carpeta PHP de esta app (módulo móvil de vacunación al agua).
  static const String seguimientoPath = '/vacunaagua';

  /// Carpeta PHP de la que se reutilizan catálogos de granjas/campañas.
  static const String catalogosPath = '/seguimiento_crianza';

  /// Búsqueda de laboratorio en maestro `ccte`. Endpoint propio de vacunación:
  /// no usa la carpeta ni los scripts de bioseguridad.
  static const String buscarProveedorCcteEndpoint =
      '/buscar_proveedor_ccte_vacunaagua_movil.php';
  static const String proveedoresVacunaEndpoint =
      '/get_proveedores_vacunaagua_movil.php';

  static const String apiToken = 'd9f7a6b3-4c8e-11ee-be56-0242ac120002';
  static const String appName = 'PROD_VACUNAAGUA';
  static const String appTitle = 'Vacuna al Agua';
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
  static const String catalogosVacunaEndpoint = '/get_catalogos_vacunaagua_movil.php';
  static const String guardarVacunaEndpoint = '/guardar_vacunaagua_movil.php';
  static const String actualizarVacunaEndpoint = '/actualizar_vacunaagua_movil.php';
  static const String consultarDniEndpoint = '/consultar_dni_bioseguridad_movil.php';
  static const String consultarPlanificacionEndpoint =
      '/consultar_planificacion_bioseguridad_movil.php';
  static const String descargarPlanificacionEndpoint =
      '/descargar_planificacion_bioseguridad_movil.php';

  static const String keyCencosGalpones = 'bio_cencos_galpones';
  static const String keyGalponesPorCenco = 'bio_galpones_por_cenco';
  static const String keyGalponesPorGranja = 'bio_galpones_por_granja';
  static const String keyCencosLista = 'bio_cencos_lista';
  static const String keyProyeccion = 'bio_proyeccion';
  static const String keyAppInfo = 'bio_g_app_info';
  static const String keyCatalogosVacuna = 'vac_catalogos';
  static const String keyProveedoresVacunaCatalog = 'vac_proveedores_catalog';

  /// Planificación de visitas descargada para trabajar sin señal (JSON) y la
  /// fecha/hora de su última descarga.
  static const String keyPlanVisitas = 'bio_plan_visitas';
  static const String keyPlanVisitasFecha = 'bio_plan_visitas_fecha';

  static const String keyLastDownloadDate = 'bio_last_download_date';
  static const String keyLastSyncDate = 'bio_last_sync_date';

  /// Granja de trabajo elegida en «Mi granja». Se premarca en los formularios.
  static const String keyGranjaTrabajo = 'bio_granja_trabajo';

  /// Retención del catálogo ccos acumulado en el dispositivo (días hacia atrás).
  static const int catalogHistoricoDias = 365;

  /// Plazo para actualizar app cuando g_app.tversion es mayor (días desde tdate).
  static const int appVersionGraceDays = 4;

  /// Días sin descargar catálogos antes de mostrar el aviso en el menú lateral.
  static const int staleCatalogDays = 3;
}

class AppStrings {
  static const String recordsTable = 'vacunaagua_records';
  static const String loginTitle = 'Iniciar Sesión';
  static const String registerTitle = 'Registro de Dispositivo';
  static const String dashboardTitle = 'Dashboard';
  static const String menuDashboard = 'Mi Dashboard';
  static const String menuDecloracion = 'Decloración';
  static const String menuVacunacion = 'Vacunación';
  static const String menuReportes = 'Reportes';
  static const String menuCerrarSesion = 'Cerrar sesión';
  static const String menuMiGranja = 'Mi granja';
  static const String miGranjaTitle = 'Mi granja';
  static const String resumenSemanal = 'Resumen Semanal';
  static const String reportesTitle = 'Reportes';
  static const String desde = 'Desde';
  static const String hasta = 'Hasta';
  static const String guardarRegistro = 'Guardar Registro';
  static const String descargaExitosa = 'Información descargada con éxito';
  static const String actualiceCatalogos = 'Actualice sus catálogos';
  static const String subidaExitosa = 'Registros subidos correctamente';
  static const String sinConexion = 'No hay conexión a internet.';
  static const String sinCatalogosLocales =
      'No hay catálogos guardados. Descargue desde el menú (Descargar).';
  static const String pendientes = 'Pendientes';
  static const String subidos = 'Subidos';
}

/* ── Navegación de los registros ────────────────────────────────────────────
 *
 * La app tiene dos registros: Decloración y Vacunación. El drawer los agrupa
 * bajo un único grupo para mantener el mismo patrón plegable de bioseguridad.
 */

/// Identificadores de sección (una pantalla de registro cada una).
class BioSecciones {
  static const String decloracion = 'decloracion';
  static const String vacunacion = 'vacunacion';
}

/// Sección navegable del AppBar.
class BioNavSeccion {
  const BioNavSeccion({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final IconData icon;
}

/// Grupo de registros con sus secciones.
class BioNavTipo {
  const BioNavTipo({
    required this.id,
    required this.label,
    required this.icon,
    required this.secciones,
  });

  final String id;

  /// Etiqueta corta del grupo.
  final String label;

  final IconData icon;
  final List<BioNavSeccion> secciones;

  /// Sección con la que abre el grupo al entrar desde el drawer.
  BioNavSeccion get primera => secciones.first;
}

/// Grupos del drawer. Hoy hay uno solo con los dos registros.
const List<BioNavTipo> bioNavTipos = [
  BioNavTipo(
    id: 'registros',
    label: 'Registros',
    icon: Icons.assignment_outlined,
    secciones: [
      BioNavSeccion(
        id: BioSecciones.decloracion,
        label: AppStrings.menuDecloracion,
        icon: Icons.water_drop_outlined,
      ),
      BioNavSeccion(
        id: BioSecciones.vacunacion,
        label: AppStrings.menuVacunacion,
        icon: Icons.vaccines_outlined,
      ),
    ],
  ),
];
