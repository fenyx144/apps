import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gc_necropcia/screens/dashboard_screen.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:get/get.dart';
import '../services/api_service.dart';
import '../services/catalog_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/dialog_helper.dart';
import '../utils/toast_helper.dart';
import 'register_device_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usuarioController = TextEditingController();
  final _passwordController = TextEditingController();
  final _apiService = ApiService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  late FocusNode _passwordFocusNode;
  bool _hasAttemptedValidation = false;

  Future<bool> _checkInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    }
  }

  /// Login offline: compara usuario con codigo y contraseña con libtri (sin desencriptar).
  /// userCode = codigo; userName = nombre (se muestra en AppDrawer).
  Future<void> _attemptOfflineLogin() async {
    final closeDialog = showChickenLoadingDialog(context, 'Verificando credenciales...');
    try {
      final catalogService = context.read<CatalogService>();
      final storage = context.read<StorageService>();
      final deviceId = await _getDeviceId();

      final usuarios = catalogService.catalogos['usuarios'] as List?;
      if (usuarios == null || usuarios.isEmpty) {
        closeDialog();
        showErrorToast(
          context,
          'No hay conexión a internet. Inténtelo más tarde.',
        );
        return;
      }

      final usuarioInput = _usuarioController.text.trim();
      final passwordInput = _passwordController.text;

      for (final u in usuarios) {
        if (u is! Map) continue;
        final uMap = Map<String, dynamic>.from(u);
        final codigo = (uMap['codigo'] ?? uMap['CODIGO'])?.toString().trim() ?? '';
        final libtri = (uMap['libtri'] ?? uMap['LIBTRI'])?.toString() ?? '';

        // Comparación directa: usuario==codigo, password==libtri (ya listo, sin desencriptar)
        if (codigo.toUpperCase() == usuarioInput.toUpperCase() &&
            libtri == passwordInput) {
          final nombre = (uMap['nombre'] ?? uMap['NOMBRE'])?.toString() ?? codigo;
          await storage.saveLoginSession(
            userCode: codigo, // identificador técnico
            userName: nombre, // nombre para mostrar en AppDrawer
            deviceId: deviceId,
          );
          closeDialog();
          showSuccessToast(context, 'Inicio de sesión exitoso');
          Get.off(
            () => const DashboardScreen(),
            transition: Transition.rightToLeftWithFade,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
          );
          return;
        }
      }

      closeDialog();
      showErrorToast(context, 'Usuario o contraseña incorrectos.');
    } catch (e) {
      closeDialog();
      debugPrint('Error en login offline: $e');
      showErrorToast(context, 'Error al verificar credenciales offline.');
    }
  }

  /// Descarga CENCOS, galpones, candidatos de match y usuarios.
  Future<void> _downloadCencosGalponesAfterLogin() async {
    final hasInternet = await _checkInternetConnection();
    if (!hasInternet) {
      debugPrint('⚠️ Sin conexión a internet, no se descargarán CENCOS, galpones ni usuarios');
      return;
    }

    final storage = context.read<StorageService>();
    final catalogService = context.read<CatalogService>();

    // 1. CENCOS y galpones (endpoint separado)
    try {
      debugPrint('📥 Descargando CENCOS y galpones después del login...');
      final result = await ApiService().downloadCencosGalpones();
      if (result['success'] == true) {
        final cencos = result['cencos'] as List;
        final galponesPorCenco =
            result['galponesPorCenco'] as Map<String, List<dynamic>>;

        final cencosData = cencos.map((c) => {
              'codigo': c.codigo?.toString() ?? '',
              'nombre': c.nombre?.toString() ?? '',
              'edad': c.edad?.toString() ?? '0',
              'fec_ing_min': c.fecIngMin?.toString() ?? '',
            }).toList();

        final galponesData = <String, List<Map<String, dynamic>>>{};
        galponesPorCenco.forEach((codigo, galpones) {
          galponesData[codigo] = galpones.map((g) => {
                'tcencos': g.tcencos,
                'tcodint': g.tcodint,
                'fec_ing_min': g.fecIngMin?.toString() ?? '',
              }).toList();
        });

        await storage.saveCencosGalpones(
          cencos: cencosData,
          galponesPorCenco: galponesData,
        );
        await storage.setLastDownloadDate();
        debugPrint('✅ CENCOS y galpones descargados y guardados después del login');
      } else {
        debugPrint('⚠️ No se pudieron descargar CENCOS y galpones: ${result['message']}');
      }
    } catch (e) {
      debugPrint('❌ Error descargando CENCOS y galpones: $e');
    }

    // 2. Candidatos de match para planificación offline (rango amplio inicial)
    try {
      final hoy = DateTime.now();
      final desde = hoy.subtract(const Duration(days: 30));
      final hasta = hoy.add(const Duration(days: 30));
      final result = await _apiService.downloadPlanMatchCandidates(
        desde: desde,
        hasta: hasta,
      );
      if (result['success'] == true) {
        final candidatos = (result['candidatos'] as List<dynamic>)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        await storage.savePlanMatchCandidates(
          candidates: candidatos,
          desde: desde,
          hasta: hasta,
        );
        debugPrint('✅ Candidatos de match guardados: ${candidatos.length}');
      } else {
        debugPrint('⚠️ No se pudieron descargar candidatos: ${result['message']}');
      }
    } catch (e) {
      debugPrint('❌ Error descargando candidatos de match: $e');
    }

    // 3. Usuarios para login offline (siempre se intenta)
    try {
      debugPrint('📥 Descargando catálogo usuarios para login offline...');
      final usuariosOk = await catalogService.downloadCatalogos(tablas: ['usuarios']);
      if (usuariosOk) {
        debugPrint('✅ Catálogo usuarios descargado para login offline');
      } else {
        debugPrint('⚠️ No se pudo descargar catálogo usuarios');
      }
    } catch (e) {
      debugPrint('❌ Error descargando usuarios: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _passwordFocusNode = FocusNode();
    // Restaurar barra de estado del sistema al volver al login
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
    );

    // Agregar listeners para ocultar errores cuando el usuario escriba
    _usuarioController.addListener(() {
      if (_hasAttemptedValidation && _usuarioController.text.isNotEmpty) {
        setState(() {}); // Actualizar UI para ocultar error
      }
    });

    _passwordController.addListener(() {
      if (_hasAttemptedValidation && _passwordController.text.isNotEmpty) {
        setState(() {}); // Actualizar UI para ocultar error
      }
    });
  }

  @override
  void dispose() {
    _usuarioController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<String> _getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ?? 'UNKNOWN_IOS';
      }
      return 'UNKNOWN_DEVICE';
    } catch (e) {
      return 'DEVICE_ERROR';
    }
  }

  Future<void> _handleLogin() async {
    FocusManager.instance.primaryFocus?.unfocus();

    // Marcar que se intentó validar
    setState(() {
      _hasAttemptedValidation = true;
    });

    // Validar campos manualmente antes de mostrar el diálogo de carga
    bool isValid = true;
    if (_usuarioController.text.trim().isEmpty) {
      isValid = false;
    }
    if (_passwordController.text.isEmpty) {
      isValid = false;
    }

    if (!isValid) {
      return;
    }

    // Verificar conexión a internet
    final hasInternet = await _checkInternetConnection();
    if (!hasInternet) {
      await _attemptOfflineLogin();
      return;
    }

    // Solo mostrar el diálogo si los campos son válidos
    final closeDialog = showChickenLoadingDialog(
      context,
      'Iniciando sesión...',
    );

    DateTime startTime = DateTime.now();
    bool loginSuccess = false;
    Map<String, dynamic>? loginResult;

    try {
      final deviceId = await _getDeviceId();
      final storage = context.read<StorageService>();
      final result = await _apiService.login(
        usuario: _usuarioController.text.trim(),
        password: _passwordController.text,
        androidId: deviceId,
        version: AppConstants.appVersion,
      );

      if (!mounted) {
        closeDialog();
        return;
      }

      if (result['success']) {
        final userData = result['data']['usuario'][0];
        debugPrint('DEBUG login - userData completo: ${userData.toString()}');
        debugPrint('DEBUG login - userData[\'codigo\']: ${userData['codigo']}');
        debugPrint('DEBUG login - userData[\'nombre\']: ${userData['nombre']}');

        final userCode = userData['codigo']?.toString() ?? '';
        final userName = userData['nombre']?.toString() ?? '';

        if (userCode.isEmpty) {
          debugPrint('ERROR: userCode está vacío o es null!');
        }

        await storage.saveLoginSession(
          userCode: userCode.isEmpty ? 'app_movil' : userCode,
          userName: userName,
          deviceId: deviceId,
        );

        // Verificar que se guardó correctamente
        final savedCode = storage.getUserCodeSync();
        debugPrint('DEBUG login - userCode guardado y verificado: $savedCode');

        loginSuccess = true;
      } else {
        loginResult = result;
      }
    } catch (e) {
      debugPrint('Error en login: $e');

    }

    final elapsed = DateTime.now().difference(startTime);
    if (elapsed < const Duration(seconds: 2)) {
      await Future.delayed(const Duration(seconds: 2) - elapsed);
    }

    // Cerrar diálogo
    closeDialog();

    // Ahora manejar resultado
    if (loginSuccess) {
      showSuccessToast(context, 'Inicio de sesión exitoso');

      // Descargar CENCOS/galpones aquí (en background) para asegurar datos actualizados
      // para el cálculo de edad por galpón.
      _downloadCencosGalponesAfterLogin();

      Get.off(
        () => const DashboardScreen(),
        transition: Transition.rightToLeftWithFade,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else if (loginResult != null) {
      _handleLoginError(loginResult);
    } else {
      showErrorToast(context, 'Error de conexión. Verifica tu internet.');
    }
  }

  void _handleLoginError(Map<String, dynamic> result) {
    final errorCode = result['errorCode'] as String?;
    debugPrint(result.toString());
    switch (errorCode) {
      case 'USER_NOT_FOUND':
        showErrorToast(context, 'Usuario no registrado.');
        _usuarioController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _usuarioController.text.length,
        );
        break;

      case 'USER_INACTIVE':
        showErrorToast(context, 'Tu cuenta de usuario está inactiva.');
        break;

      case 'WRONG_PASSWORD':
        showErrorToast(context, 'Contraseña incorrecta. Intenta nuevamente.');
        _passwordController.clear();
        break;

      case 'DEVICE_NOT_REGISTERED':
        _showDeviceNotRegisteredDialog(context);
        break;

      case 'DEVICE_INACTIVE':
        showErrorToast(
          context,
          'Tu dispositivo está registrado pero está inactivo.',
        );
        break;

      case 'MISSING_DATA':
        showErrorToast(context, 'Por favor completa todos los campos.');
        break;

      default:
        showErrorToast(context, 'Ocurrió un error. Inténtalo más tarde.');
    }
  }

  Future<bool?> _showDeviceNotRegisteredDialog(BuildContext context) {
    return Get.dialog<bool>(
      AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 12,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.accent.withOpacity(0.2),
                    AppColors.accentLight.withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.phonelink_erase_outlined,
                color: AppColors.accent,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Registro requerido',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 19),
            ),
          ],
        ),
        content: const Text(
          'Este dispositivo no está registrado en el sistema.\n\n¿Deseas registrarlo ahora para poder acceder?',
          style: TextStyle(fontSize: 15, color: Colors.black87, height: 1.5),
        ),
        actionsAlignment: MainAxisAlignment.end,
        actionsPadding: const EdgeInsets.only(right: 12, bottom: 12),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey[700],
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            child: const Text('Cancelar'),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: () {
                Get.back();
                Get.to(
                  () => const RegisterDeviceScreen(),
                  transition: Transition.circularReveal,
                  duration: Duration(milliseconds: 800),
                  curve: Curves.easeInOut,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Registrar',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 300),
      transitionCurve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // HEADER CURVO VERDE (usando ClipPath)
              _buildHeader(),

              const SizedBox(height: 40),

              // FORMULARIO COMPACTO
              _buildLoginForm(),

              const SizedBox(height: 32),

              // Versión y ID del dispositivo
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    Text(
                      'v${AppConstants.appVersion}',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return ClipPath(
      clipper: TopWaveClipper(), // Define abajo
      child: Container(
        height: 280,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primary, AppColors.primaryLight],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 40, bottom: 60),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Image.asset(
                    'assets/images/logo_grs.png',
                    width: 70,
                    height: 70,
                    color: Colors.white,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Título Sanidad
              const Text(
                'Necropsia',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  shadows: [
                    Shadow(
                      blurRadius: 8,
                      color: Colors.black26,
                      offset: Offset(0, 2),
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

  Widget _buildLoginForm() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppColors.mediumShadow,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildUserField(),
                const SizedBox(height: 4),
                _buildUserError(),
                const SizedBox(height: 12),
                _buildPasswordField(),
                const SizedBox(height: 4),
                _buildPasswordError(),
                const SizedBox(height: 24),
                _buildLoginButton(),
                const SizedBox(height: 20),
                _buildDivider(),
                const SizedBox(height: 20),
                _buildRegisterDeviceButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: _usuarioController,
        textInputAction: TextInputAction.next,
        textCapitalization: TextCapitalization.characters,
        onEditingComplete: () {
          FocusScope.of(context).requestFocus(_passwordFocusNode);
        },
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
        decoration: InputDecoration(
          labelText: 'Usuario',
          labelStyle: TextStyle(
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
          hintText: 'Ingresa tu usuario',
          hintStyle: TextStyle(color: Colors.grey.shade400),
          prefixIcon: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(
              Icons.person_rounded,
              color: Colors.grey.shade700,
              size: 22,
            ),
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.error, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.error, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          errorText: null, // No mostrar error dentro del input
          errorStyle: const TextStyle(height: 0), // Ocultar espacio del error
        ),
        validator: (value) {
          // Siempre retornar null para que no se muestre error dentro del input
          // La validación se maneja manualmente en _handleLogin
          return null;
        },
      ),
    );
  }

  Widget _buildUserError() {
    // Solo mostrar error si se intentó validar y el campo está vacío
    if (!_hasAttemptedValidation || _usuarioController.text.isNotEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 4),
      child: Text(
        'Ingrese su usuario',
        style: TextStyle(
          color: AppColors.error,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildPasswordError() {
    // Solo mostrar error si se intentó validar y el campo está vacío
    if (!_hasAttemptedValidation || _passwordController.text.isNotEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 4),
      child: Text(
        'Ingrese su contraseña',
        style: TextStyle(
          color: AppColors.error,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildPasswordField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: _passwordController,
        focusNode: _passwordFocusNode,
        textInputAction: TextInputAction.go,
        textCapitalization: TextCapitalization.characters,
        onEditingComplete: _handleLogin,
        obscureText: _obscurePassword,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
        decoration: InputDecoration(
          labelText: 'Contraseña',
          labelStyle: TextStyle(
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
          hintText: 'Ingresa tu contraseña',
          hintStyle: TextStyle(color: Colors.grey.shade400),
          prefixIcon: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(
              Icons.lock_rounded,
              color: Colors.grey.shade700,
              size: 22,
            ),
          ),
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              color: Colors.grey.shade600,
              size: 22,
            ),
            onPressed: () {
              setState(() {
                _obscurePassword = !_obscurePassword;
              });
            },
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.error, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.error, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          errorText: null, // No mostrar error dentro del input
          errorStyle: const TextStyle(height: 0), // Ocultar espacio del error
        ),
        validator: (value) {
          // Siempre retornar null para que no se muestre error dentro del input
          // La validación se maneja manualmente en _handleLogin
          return null;
        },
      ),
    );
  }

  Widget _buildLoginButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: _isLoading ? null : AppColors.primaryGradient,
        boxShadow: _isLoading
            ? null
            : [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: /*_isLoading
            ? Image.asset(
                'assets/gifs/gallina.gif',
                width: 40,
                height: 40,
                fit: BoxFit.contain,
              )
            : */ const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.login_rounded, size: 24, color: Colors.white),
            SizedBox(width: 12),
            Text(
              'LOGIN',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            color: AppColors.primary.withOpacity(0.2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'o',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            color: AppColors.primary.withOpacity(0.2),
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterDeviceButton() {
    return Center(
      child: TextButton.icon(
        onPressed: _isLoading
            ? null
            : () {
                Get.to(
                  () => const RegisterDeviceScreen(),
                  transition: Transition.rightToLeftWithFade,
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                );
              },
        icon: Icon(Icons.phone_android_rounded, color: AppColors.primary),
        label: const Text(
          'Registrar tu Dispositivo',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

// CLIPPER PARA EL HEADER CURVO CON ONDA CÓNCAVA
class TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    var path = Path();
    // Iniciar desde la esquina superior izquierda
    path.lineTo(0, 0);
    // Línea hasta el inicio de la curva
    path.lineTo(0, size.height * 0.75);
    // Curva cóncava más pronunciada (onda suave)
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height *
          0.85, // Punto de control más bajo para curva más pronunciada
      size.width * 0.5,
      size.height * 0.8, // Punto medio de la curva
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.75, // Segundo punto de control
      size.width,
      size.height * 0.8, // Final de la curva
    );
    // Línea hasta la esquina superior derecha
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
