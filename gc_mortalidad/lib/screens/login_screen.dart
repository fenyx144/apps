import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/catalog_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/theme_extensions.dart';
import '../utils/aes_offline.dart';
import '../utils/dialog_helper.dart';
import '../utils/toast_helper.dart';
import '../utils/top_wave_clipper.dart';
import '../widgets/poultry_icon.dart';
import 'dashboard_screen.dart';
import 'register_device_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usuarioController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usuarioFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final _apiService = ApiService();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _hasAttemptedValidation = false;

  @override
  void dispose() {
    _usuarioController.dispose();
    _passwordController.dispose();
    _usuarioFocusNode.dispose();
    _passwordFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<bool> _checkInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    }
  }

  Future<String> _getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) return (await deviceInfo.androidInfo).id;
    if (Platform.isIOS) {
      return (await deviceInfo.iosInfo).identifierForVendor ?? 'UNKNOWN_IOS';
    }
    return 'UNKNOWN_DEVICE';
  }

  Future<void> _attemptOfflineLogin() async {
    // Cerrar teclado inmediatamente
    FocusScope.of(context).unfocus();
    await SystemChannels.textInput.invokeMethod('TextInput.hide');

    final closeDialog = showChickenLoadingDialog(context, 'Verificando credenciales...');
    try {
      final catalogService = context.read<CatalogService>();
      await catalogService.loadFromPrefs();
      final storage = context.read<StorageService>();
      final deviceId = await _getDeviceId();
      final usuarioInput = _usuarioController.text.trim().toLowerCase();
      final passwordInput = _passwordController.text;

      // ── Metodo 1: offline_hash guardado (backward compatibility) ──
      final storedHash = storage.getOfflineHash() ?? '';
      debugPrint('[OFFLINE_LOGIN] Metodo 1: storedHash=${storedHash.isNotEmpty ? storedHash.substring(0, 10) + '...' : 'vacio'}');
      if (storedHash.isNotEmpty) {
        final inputHash = sha256.convert(utf8.encode(passwordInput + 'M0rt4l1d4d_S4lt_2026')).toString();
        debugPrint('[OFFLINE_LOGIN] Metodo 1: inputHash=${inputHash.substring(0, 10)}... storedHash=${storedHash.substring(0, 10)}... match=${inputHash == storedHash}');
        if (inputHash == storedHash) {
          debugPrint('[OFFLINE_LOGIN] login exitoso via offline_hash');
          final storedPermisos = storage.getPermisos();
          await storage.saveLoginSession(
            userCode: usuarioInput,
            userName: 'Usuario',
            deviceId: deviceId,
            permisos: storedPermisos,
          );
          closeDialog();
          if (!mounted) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Get.off(() => const DashboardScreen());
          });
          return;
        }
      }

      // ── Metodo 2: AES-128-ECB con password_hex + conempre ──
      final usuarios = catalogService.catalogos['usuarios'] as List?;
      final conempreList = catalogService.catalogos['conempre'] as List?;
      debugPrint('[OFFLINE_LOGIN] Metodo 2: usuarios=${usuarios?.length ?? 0} conempre=${conempreList?.length ?? 0}');

      // Recolectar TODOS los enom disponibles
      final enomCandidates = <String>[];
      
      // 1. Primero, el enom guardado del ultimo login exitoso (es el mas confiable)
      final savedLoginEnom = storage.getLoginEnom() ?? '';
      if (savedLoginEnom.isNotEmpty) {
        enomCandidates.add(savedLoginEnom);
        debugPrint('[OFFLINE_LOGIN] enom guardado del login: len=${savedLoginEnom.length} hex=${savedLoginEnom.codeUnits.map((b) => b.toRadixString(16).padLeft(2, '0')).join('')}');
      }
      
      // 2. Los enom del catalogo conempre descargado
      if (conempreList != null) {
        for (final ce in conempreList) {
          if (ce is! Map) continue;
          final raw = ce['enom']?.toString() ?? '';
          if (raw.isNotEmpty) {
            enomCandidates.add(raw);
            final trimmed = raw.trim();
            if (trimmed != raw) enomCandidates.add(trimmed);
            debugPrint('[OFFLINE_LOGIN] enom candidato: epre=${ce['epre']} len=${raw.length} hex=${raw.codeUnits.map((b) => b.toRadixString(16).padLeft(2, '0')).join('')}');
          }
        }
      }
      // Quitar duplicados
      final uniqueEnoms = enomCandidates.toSet().toList();
      debugPrint('[OFFLINE_LOGIN] enomCandidates=${uniqueEnoms.length}');

      if (usuarios != null && usuarios.isNotEmpty && uniqueEnoms.isNotEmpty) {
        for (final u in usuarios) {
          if (u is! Map) continue;
          final codigo = u['codigo']?.toString().trim().toLowerCase() ?? '';
          final passHex = (u['password_hex']?.toString() ?? '').trim().toUpperCase();
          if (codigo != usuarioInput || passHex.isEmpty) continue;

          debugPrint('[OFFLINE_LOGIN] verificando usuario=$codigo con ${uniqueEnoms.length} clave(s)...');
          for (final candidateEnom in uniqueEnoms) {
            final computedHex = computePasswordHex(passwordInput, candidateEnom);
            debugPrint('[OFFLINE_LOGIN]   enom(hex)=${candidateEnom.codeUnits.map((b) => b.toRadixString(16).padLeft(2, '0')).join('')} => $computedHex vs esperado=$passHex match=${computedHex == passHex}');
            if (computedHex == passHex) {
              final nombre = u['nombre']?.toString() ?? 'Usuario';
              debugPrint('[OFFLINE_LOGIN] login exitoso via AES-ECB con enom="${candidateEnom}"');
              final storedPermisos = storage.getPermisos();
              await storage.saveLoginSession(
                userCode: codigo,
                userName: nombre,
                deviceId: deviceId,
                permisos: storedPermisos,
              );
              closeDialog();
              if (!mounted) return;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                Get.off(() => const DashboardScreen());
              });
              return;
            }
          }
        }
      } else {
        debugPrint('[OFFLINE_LOGIN] Metodo 2: catalogos insuficientes: '
            'usuarios=${usuarios?.length ?? 0} enomCandidates=${uniqueEnoms.length}');
      }

      // ── Metodo 3: libtri (texto plano) como fallback ──
      if (usuarios != null && usuarios.isNotEmpty) {
        for (final u in usuarios) {
          if (u is! Map) continue;
          final codigo = u['codigo']?.toString().trim().toLowerCase() ?? '';
          if (codigo != usuarioInput) continue;
          final libtri = u['libtri']?.toString() ?? '';
          debugPrint('[OFFLINE_LOGIN] Metodo 3: libtri="${libtri.length > 6 ? libtri.substring(0, 3) + '...' : libtri}" pwInputLen=${passwordInput.length} matchDirect=${passwordInput == libtri}');
          if (libtri.isNotEmpty && passwordInput == libtri) {
            final nombre = u['nombre']?.toString() ?? 'Usuario';
            debugPrint('[OFFLINE_LOGIN] login exitoso via libtri');
            final storedPermisos = storage.getPermisos();
            await storage.saveLoginSession(
              userCode: codigo,
              userName: nombre,
              deviceId: deviceId,
              permisos: storedPermisos,
            );
            closeDialog();
            if (!mounted) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              Get.off(() => const DashboardScreen());
            });
            return;
          }
        }
      }

      closeDialog();
      debugPrint('[OFFLINE_LOGIN] TODOS los metodos fallaron. '
          'storedHash=${storedHash.isNotEmpty} '
          'usuarios=${usuarios?.length ?? 0} '
          'conempre=${conempreList?.length ?? 0} '
          'enomCandidates=${uniqueEnoms.length}');
      if (mounted) showErrorToast(context, 'Usuario o contrase\u00f1a incorrectos.');
    } catch (e) {
      closeDialog();
      debugPrint('[OFFLINE_LOGIN_ERROR] $e');
      if (mounted) showErrorToast(context, 'Error al verificar usuario.');
    }
  }

  /// Cierra el teclado y muestra el error de validación de forma que siempre
  /// se aprecie (aunque el teclado esté abierto o cerrándose): toast + scroll
  /// para que los mensajes bajo los campos queden a la vista.
  void _showValidationError({required bool usuarioVacio, required bool passwordVacio}) {
    FocusScope.of(context).unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    final String mensaje;
    if (usuarioVacio && passwordVacio) {
      mensaje = 'Debe ingresar su usuario y contraseña';
    } else if (usuarioVacio) {
      mensaje = 'Debe ingresar su usuario';
    } else {
      mensaje = 'Debe ingresar su contraseña';
    }
    showErrorToast(context, mensaje);
    // Desplazar el formulario hacia arriba para que se vean los mensajes
    // de error ("Requerido") debajo de los campos.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    // Pequeña pausa para que el teclado se cierre antes de mostrar diálogos
    await Future.delayed(const Duration(milliseconds: 150));
    setState(() => _hasAttemptedValidation = true);
    final usuarioVacio = _usuarioController.text.trim().isEmpty;
    final passwordVacio = _passwordController.text.isEmpty;
    if (usuarioVacio || passwordVacio) {
      _showValidationError(usuarioVacio: usuarioVacio, passwordVacio: passwordVacio);
      return;
    }

    if (!await _checkInternet()) {
      await _attemptOfflineLogin();
      return;
    }

    setState(() => _isLoading = true);
    final closeDialog = showChickenLoadingDialog(context, 'Iniciando sesión...');

    try {
      final deviceId = await _getDeviceId();
      final storage = context.read<StorageService>();
      final result = await _apiService.login(
        usuario: _usuarioController.text.trim(),
        password: _passwordController.text,
        androidId: deviceId,
        version: AppConstants.appVersion,
      );
      closeDialog();
      if (!mounted) return;

      // Depuración: imprime en consola con flutter logs
      print('[LOGIN_RESPONSE] ${jsonEncode(result)}');

      if (result['success'] == true) {
        final data = result['data'];
        final userData = (data?['usuario'] as List?)?.first;
        final userMap = userData is Map
            ? Map<String, dynamic>.from(userData)
            : <String, dynamic>{};
        Map<String, dynamic>? visibilidad;
        final visRaw = data?['visibilidad'];
        if (visRaw is Map) {
          visibilidad = Map<String, dynamic>.from(visRaw);
        }
        var codigoSanidad = data?['codigo_usuario']?.toString().trim() ??
            userMap['codigo_usuario']?.toString().trim() ??
            '';
        if (codigoSanidad.isEmpty && visibilidad != null) {
          codigoSanidad = visibilidad['codigo_usuario']?.toString().trim() ?? '';
        }
        // Obtener permisos ACL antes de saveLoginSession
        final permisosRaw = data?['permisos'];
        Map<String, dynamic> permisosMap;
        if (permisosRaw is Map) {
          permisosMap = Map<String, dynamic>.from(permisosRaw);
          debugPrint('[LOGIN_PERMISOS] permisos guardados: $permisosRaw');
        } else {
          permisosMap = <String, dynamic>{};
          debugPrint('[LOGIN_PERMISOS] permisos vacíos guardados (tabla san_mortalidad_acceso_app sin registros)');
        }
        await storage.saveLoginSession(
          userCode: userMap['codigo']?.toString() ?? 'app_movil',
          userName: userMap['nombre']?.toString() ?? 'Usuario',
          deviceId: deviceId,
          usuarioCodigoSanidad:
              codigoSanidad.isNotEmpty ? codigoSanidad : null,
          mortalityVisibility: visibilidad,
          permisos: permisosMap,
        );
        // Guardar hash offline para login sin internet
        // Calcular localmente desde la contraseña ingresada (no depende del servidor)
        final computedHash =
            sha256.convert(utf8.encode(_passwordController.text + 'M0rt4l1d4d_S4lt_2026')).toString();
        debugPrint('[LOGIN_SAVE_HASH] guardando offline_hash (computado localmente): $computedHash');
        await storage.saveOfflineHash(computedHash);
        // También guardar offline_hash del servidor por si acaso
        final serverHash = data?['offline_hash']?.toString() ?? '';
        if (serverHash.isNotEmpty && serverHash != computedHash) {
          debugPrint('[LOGIN_SAVE_HASH] guardando offline_hash del servidor (diferente): $serverHash');
          await storage.saveOfflineHash(serverHash);
        }
        // Guardar enom del servidor para login offline (evita problema de cache desactualizada)
        final loginEnom = data?['enom']?.toString() ?? '';
        if (loginEnom.isNotEmpty) {
          debugPrint('[LOGIN_SAVE_ENOM] guardando enom del servidor: $loginEnom');
          await storage.saveLoginEnom(loginEnom);
        }
        // Forzar cierre del teclado
        SystemChannels.textInput.invokeMethod('TextInput.hide');
        // El login ya NO descarga catálogos: navegar al Dashboard de inmediato.
        // La descarga completa (usuarios, granjas, causas, cantidad de pollos,
        // liquidaciones, auditorías, etc.) la hace el botón "Descargar" del
        // menú lateral (AppDrawer), que mantiene los datos para uso offline.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Get.off(() => const DashboardScreen());
        });
      } else {
        final errorCode = result['errorCode']?.toString();
        if (errorCode == 'DEVICE_NOT_REGISTERED') {
          _showDeviceNotRegisteredDialog();
        } else if (errorCode == 'INVALID_TOKEN') {
          showErrorToast(context, 'Error de conexión, inténtelo más tarde');
        } else if (errorCode == 'USER_NOT_FOUND') {
          showErrorToast(context, 'Usuario no encontrado. Verifique el código e intente de nuevo.');
        } else if (errorCode == 'WRONG_PASSWORD') {
          showErrorToast(context, 'Contraseña incorrecta.');
        } else if (errorCode == 'INVALID_JSON' || errorCode == 'EMPTY_RESPONSE') {
          showErrorToast(context, result['message']?.toString() ?? 'Error del servidor.');
        } else if (errorCode == 'FATAL_ERROR') {
          showErrorToast(context, result['debug']?.toString() ?? 'Error desconocido');
        } else {
          showErrorToast(context, result['message']?.toString() ?? 'Error al iniciar sesión');
        }
      }
    } catch (e) {
      closeDialog();
      print('[LOGIN_ERROR] $e');
      if (mounted) showErrorToast(context, 'Error inesperado. Intente de nuevo.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showDeviceNotRegisteredDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
        backgroundColor: isDark ? AppColors.darkCard : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Registro requerido'),
        content: const Text('Este dispositivo no está registrado. ¿Deseas registrarlo ahora?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              FocusScope.of(context).unfocus();
              Get.to(() => const RegisterDeviceScreen());
            },
            child: const Text('Registrar'),
          ),
        ],
      );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.primary,
      body: SafeArea(
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: isDark ? AppColors.darkBackground : const Color(0xFFF7FBF2),
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 36),
                _buildLoginForm(context),
                const SizedBox(height: 24),
                Text(
                  'v${AppConstants.appVersion}',
                  style: TextStyle(color: context.mutedTextColor, fontSize: 12),
                ),
                const SizedBox(height: 32),
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
        height: 260,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primary, AppColors.primaryLight],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Image.asset(
                  'assets/images/logo_grs.png',
                  width: 64,
                  height: 64,
                  color: Colors.white,
                  errorBuilder: (_, __, ___) => const PoultryIcon(
                    size: 48,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Mortalidad',
              style: TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginForm(BuildContext context) {
    final isDark = context.isDarkTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isDark ? null : AppColors.mediumShadow,
          border: isDark
              ? Border.all(color: Colors.white.withValues(alpha: 0.08))
              : null,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _field(
              context: context,
              controller: _usuarioController,
              focusNode: _usuarioFocusNode,
              label: 'Usuario',
              icon: Icons.person_rounded,
              textCapitalization: TextCapitalization.characters,
              error: _hasAttemptedValidation && _usuarioController.text.trim().isEmpty
                  ? 'Requerido'
                  : null,
              textInputAction: TextInputAction.next,
              onSubmit: () {
                _passwordFocusNode.requestFocus();
              },
            ),
            const SizedBox(height: 14),
            _field(
              context: context,
              controller: _passwordController,
              focusNode: _passwordFocusNode,
              label: 'Contraseña',
              icon: Icons.lock_rounded,
              obscure: _obscurePassword,
              error: _hasAttemptedValidation && _passwordController.text.isEmpty
                  ? 'Requerido'
                  : null,
              suffix: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              textInputAction: TextInputAction.done,
              onSubmit: _handleLogin,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _handleLogin,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.login_rounded),
                label: const Text('LOGIN', style: TextStyle(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: Divider(color: context.borderColor)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('o', style: TextStyle(color: context.mutedTextColor)),
                ),
                Expanded(child: Divider(color: context.borderColor)),
              ],
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                FocusScope.of(context).unfocus();
                Get.to(() => const RegisterDeviceScreen());
              },
              icon: const Icon(Icons.phone_android_rounded, color: AppColors.textSecondary),
              label: const Text(
                'Registrar tu Dispositivo',
                style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required BuildContext context,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required IconData icon,
    String? error,
    bool obscure = false,
    Widget? suffix,
    TextCapitalization textCapitalization = TextCapitalization.none,
    TextInputAction textInputAction = TextInputAction.next,
    VoidCallback? onSubmit,
  }) {
    final isDark = context.isDarkTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscure,
          textCapitalization: textCapitalization,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          textInputAction: textInputAction,
          onSubmitted: onSubmit != null ? (_) => onSubmit() : null,
          decoration: AppInputStyles.decoration(
            context,
            r: 12,
            labelText: label,
            prefixIcon: Icon(
              icon,
              color: isDark ? Colors.white70 : Colors.grey.shade700,
            ),
            suffixIcon: suffix,
            fillColor: isDark ? AppColors.darkBackground : Colors.white,
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Text(error, style: const TextStyle(color: AppColors.error, fontSize: 12)),
          ),
      ],
    );
  }
}
