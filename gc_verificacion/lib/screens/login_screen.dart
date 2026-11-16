import 'dart:convert';
import 'dart:io';

import 'package:android_id/android_id.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/app_version_service.dart';
import '../services/storage_service.dart';
import '../utils/aes_offline.dart';
import '../utils/constants.dart';
import '../utils/dialog_helper.dart';
import '../utils/dialog_utils.dart';
import '../utils/theme_colors.dart';
import '../utils/toast_helper.dart';
import '../widgets/screen_status_bar.dart';
import 'dashboard_screen.dart';
import 'inicio_screen.dart';
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
    if (Platform.isAndroid) {
      final id = await const AndroidId().getId();
      return id ?? 'unknown';
    }
    return 'unknown';
  }

  Future<void> _enterOffline(
    StorageService storage,
    String codigo,
    String nombre,
    String deviceId,
  ) async {
    await storage.saveLoginSession(
      userCode: codigo,
      userName: nombre,
      deviceId: deviceId,
    );
    if (!mounted) return;
    showSuccessToast(context, 'Sesión iniciada (offline)');
    await AppVersionService.notifyIfNeeded(context, storage);
    Get.off(() => const DashboardScreen(), routeName: '/dashboard');
  }

  Future<void> _attemptOfflineLogin() async {
    final close = showAppLoadingDialog(context, 'Verificando credenciales...');
    try {
      final storage = context.read<StorageService>();
      final deviceId = await _getDeviceId();
      final userIn = _usuarioController.text.trim().toLowerCase();
      final passIn = _passwordController.text;

      final storedHash = storage.getOfflineHash() ?? '';
      final savedUser = storage.getUserCodeSync()?.trim().toLowerCase() ?? '';
      if (storedHash.isNotEmpty) {
        final inputHash = sha256
            .convert(utf8.encode(passIn + AppConstants.offlineSalt))
            .toString();
        final userOk = savedUser.isEmpty || userIn == savedUser;
        if (inputHash == storedHash && userOk) {
          close();
          await _enterOffline(
            storage,
            savedUser.isNotEmpty ? savedUser : userIn,
            storage.getUserName() ?? userIn,
            deviceId,
          );
          return;
        }
      }

      final catalogos = storage.getCatalogos();
      final usuarios = catalogos['usuarios'] as List?;
      final conempreList = catalogos['conempre'] as List?;
      final enomCandidates = <String>[];
      final savedEnom = storage.getLoginEnom() ?? '';
      if (savedEnom.isNotEmpty) enomCandidates.add(savedEnom);
      if (conempreList != null) {
        for (final ce in conempreList) {
          if (ce is! Map) continue;
          final raw = ce['enom']?.toString() ?? '';
          if (raw.isNotEmpty) enomCandidates.add(raw);
        }
      }
      final uniqueEnoms = enomCandidates.toSet().toList();
      if (usuarios != null && uniqueEnoms.isNotEmpty) {
        for (final u in usuarios) {
          if (u is! Map) continue;
          final codigo = u['codigo']?.toString().trim().toLowerCase() ?? '';
          final passHex = (u['password_hex']?.toString() ?? '')
              .trim()
              .toUpperCase();
          if (codigo != userIn || passHex.isEmpty) continue;
          for (final enom in uniqueEnoms) {
            if (computePasswordHex(passIn, enom) == passHex) {
              final nombre = u['nombre']?.toString() ?? codigo;
              close();
              await _enterOffline(storage, codigo, nombre, deviceId);
              return;
            }
          }
        }
      }

      if (usuarios != null) {
        for (final u in usuarios) {
          if (u is! Map) continue;
          final codigo = u['codigo']?.toString().trim().toLowerCase() ?? '';
          if (codigo != userIn) continue;
          final libtri = u['libtri']?.toString() ?? '';
          if (libtri.isNotEmpty && passIn == libtri) {
            final nombre = u['nombre']?.toString() ?? codigo;
            close();
            await _enterOffline(storage, codigo, nombre, deviceId);
            return;
          }
        }
      }

      close();
      if (mounted) {
        showErrorToast(context, 'Usuario o contraseña incorrectos.');
      }
    } catch (_) {
      close();
      if (mounted) showErrorToast(context, 'Error en login offline.');
    }
  }

  Future<void> _login() async {
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _hasAttemptedValidation = true;
    });

    if (_usuarioController.text.trim().isEmpty) return;
    if (_passwordController.text.isEmpty) return;

    setState(() => _isLoading = true);
    final hasNet = await _hasInternet();
    if (!hasNet) {
      if (mounted) setState(() => _isLoading = false);
      await _attemptOfflineLogin();
      return;
    }

    final close = showAppLoadingDialog(context, 'Iniciando sesión...');
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
      if (!mounted) return;
      if (result['success'] == true) {
        final data = result['data'];
        String codigo = _usuarioController.text.trim();
        String nombre = codigo;
        if (data is Map &&
            data['usuario'] is List &&
            (data['usuario'] as List).isNotEmpty) {
          final u = (data['usuario'] as List).first as Map;
          codigo = (u['codigo'] ?? codigo).toString();
          nombre = (u['nombre'] ?? codigo).toString();
        }
        final storage = context.read<StorageService>();
        await storage.saveLoginSession(
          userCode: codigo,
          userName: nombre,
          deviceId: deviceId,
        );
        if (data is Map) {
          final oh = data['offline_hash']?.toString() ?? '';
          if (oh.isNotEmpty) await storage.saveOfflineHash(oh);
          final enom = data['enom']?.toString() ?? '';
          if (enom.isNotEmpty) await storage.saveLoginEnom(enom);
          final verPayload = AppVersionService.extractPayload(data);
          if (verPayload != null) {
            await AppVersionService.mergeServerPayload(storage, verPayload);
          }
        }
        close();
        showSuccessToast(context, 'Sesión iniciada');
        if (mounted) {
          await AppVersionService.notifyIfNeeded(context, storage);
        }
        Get.off(() => const DashboardScreen(), routeName: '/dashboard');
      } else {
        close();
        final code = result['errorCode']?.toString() ?? '';
        if (code == 'APP_VERSION_BLOCKED') {
          final storage = context.read<StorageService>();
          final verPayload = AppVersionService.extractPayload(result['data']);
          if (verPayload != null) {
            await AppVersionService.mergeServerPayload(storage, verPayload);
          }
          if (mounted) {
            await AppVersionService.showStatusDialog(
              context,
              AppVersionService.fromStorage(storage),
              barrierDismissible: false,
            );
          }
        } else if (code == 'DEVICE_NOT_REGISTERED' ||
            code == 'DEVICE_INACTIVE') {
          if (!mounted) return;
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
      if (mounted) showErrorToast(context, 'Error: $e');
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

  void _volver() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Get.offAll(() => const InicioScreen(), routeName: '/inicio');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenStatusBar(
      color: context.scaffoldMuted,
      iconBrightness: Theme.of(context).brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
      child: Scaffold(
        backgroundColor: context.scaffoldMuted,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: AppColors.primaryShadow,
                        ),
                        child: Center(
                          child: Image.asset(
                            'assets/images/logo_grs.png',
                            width: 56,
                            height: 56,
                            color: Colors.white,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.face_rounded,
                                size: 44,
                                color: Colors.white,
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        AppConstants.appTitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.textThemePrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Container(
                        decoration: BoxDecoration(
                          color: context.surfaceCard,
                          borderRadius: BorderRadius.circular(
                            AppColors.radiusXl,
                          ),
                          border: Border.all(color: context.borderSubtle),
                          boxShadow: AppColors.mediumShadow,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextFormField(
                                  controller: _usuarioController,
                                  textInputAction: TextInputAction.next,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  onEditingComplete: () {
                                    FocusScope.of(
                                      context,
                                    ).requestFocus(_passwordFocusNode);
                                  },
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: context.textThemePrimary,
                                  ),
                                  decoration: const InputDecoration(
                                    labelText: 'Usuario',
                                    prefixIcon: Icon(
                                      Icons.person_rounded,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                                if (_hasAttemptedValidation &&
                                    _usuarioController.text.trim().isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 16, top: 6),
                                    child: Text(
                                      'Ingrese su usuario',
                                      style: TextStyle(
                                        color: AppColors.error,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _passwordController,
                                  focusNode: _passwordFocusNode,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) =>
                                      _isLoading ? null : _login(),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: context.textThemePrimary,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: 'Contraseña',
                                    prefixIcon: const Icon(
                                      Icons.lock_rounded,
                                      color: AppColors.primary,
                                    ),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_rounded
                                            : Icons.visibility_off_rounded,
                                        color: context.textThemeMuted,
                                      ),
                                      onPressed: () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                    ),
                                  ),
                                ),
                                if (_hasAttemptedValidation &&
                                    _passwordController.text.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 16, top: 6),
                                    child: Text(
                                      'Ingrese su contraseña',
                                      style: TextStyle(
                                        color: AppColors.error,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 24),
                                SizedBox(
                                  width: double.infinity,
                                  height: 52,
                                  child: ElevatedButton(
                                    // un spinner aquí duplicaba el indicador.
                                    onPressed: _isLoading ? null : _login,
                                    child: const Text('INGRESAR'),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Divider(
                                        color: context.borderSubtle,
                                        thickness: 1,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Text(
                                        'o',
                                        style: TextStyle(
                                          color: context.textThemeMuted,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Divider(
                                        color: context.borderSubtle,
                                        thickness: 1,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: OutlinedButton.icon(
                                    onPressed: () => Get.to(
                                      () => const RegisterDeviceScreen(),
                                    ),
                                    icon: const Icon(
                                      Icons.phonelink_setup_rounded,
                                      size: 20,
                                    ),
                                    label: const Text('REGISTRAR DISPOSITIVO'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.primary,
                                      side: const BorderSide(
                                        color: AppColors.primary,
                                        width: 1.5,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          AppColors.radiusMd,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'v${AppConstants.appVersion}',
                        style: TextStyle(
                          color: context.textThemeMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 8,
                top: 8,
                child: IconButton(
                  onPressed: _volver,
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.surfaceCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: context.borderSubtle,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: context.textThemePrimary,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
