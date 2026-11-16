import 'package:flutter/material.dart';

class AppColors {
  // Verde principal (Sanidad) - Paleta mejorada
  static const Color primary = Color(0xFF4CAF50);
  static const Color primaryLight = Color(0xFF81C784);
  static const Color primaryDark = Color(0xFF388E3C);
  static const Color primaryVibrant = Color(0xFF66BB6A); // Verde más vibrante

  // Secundarios - Mejorados
  static const Color accent = Color(0xFF66BB6A); // Verde claro para botones
  static const Color accentLight = Color(0xFFA5D6A7);
  static const Color accentDark = Color(0xFF43A047);
  static const Color accentBright = Color(0xFF8BC34A); // Verde más brillante

  // Fondo y texto - Mejorados
  static const Color background = Color(0xFFF1F8E9); // Verde muy claro
  static const Color cardBackground = Colors.white;
  static const Color textPrimary = Color(0xFF2E7D32); // Verde oscuro para texto
  static const Color textSecondary = Color(0xFF66BB6A);
  static const Color textMuted = Color(0xFF81C784);
  static const Color textOnPrimary = Colors.white; // Texto sobre fondo verde

  static const Color surface = Color(0xFFF5F5F5);

  // Errores - Mejorado
  static const Color error = Color(0xFFE57373);
  static const Color errorLight = Color(0xFFEF9A9A);
  static const Color errorDark = Color(0xFFD32F2F);

  // Éxito y advertencias
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color info = Color(0xFF2196F3);

  // Iconos y títulos: celeste suave en armonía con la app
  static const Color iconAccent = Color(0xFF4FC3F7); // Light Blue 300

  // Gradientes - Mejorados
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

