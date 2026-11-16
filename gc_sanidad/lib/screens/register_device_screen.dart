import 'package:flutter/material.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';
import '../utils/app_fonts.dart';
import '../utils/toast_helper.dart';

class RegisterDeviceScreen extends StatefulWidget {
  const RegisterDeviceScreen({super.key});

  @override
  State<RegisterDeviceScreen> createState() => _RegisterDeviceScreenState();
}

class _RegisterDeviceScreenState extends State<RegisterDeviceScreen>
  // with SingleTickerProviderStateMixin
    {
  final _formKey = GlobalKey<FormState>();
  final _descripcionController = TextEditingController();
  final _apiService = ApiService();

  bool _isLoading = false;
  String _androidId = '';
  String _fabricante = '';
  String _familia = '';
  String _modelo = '';

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();

  }

  @override
  void dispose() {
    _descripcionController.dispose();
    super.dispose();
  }

  Future<void> _loadDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        setState(() {
          _androidId = androidInfo.id;
          _fabricante = androidInfo.manufacturer;
          _familia = androidInfo.brand;
          _modelo = androidInfo.model;
        });
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        setState(() {
          _androidId = iosInfo.identifierForVendor ?? 'UNKNOWN_IOS';
          _fabricante = 'Apple';
          _familia = 'iPhone';
          _modelo = iosInfo.model;
          _descripcionController.text = 'Apple ${iosInfo.model}';
        });
      }
    } catch (e) {
      setState(() {
        _androidId = 'DEVICE_ERROR';
        _fabricante = 'Unknown';
        _familia = 'Unknown';
        _modelo = 'Unknown';
      });
    }
  }

  Future<void> _handleRegister() async {
  if (!_formKey.currentState!.validate()) {
    return;
  }

  setState(() => _isLoading = true);

  try {
    final result = await _apiService.registerDevice(
      androidId: _androidId,
      fabricante: _fabricante,
      familia: _familia,
      modelo: _modelo,
      descripcion: _descripcionController.text.trim(),
    );

    if (!mounted) return;

    // Verificar el errorCode para casos especiales
    final errorCode = result['errorCode'] as String?;

    // CASO 1: Dispositivo ya registrado y ACTIVO
    if (errorCode == 'DEVICE_ALREADY_ACTIVE') {
      _handleDeviceAlreadyActive(context);
      return;
    }

    // CASO 2: Dispositivo INACTIVO
    if (errorCode == 'DEVICE_INACTIVE') {
      showInfoToast(context, 'Este dispositivo está registrado pero ha sido desactivado.');
      return;
    }

    // CASO 3: Registro EXITOSO (dispositivo nuevo)
    if (result['success']) {
      showSuccessToast(
        context,
        'Dispositivo registrado exitosamente. Ya puedes iniciar sesión.',
      );

      if (!mounted) return;

      Navigator.of(context).pop();
    } else {
      // Error genérico
      showErrorToast(
        context,
        'Ocurrió un error. Inténtelo nuevamente.',
      );
    }
  } catch (e) {
    if (mounted) {
      showErrorToast(context, 'Error de conexión. Verifica tu internet.');
    }
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}
void _handleDeviceAlreadyActive(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      elevation: 12,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.accent.withOpacity(0.2),
                  AppColors.accentLight.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.check_circle_outline,
              color: AppColors.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: const Text(
              'Dispositivo ya registrado',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16.5, // Más pequeño para evitar desborde
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: const Text(
        'Este dispositivo ya está registrado y activo en el sistema.',
        style: TextStyle(
          fontSize: 15,
          color: Colors.black87,
          height: 1.5,
        ),
        textAlign: TextAlign.start,
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actionsPadding: const EdgeInsets.only(right: 12, bottom: 12, left: 12),
      actions: [
        // Botón Cancelar
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
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
        // Botón Ir al Login
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
              Navigator.of(context).pop();
              Navigator.of(context).pop();
              /*Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );*/
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Ir al Login',
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
  );
}
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF8F9FA),
              Color(0xFFE8EEF3),
              Color(0xFFD6E4F0),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header Premium
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF0F1419),
                      Color(0xFF1A2332),
                      Color(0xFF2D3E50),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Registrar Dispositivo',
                        style: AppFonts.h3.copyWith(
                          color: Colors.white,
                          fontSize: 22,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Contenido principal con fondo gris claro
              Expanded(
                // child: FadeTransition(
                  // opacity: _fadeAnimation,
                  // child: SlideTransition(
                    // position: _slideAnimation,
                    child: Container(
                      margin: const EdgeInsets.only(top: 20),
                      decoration: BoxDecoration(
                        color: AppColors
                            .surface, // GRIS CLARO EN LUGAR DE BLANCO
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(30),
                          topRight: Radius.circular(30),
                        ),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(28),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Icono y título
                              Center(
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(24),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            const Color(0xFF4A90E2)
                                                .withOpacity(0.2),
                                            const Color(0xFF6BA3E8)
                                                .withOpacity(0.1),
                                          ],
                                        ),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF4A90E2)
                                                .withOpacity(0.3),
                                            blurRadius: 20,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.phonelink_setup_rounded,
                                        size: 60,
                                        color: Color(0xFF4A90E2),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    Text(
                                      'Información del Dispositivo',
                                      style: AppFonts.h3,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Completa los datos para registrar tu dispositivo',
                                      style: AppFonts.body.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 36),

                              // ID Android
                              _buildReadOnlyField(
                                label: 'ID Android',
                                value: _androidId,
                                icon: Icons.fingerprint_rounded,
                                iconColor: const Color(0xFF4A90E2),
                              ),

                              const SizedBox(height: 16),

                              // Fabricante
                              _buildReadOnlyField(
                                label: 'Fabricante',
                                value: _fabricante,
                                icon: Icons.business_rounded,
                                iconColor: const Color(0xFF6BA3E8),
                              ),

                              const SizedBox(height: 16),

                              // Familia
                              _buildReadOnlyField(
                                label: 'Familia',
                                value: _familia,
                                icon: Icons.category_rounded,
                                iconColor: const Color(0xFF4A90E2),
                              ),

                              const SizedBox(height: 16),

                              // Modelo
                              _buildReadOnlyField(
                                label: 'Modelo',
                                value: _modelo,
                                icon: Icons.phone_android_rounded,
                                iconColor: const Color(0xFF6BA3E8),
                              ),

                              const SizedBox(height: 24),

                              // Descripción (editable)
                              Text(
                                'Descripción',
                                style: AppFonts.caption.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),

                              const SizedBox(height: 12),
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF4A90E2)
                                          .withOpacity(0.08),
                                      blurRadius: 15,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: TextFormField(
                                  controller: _descripcionController,
                                  maxLength: 100,
                                  style: AppFonts.body.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Ingresa una descripción',
                                    hintStyle: AppFonts.body
                                        .copyWith(color: AppColors.textMuted),
                                    prefixIcon: Container(
                                      margin: const EdgeInsets.all(12),
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            const Color(0xFF4A90E2)
                                                .withOpacity(0.2),
                                            const Color(0xFF6BA3E8)
                                                .withOpacity(0.1),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.description_rounded,
                                        color: Color(0xFF4A90E2),
                                        size: 20,
                                      ),
                                    ),
                                    filled: true,
                                    fillColor:
                                        Colors.white, // Blanco sobre gris claro
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(
                                        color: Colors.grey.shade200,
                                        width: 1,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF4A90E2),
                                        width: 2,
                                      ),
                                    ),
                                    errorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: const BorderSide(
                                        color: AppColors.error,
                                        width: 1,
                                      ),
                                    ),
                                    focusedErrorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: const BorderSide(
                                        color: AppColors.error,
                                        width: 2,
                                      ),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 18,
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Ingrese una descripción';
                                    }
                                    return null;
                                  },
                                ),
                              ),

                              const SizedBox(height: 32),

                              // Botón de registro premium
                              Container(
                                width: double.infinity,
                                height: 60,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: _isLoading
                                      ? null
                                      : const LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Color(0xFF1E3A5F),
                                            Color(0xFF2D4A6F),
                                            Color(0xFF4A90E2),
                                          ],
                                        ),
                                  boxShadow: _isLoading
                                      ? null
                                      : [
                                          BoxShadow(
                                            color: const Color(0xFF4A90E2)
                                                .withOpacity(0.4),
                                            blurRadius: 20,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                ),
                                child: ElevatedButton(
                                  onPressed:
                                      _isLoading ? null : _handleRegister,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          height: 28,
                                          width: 28,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 3,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Icon(
                                                Icons.check_circle_rounded,
                                                size: 26),
                                            const SizedBox(width: 12),
                                            Text(
                                              'REGISTRAR',
                                              style: AppFonts.button
                                                  .copyWith(fontSize: 18),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ],
                          ),
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

  Widget _buildReadOnlyField({
    required String label,
    required String value,
    required IconData icon,
    required Color iconColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppFonts.caption.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white, // Blanco sobre gris claro
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  value,
                  style: AppFonts.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
