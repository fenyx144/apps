import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';
import '../utils/theme_extensions.dart';
import '../utils/toast_helper.dart';

class RegisterDeviceScreen extends StatefulWidget {
  const RegisterDeviceScreen({super.key});

  @override
  State<RegisterDeviceScreen> createState() => _RegisterDeviceScreenState();
}

class _RegisterDeviceScreenState extends State<RegisterDeviceScreen> {
  final _descripcionController = TextEditingController();
  final _apiService = ApiService();
  bool _isLoading = false;
  bool _hasAttemptedValidation = false;
  String _androidId = 'Cargando...';
  String _fabricante = 'Cargando...';
  String _familia = 'Cargando...';
  String _modelo = 'Cargando...';

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
        final info = await deviceInfo.androidInfo;
        setState(() {
          _androidId = info.id;
          _fabricante = info.manufacturer;
          _familia = info.brand;
          _modelo = info.model;
        });
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        setState(() {
          _androidId = info.identifierForVendor ?? 'UNKNOWN_IOS';
          _fabricante = 'Apple';
          _familia = 'iPhone';
          _modelo = info.model;
        });
      }
    } catch (_) {
      setState(() {
        _androidId = 'ERROR';
        _fabricante = 'Desconocido';
        _familia = 'Desconocido';
        _modelo = 'Desconocido';
      });
    }
  }

  Future<void> _handleRegister() async {
    setState(() => _hasAttemptedValidation = true);
    if (_descripcionController.text.trim().isEmpty) return;

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

      if (result['errorCode'] == 'DEVICE_ALREADY_ACTIVE') {
        showInfoToast(context, 'Dispositivo ya registrado.');
        FocusScope.of(context).unfocus();
        Navigator.pop(context);
        return;
      }

      if (result['success'] == true) {
        showSuccessToast(context, 'Dispositivo registrado correctamente.');
        FocusScope.of(context).unfocus();
        Navigator.pop(context);
      } else {
        showErrorToast(context, result['message']?.toString() ?? 'Error al registrar dispositivo');
      }
    } catch (e) {
      showErrorToast(context, 'Error al registrar dispositivo.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildInfoField(BuildContext context, String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.secondaryTextColor,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.primaryTextColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
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
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: context.primaryTextColor),
                      onPressed: () {
                        FocusScope.of(context).unfocus();
                        Navigator.pop(context);
                      },
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Registrar Dispositivo',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: context.primaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.phonelink_setup_rounded,
                          size: 50,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildInfoField(context, 'ID del Dispositivo', _androidId, Icons.fingerprint),
                      const SizedBox(height: 14),
                      _buildInfoField(context, 'Fabricante', _fabricante, Icons.business),
                      const SizedBox(height: 14),
                      _buildInfoField(context, 'Familia', _familia, Icons.category),
                      const SizedBox(height: 14),
                      _buildInfoField(context, 'Modelo', _modelo, Icons.phone_android),
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Descripción',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: context.secondaryTextColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _descripcionController,
                        maxLength: 100,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: context.primaryTextColor,
                        ),
                        decoration: AppInputStyles.decoration(
                          context,
                          r: 12,
                          hintText: 'Descripción del dispositivo',
                          hintStyle: TextStyle(color: context.mutedTextColor),
                          prefixIcon: const Icon(Icons.description, color: AppColors.primary),
                          counterText: '',
                        ),
                      ),
                      if (_hasAttemptedValidation && _descripcionController.text.trim().isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(left: 12, top: 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Por favor, ingresa una descripción',
                              style: TextStyle(color: AppColors.error, fontSize: 12),
                            ),
                          ),
                        ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _handleRegister,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.check_circle),
                          label: const Text(
                            'REGISTRAR DISPOSITIVO',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
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
