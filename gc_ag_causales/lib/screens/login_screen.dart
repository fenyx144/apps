import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/catalog_service.dart';
import '../services/catalog_sync_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/dialog_helper.dart';
import '../utils/dialog_utils.dart';
import '../utils/theme_colors.dart';
import '../utils/toast_helper.dart';
import '../widgets/screen_status_bar.dart';
import 'dashboard_screen.dart';
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
  final _api = ApiService();
  bool _isLoading = false;
  bool _obscurePassword = true;
  late FocusNode _passwordFocusNode;
  bool _hasAttemptedValidation = false;

  Future<bool> _hasInternet() async {
    try {
      final r = await InternetAddress.lookup('google.com');
      return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    }
  }

  Future<String> _getDeviceId() async {
    final plugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final a = await plugin.androidInfo;
      return a.id;
    }
    return 'unknown';
  }

  Future<void> _syncCatalogsAfterLogin() async {
    final storage = context.read<StorageService>();
    final catalog = context.read<CatalogService>();
    final close = showChickenLoadingDialog(context, 'Descargando catálogos...');
    try {
      final result = await CatalogSyncService().syncAll(
        storage: storage,
        catalog: catalog,
        forzar: true,
      );
      close();
      if (!mounted) return;
      if (!result.hadInternet) {
        showErrorToast(
          context,
          '${AppStrings.sinConexion} Puede descargar desde el menú.',
        );
      } else if (!storage.hasCencosGalponesLocal()) {
        showErrorToast(
          context,
          'No se descargaron galpones. Use el menú → Descargar catálogos.',
        );
      }
    } catch (e) {
      close();
      if (mounted) {
        showErrorToast(context, 'Error al descargar catálogos: $e');
      }
    }
  }

  Future<void> _attemptOfflineLogin() async {
    final close = showChickenLoadingDialog(context, 'Verificando credenciales...');
    try {
      final catalog = context.read<CatalogService>();
      await catalog.loadFromPrefs();
      final usuarios = catalog.catalogos['usuarios'] as List?;
      if (usuarios == null || usuarios.isEmpty) {
        close();
        showErrorToast(context, AppStrings.sinConexion);
        return;
      }
      final userIn = _usuarioController.text.trim();
      final passIn = _passwordController.text;
      for (final u in usuarios) {
        if (u is! Map) continue;
        final m = Map<String, dynamic>.from(u);
        final codigo = (m['codigo'] ?? '').toString().trim();
        final libtri = (m['libtri'] ?? '').toString();
        if (codigo.toUpperCase() == userIn.toUpperCase() && libtri == passIn) {
          final nombre = (m['nombre'] ?? codigo).toString();
          await context.read<StorageService>().saveLoginSession(
                userCode: codigo,
                userName: nombre,
                deviceId: await _getDeviceId(),
              );
          close();
          showSuccessToast(context, 'Inicio de sesión exitoso');
          Get.off(() => const DashboardScreen());
          return;
        }
      }
      close();
      showErrorToast(context, 'Usuario o contraseña incorrectos.');
    } catch (e) {
      close();
      showErrorToast(context, 'Error en login offline.');
    }
  }

  Future<void> _login() async {
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _hasAttemptedValidation = true;
    });

    var isValid = true;
    if (_usuarioController.text.trim().isEmpty) isValid = false;
    if (_passwordController.text.isEmpty) isValid = false;
    if (!isValid) return;

    setState(() => _isLoading = true);
    final hasNet = await _hasInternet();
    if (!hasNet) {
      setState(() => _isLoading = false);
      await _attemptOfflineLogin();
      return;
    }

    final close = showChickenLoadingDialog(context, 'Iniciando sesión...');
    final start = DateTime.now();
    try {
      final deviceId = await _getDeviceId();
      final result = await _api.login(
        usuario: _usuarioController.text.trim(),
        password: _passwordController.text,
        androidId: deviceId,
        version: AppConstants.appVersion,
      );
      final elapsed = DateTime.now().difference(start);
      if (elapsed.inMilliseconds < 2000) {
        await Future.delayed(
          Duration(milliseconds: 2000 - elapsed.inMilliseconds),
        );
      }
      print('result: $result');
      if (result['success'] == true) {
        final data = result['data'];
        String codigo = _usuarioController.text.trim();
        String nombre = codigo;
        if (data is Map && data['usuario'] is List && (data['usuario'] as List).isNotEmpty) {
          final u = (data['usuario'] as List).first as Map;
          codigo = (u['codigo'] ?? codigo).toString();
          nombre = (u['nombre'] ?? codigo).toString();
        }
        await context.read<StorageService>().saveLoginSession(
              userCode: codigo,
              userName: nombre,
              deviceId: deviceId,
            );
        close();
        showSuccessToast(context, 'Inicio de sesión exitoso');
        await _syncCatalogsAfterLogin();
        if (!mounted) return;
        Get.off(() => const DashboardScreen());
      } else {
        close();
        final code = result['errorCode']?.toString() ?? '';
        if (code == 'DEVICE_NOT_REGISTERED' || code == 'DEVICE_INACTIVE') {
          showAppDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(
                'Dispositivo no registrado',
                style: TextStyle(color: ctx.textThemePrimary),
              ),
              content: Text(
                result['message']?.toString() ?? '',
                style: TextStyle(color: ctx.textThemeMuted),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Get.to(() => const RegisterDeviceScreen());
                  },
                  child: const Text('Registrar'),
                ),
              ],
            ),
          );
        } else {
          showErrorToast(
            context,
            result['message']?.toString() ?? 'Error de login',
          );
        }
      }
    } catch (e) {
      close();
      showErrorToast(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _passwordFocusNode = FocusNode();
    _usuarioController.addListener(() {
      if (_hasAttemptedValidation && _usuarioController.text.isNotEmpty) {
        setState(() {});
      }
    });
    _passwordController.addListener(() {
      if (_hasAttemptedValidation && _passwordController.text.isNotEmpty) {
        setState(() {});
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

  @override
  Widget build(BuildContext context) {
    return ScreenStatusBar(
      color: AppColors.primary,
      iconBrightness: Brightness.light,
      child: Scaffold(
      backgroundColor: context.scaffoldMuted,
      body: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 40),
              _buildLoginForm(),
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'v${AppConstants.appVersion}',
                  style: TextStyle(
                    color: context.textThemeMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildHeader() {
    return ClipPath(
      clipper: TopWaveClipper(),
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
          padding: EdgeInsets.only(
            top: 40 + MediaQuery.viewPaddingOf(context).top,
            bottom: 60,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
              Text(
                AppConstants.appTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
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
                textAlign: TextAlign.center,
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
          color: context.surfaceCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.borderSubtle),
          boxShadow: context.cardShadow(blur: 12, dy: 6),
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
    final isDark = context.isAppDark;
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderSubtle, width: 1),
        boxShadow: isDark ? null : context.cardShadow(blur: 4, dy: 2),
      ),
      child: TextFormField(
        controller: _usuarioController,
        textInputAction: TextInputAction.next,
        textCapitalization: TextCapitalization.characters,
        onEditingComplete: () {
          FocusScope.of(context).requestFocus(_passwordFocusNode);
        },
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: context.textThemePrimary,
        ),
        decoration: InputDecoration(
          labelText: 'Usuario',
          labelStyle: TextStyle(
            color: context.textThemeMuted,
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
          hintText: 'Ingresa tu usuario',
          hintStyle: TextStyle(color: context.textThemeMuted.withValues(alpha: 0.7)),
          prefixIcon: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(
              Icons.person_rounded,
              color: context.textThemeMuted,
              size: 22,
            ),
          ),
          filled: true,
          fillColor: context.surfaceElevated,
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
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.error, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.error, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          errorText: null,
          errorStyle: const TextStyle(height: 0),
        ),
        validator: (_) => null,
      ),
    );
  }

  Widget _buildUserError() {
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
    final isDark = context.isAppDark;
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: isDark ? 0.5 : 0.3),
          width: 1,
        ),
        boxShadow: isDark ? null : context.cardShadow(blur: 4, dy: 2),
      ),
      child: TextFormField(
        controller: _passwordController,
        focusNode: _passwordFocusNode,
        textInputAction: TextInputAction.go,
        textCapitalization: TextCapitalization.characters,
        onEditingComplete: _login,
        obscureText: _obscurePassword,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: context.textThemePrimary,
        ),
        decoration: InputDecoration(
          labelText: 'Contraseña',
          labelStyle: TextStyle(
            color: context.textThemeMuted,
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
          hintText: 'Ingresa tu contraseña',
          hintStyle: TextStyle(color: context.textThemeMuted.withValues(alpha: 0.7)),
          prefixIcon: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(
              Icons.lock_rounded,
              color: context.textThemeMuted,
              size: 22,
            ),
          ),
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              color: context.textThemeMuted,
              size: 22,
            ),
            onPressed: () {
              setState(() {
                _obscurePassword = !_obscurePassword;
              });
            },
          ),
          filled: true,
          fillColor: context.surfaceElevated,
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
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.error, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.error, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          errorText: null,
          errorStyle: const TextStyle(height: 0),
        ),
        validator: (_) => null,
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
        onPressed: _isLoading ? null : _login,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white,
                ),
              )
            : const Row(
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
              color: context.textThemeMuted,
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
        icon: const Icon(Icons.phone_android_rounded, color: AppColors.primary),
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

class TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, 0);
    path.lineTo(0, size.height * 0.75);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height * 0.85,
      size.width * 0.5,
      size.height * 0.8,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.75,
      size.width,
      size.height * 0.8,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
