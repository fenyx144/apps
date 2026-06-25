import 'package:flutter/material.dart';

class AppColors {
  // Colores primarios (mantenidos de tu versión original)
  static const Color primary = Color(0xFF1A2B56); // Azul profundo
  static const Color accent = Color(
    0xFF4A90E2,
  ); // Azul vibrante → para acentos y bordes activos
  static const Color surface = Colors.white; // Fondo de tarjetas
  static const Color background = Color(0xFFF5F9FD); // Fondo suave
  static const Color primaryLight = Color(0xFF2D3E50); // Azul marino medio
  static const Color primaryDark = Color(0xFF0F1419); // Casi negro azulado

  // Colores de acento
  static const Color accentLight = Color(0xFF6BA3E8); // Azul claro
  static const Color accentDark = Color(0xFF2E6FB8); // Azul intenso

  static const Color secondary = Color(0xFF5B7C99); // Azul grisáceo elegante
  static const Color tertiary = Color(0xFF7B9FC9); // Azul suave

  static const Color cardBackground = Color(0xFFF0F4F8); // Azul muy claro

  // Colores de texto
  static const Color textPrimary = Color(0xFF1F2937); // Gris muy oscuro
  static const Color textSecondary = Color(0xFF6B7280); // Gris medio
  static const Color textLight = Colors.white;
  static const Color textMuted = Color(0xFF9CA3AF); // Gris claro

  // Colores de estado
  static const Color success = Color(0xFF10B981); // Verde esmeralda
  static const Color warning = Color(0xFFF59E0B); // Ámbar
  static const Color error = Color(0xFFEF4444); // Rojo coral
  static const Color info = Color(0xFF3B82F6); // Azul info

  // Modo oscuro
  static const Color darkBackground = Color(0xFF121212); // Fondo muy oscuro
  static const Color darkSurface = Color(0xFF1F1F1F); // Superficie de tarjetas
  static const Color darkTextPrimary = Colors.white;
  static const Color darkTextSecondary = Color(0xFFB0B0B0); // Gris claro
  static const Color darkCardBackground = Color(
    0xFF282828,
  ); // Fondo de tarjeta oscuro

  // Función para obtener el color dinámicamente
  static Color getBackgroundColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkBackground
        : background;
  }

  // Gradientes principales
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1E3A5F), // Azul profundo
      Color(0xFF2D4A6F), // Azul medio
      Color(0xFF4A90E2), // Azul vibrante
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF0F1419), // Casi negro
      Color(0xFF1A2332), // Azul marino profundo
      Color(0xFF2D3E50), // Azul marino medio
    ],
    stops: [0.0, 0.4, 1.0],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFFFFF), Color(0xFFF8F9FA)],
  );

  // Nuevo: Gradiente de acento para botones y elementos destacados
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4A90E2), Color(0xFF6BA3E8)],
  );

  // Sombras elegantes
  static List<BoxShadow> get softShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.08),
      blurRadius: 20,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get mediumShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.12),
      blurRadius: 30,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> get strongShadow => [
    BoxShadow(
      color: primary.withOpacity(0.25),
      blurRadius: 40,
      offset: const Offset(0, 12),
    ),
  ];

  // Nuevo: Sombras adicionales para diferentes casos de uso
  static List<BoxShadow> get lightShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.05),
      blurRadius: 10,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> accentShadow(Color color) => [
    BoxShadow(
      color: color.withOpacity(0.3),
      blurRadius: 15,
      offset: const Offset(0, 6),
    ),
  ];
}

class AppConstants {
  // API Configuration
  static const String baseUrl = //'https://granjarinconadadelsur.com/sanidad';
      'http://10.94.219.131/sanidad';
  static const String baseUrlSanidad = // 'https://granjarinconadadelsur.com/sanidad/flutter';
      'http://10.94.219.131/sanidad/flutter';

  static const String dashboardBasePath =
      '/modules/laboratorio/muestras/dashboard';
  
  static const String apiToken = 'd9f7a6b3-4c8e-11ee-be56-0242ac120002';