  // Nuevo: Gradiente para iconos y elementos destacados
  static const LinearGradient iconGradient = LinearGradient(
    colors: [primary, primaryVibrant, accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Nuevo: Gradiente suave para fondos
  static const LinearGradient softGradient = LinearGradient(
    colors: [primaryLight, accentLight],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Nuevo: Gradiente vibrante para botones importantes
  static const LinearGradient vibrantGradient = LinearGradient(
    colors: [primary, primaryVibrant],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Sombras - Mejoradas
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

  // Nuevo: Sombra suave para elementos elevados
  static const List<BoxShadow> lightShadow = [
    BoxShadow(
      color: Color(0x08000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  // Nuevo: Sombra con color verde para elementos destacados
  static List<BoxShadow> get primaryShadow => [
    BoxShadow(
      color: primary.withOpacity(0.3),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}

class AppConstants {
  // API Configuration

  static const String baseUrl = // 'https://granjarinconadadelsur.com/sanidad/flutter';

  'http://10.94.219.131/sanidad/flutter';
  static const String apiToken = 'd9f7a6b3-4c8e-11ee-be56-0242ac120002';

  static const String appName = 'PROD_NECROPCIAS';
  static const String appDeveloper = 'JLSF Soft Soluciones EIRL.';
  static const String companyName = 'Granja Rinconada del Sur';
    static const String appTitle = 'NECROPCIAS';

  static const String appVersion = '1.0.5';
    // Storage Keys
  static const String keyIsLoggedIn = 'is_logged_in';
  static const String keyUserCode = 'user_code';
  static const String keyUserName = 'user_name';
  static const String keyDeviceId = 'device_id';
  static const String keyDeviceAuthorized = 'device_authorized';

  // Endpoints
  static const String loginEndpoint = '/login.php';
  static const String registerDeviceEndpoint = '/registrardispositivo.php';
  static const String downloadEndpoint = '/download.php';
  static const String uploadEndpoint = '/upload.php';
}

class AppStrings {
  // Login Screen
  static const String loginTitle = 'Iniciar Sesión';
  static const String registerTitle = 'Registro de Dispositivo';
  static const String labelUsuario = 'Usuario';
  static const String labelPassword = 'Contraseña';
  static const String labelDispositivo = 'ID de Dispositivo';
  static const String menuModoOscuro = 'Modo Oscuro';
  static const String menuModoClaro = 'Modo Claro';

  // Login alternativo (mantenido para compatibilidad)
  static const String userLabel = 'Usuario';
  static const String passwordLabel = 'Contraseña';
  static const String loginButton = 'LOGIN';
  static const String registerDeviceButton = 'Registra tu dispositivo';

  // Dashboard
  static const String dashboardTitle = 'Dashboard';
  static const String todayRecords = 'Total de registros del día';

  // Nuevo: Títulos de secciones del dashboard
  static const String resumenSemanal = 'Resumen Semanal';
  static const String registrosPorFecha = 'Registros por Fecha';
  static const String registrosPorTipo = 'Por Tipo';
  static const String registrosPorEstado = 'Estado';

  // Menu
  static const String menuDashboard = 'Mi Dashboard';
  static const String menuFormularios = 'Registro Mercados';
  static const String menuReportes = 'Proyección Mensual';
  static const String menuAcercaDe = 'Acerca de';
  static const String menuCerrarSesion = 'Cerrar sesión';
  static const String statusOffline = 'Offline';
  static const String statusOnline = 'Online';

  // Nuevo: Navegación y opciones
  static const String navegacion = 'Navegación';
  static const String opciones = 'Opciones';

  // Forms
  static const String formType1 = 'necropcias';

  // Nuevo: Formulario de mercados
  static const String fechaRegistro = 'Fecha de Registro';
  static const String ubicacion = 'Ubicación';
  static const String provincia = 'Provincia';
  static const String mercado = 'Mercado';
  static const String seleccionar = 'Seleccionar...';
  static const String puestosMercado = 'Puestos de Mercado';
  static const String tiendasAledanas = 'Tiendas Aledañas';
  static const String conteo = 'Conteo';
  static const String guardarRegistro = 'Guardar Registro';

  // Nuevo: Proyección mensual
  static const String proyeccionMensual = 'Proyección Mensual';
  static const String mesSeleccionado = 'Mes Seleccionado';
  static const String proyeccionTotal = 'Proyección Total';
  static const String totalMercados = 'mercados';
  static const String totalUnidades = 'unidades';
  static const String supermercados = 'Supermercados';
  static const String puestosMercadoLabel = 'Puestos de Mercado';
  static const String tiendasAledanasLabel = 'Tiendas y Puestos Aledaños';
  static const String tamanioGrande = 'Grande';
  static const String tamanioMediano = 'Mediano';
  static const String tamanioChico = 'Chico';
  static const String subtotal = 'Subtotal';

  // Reportes
  static const String reportesTitle = 'Reportes';
  static const String reportesComerciales = 'Reportes Comerciales';
  static const String desde = 'Desde';
  static const String hasta = 'Hasta';
  static const String buscar = 'Buscar';

  // Dialogs
  static const String cerrarSesionTitulo = 'Cerrar sesión';
  static const String cerrarSesionMensaje = '¿Está seguro que desea cerrar sesión?';
  static const String cancelar = 'Cancelar';
  static const String si = 'Sí';
  static const String aceptar = 'Aceptar';
  static const String cerrar = 'Cerrar';

  // Nuevo: Sincronización
  static const String descargar = 'Descargar';
  static const String subir = 'Subir';
  static const String sincronizando = 'Sincronizando...';
  static const String ultimaDescarga = 'Última descarga';
  static const String ultimaSincronizacion = 'Última sincronización';
  static const String sinConexion = 'No hay conexión a internet. Inténtelo más tarde.';
  static const String descargaExitosa = 'Información descargada con éxito';
  static const String errorDescarga = 'Error al descargar información';
  static const String subidaExitosa = 'Información subida correctamente';
  static const String errorSubida = 'Error al subir información';
  static const String noHayRegistrosPendientes = 'No hay registros pendientes por subir';

  // Errors
  static const String errorGeneral = 'Ha ocurrido un error';
  static const String errorConexion = 'Error de conexión';
  static const String errorCredenciales = 'Usuario o contraseña incorrectos';
  static const String errorDispositivoNoAutorizado = 'Dispositivo no autorizado';

  // Nuevo: Estados y mensajes
  static const String total = 'Total';
  static const String pendientes = 'Pendientes';
  static const String subidos = 'Subidos';
  static const String sincronizados = 'Sincronizados';
  static const String sinDatos = 'Sin datos para mostrar';
  static const String cargando = 'Cargando...';
  static const String guardando = 'Guardando...';
  static const String guardadoExitoso = 'Registro guardado exitosamente';
  static const String errorGuardado = 'Error al guardar el registro';

  // Nuevo: Validaciones
  static const String campoRequerido = 'Este campo es requerido';
  static const String seleccioneOpcion = 'Seleccione una opción';
  static const String validacionFallida = 'Por favor complete todos los campos requeridos';
}