  // App Info
  static const String appTitle = 'GC Sanidad';
  static const String appName = 'PROD_SANIDAD';
  static const String appVersion = '1.0.0';
  static const String appDeveloper = 'JLSF Soft Soluciones EIRL.';
  static const String companyName = 'Granja Rinconada del Sur';

  // Storage Keys
  static const String keyIsLoggedIn = 'is_logged_in';
  static const String keyUserCode = 'user_code';
  static const String keyUserName = 'user_name';
  static const String keyDeviceId = 'device_id';
  static const String keyDeviceAuthorized = 'device_authorized';

  // Nuevo: Keys adicionales para sincronización
  static const String keyLastDownloadDate = 'last_download_date';
  static const String keyLastSyncDate = 'last_sync_date';

  // Endpoints
  static const String loginEndpoint = '/login.php';
  static const String registerDeviceEndpoint = '/registrardispositivo.php';
  static const String downloadEndpoint = '/download.php';
  static const String uploadEndpoint = '/upload.php';
  static const String uploadEndpointIngresoLima = '/uploadingresolima.php';
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
  static const String formType1 = 'envios_muestras';
  static const String formTypeTracking = 'orden_tracking';
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
  static const String cerrarSesionMensaje =
      '¿Está seguro que desea cerrar sesión?';
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
  static const String sinConexion = 'No hay conexión a internet';
  static const String descargaExitosa = 'Información descargada con éxito';
  static const String errorDescarga = 'Error al descargar información';
  static const String subidaExitosa = 'Información subida correctamente';
  static const String errorSubida = 'Error al subir información';
  static const String noHayRegistrosPendientes =
      'No hay registros pendientes por subir';

  // Errors
  static const String errorGeneral = 'Ha ocurrido un error';
  static const String errorConexion = 'Error de conexión';
  static const String errorCredenciales = 'Usuario o contraseña incorrectos';
  static const String errorDispositivoNoAutorizado =
      'Dispositivo no autorizado';

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
  static const String validacionFallida =
      'Por favor complete todos los campos requeridos';
}

class AppSizes {
  // Padding
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  static const double paddingXLarge = 32.0;

  // Nuevo: Padding adicional
  static const double paddingXSmall = 4.0;
  static const double paddingXXLarge = 40.0;

  // Border Radius
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusXLarge = 20.0;

  // Nuevo: Radius adicionales
  static const double radiusXSmall = 4.0;
  static const double radiusRound = 24.0;
  static const double radiusCircular = 50.0;

  // Icon Sizes
  static const double iconSmall = 20.0;
  static const double iconMedium = 24.0;
  static const double iconLarge = 32.0;
  static const double iconXLarge = 48.0;

  // Nuevo: Icon sizes adicionales
  static const double iconXSmall = 16.0;
  static const double iconXXLarge = 64.0;

  // Nuevo: Font Sizes
  static const double fontXSmall = 10.0;
  static const double fontSmall = 12.0;
  static const double fontMedium = 14.0;
  static const double fontLarge = 16.0;
  static const double fontXLarge = 18.0;
  static const double fontTitle = 20.0;
  static const double fontHeader = 24.0;
  static const double fontDisplay = 32.0;

  // Nuevo: Espaciado para listas y grids
  static const double spacingSmall = 8.0;
  static const double spacingMedium = 16.0;
  static const double spacingLarge = 24.0;

  // Nuevo: Elevaciones
  static const double elevationLow = 2.0;
  static const double elevationMedium = 4.0;
  static const double elevationHigh = 8.0;
  static const double elevationXHigh = 12.0;
}

// Nuevo: Clase para configuraciones de animación
class AppAnimations {
  // Duraciones
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration medium = Duration(milliseconds: 400);
  static const Duration slow = Duration(milliseconds: 600);
  static const Duration verySlow = Duration(milliseconds: 800);
  static const Duration extraSlow = Duration(milliseconds: 1200);
  static const Duration chart = Duration(milliseconds: 1500);

  // Curvas de animación
  static const Curve defaultCurve = Curves.easeInOut;
  static const Curve entrance = Curves.easeOut;
  static const Curve exit = Curves.easeIn;
  static const Curve bounce = Curves.bounceOut;
  static const Curve elastic = Curves.elasticOut;
  static const Curve emphasized = Curves.easeOutCubic;
  static const Curve decelerate = Curves.decelerate;
}

// Nuevo: Tema de la aplicación
class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.surface,
        background: AppColors.background,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.background,

      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: AppSizes.fontTitle,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
        ),
        color: AppColors.surface,
        shadowColor: Colors.black.withOpacity(0.1),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.paddingLarge,
            vertical: AppSizes.paddingMedium,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          ),
          textStyle: const TextStyle(
            fontSize: AppSizes.fontMedium,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          borderSide: BorderSide(color: AppColors.textMuted.withOpacity(0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          borderSide: BorderSide(color: AppColors.textMuted.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          borderSide: const BorderSide(color: AppColors.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSizes.paddingMedium,
          vertical: AppSizes.paddingMedium,
        ),
      ),

      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: AppSizes.fontDisplay,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
          letterSpacing: -0.5,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
          letterSpacing: -0.3,
        ),
        displaySmall: TextStyle(
          fontSize: AppSizes.fontHeader,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
        headlineMedium: TextStyle(
          fontSize: AppSizes.fontTitle,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: AppSizes.fontXLarge,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: AppSizes.fontLarge,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: AppSizes.fontLarge,
          color: AppColors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: AppSizes.fontMedium,
          color: AppColors.textPrimary,
        ),
        bodySmall: TextStyle(
          fontSize: AppSizes.fontSmall,
          color: AppColors.textSecondary,
        ),
        labelLarge: TextStyle(
          fontSize: AppSizes.fontMedium,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),

      dividerTheme: DividerThemeData(
        color: AppColors.textMuted.withOpacity(0.2),
        thickness: 1,
        space: AppSizes.spacingMedium,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
        primary: AppColors.accent,
        secondary: AppColors.accentLight,
        surface: AppColors.darkSurface,
        background: AppColors.darkBackground,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.darkBackground,

      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: AppSizes.fontTitle,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
        ),
        color: AppColors.darkSurface,
      ),

      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: AppSizes.fontDisplay,
          fontWeight: FontWeight.bold,
          color: AppColors.darkTextPrimary,
          letterSpacing: -0.5,
        ),
        bodyLarge: TextStyle(
          fontSize: AppSizes.fontLarge,
          color: AppColors.darkTextPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: AppSizes.fontMedium,
          color: AppColors.darkTextPrimary,
        ),
        bodySmall: TextStyle(
          fontSize: AppSizes.fontSmall,
          color: AppColors.darkTextSecondary,
        ),
      ),
    );
  }
}

// Nuevo: Extensiones útiles
extension ColorExtension on Color {
  /// Oscurece el color en un porcentaje (0.0 - 1.0)
  Color darken([double amount = 0.1]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(this);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }

  /// Aclara el color en un porcentaje (0.0 - 1.0)
  Color lighten([double amount = 0.1]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(this);
    final hslLight = hsl.withLightness(
      (hsl.lightness + amount).clamp(0.0, 1.0),
    );
    return hslLight.toColor();
  }
}

extension NumberFormatting on int {
  /// Formatea números con separador de miles
  String toFormattedString() {
    return toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }
}

// Nuevo: Widgets helper reutilizables
class AnimatedCard extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final Curve curve;
  final double delay;

  const AnimatedCard({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 600),
    this.curve = Curves.easeOutCubic,
    this.delay = 0,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: duration,
      curve: curve,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 30 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class AnimatedCounter extends StatelessWidget {
  final int value;
  final Duration duration;
  final TextStyle? style;
  final String? suffix;
  final String? prefix;

  const AnimatedCounter({
    super.key,
    required this.value,
    this.duration = const Duration(milliseconds: 1200),
    this.style,
    this.suffix,
    this.prefix,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Text('${prefix ?? ''}$value${suffix ?? ''}', style: style);
      },
    );
  }
}
