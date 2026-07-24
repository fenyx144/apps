import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';
import '../utils/theme_colors.dart';
import '../utils/toast_helper.dart';
import '../widgets/screen_status_bar.dart';

class RegisterDeviceScreen extends StatefulWidget {
  const RegisterDeviceScreen({super.key});

  @override
  State<RegisterDeviceScreen> createState() => _RegisterDeviceScreenState();
}

class _RegisterDeviceScreenState extends State<RegisterDeviceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descController = TextEditingController();
  final _api = ApiService();
  bool _loading = false;
  bool _hasAttemptedValidation = false;
  String _deviceId = 'Cargando...';
  String _fabricante = 'Cargando...';
  String _familia = 'Cargando...';
  String _modelo = 'Cargando...';

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
    _descController.addListener(() {
      if (_hasAttemptedValidation && _descController.text.trim().isNotEmpty) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Future<void> _loadDeviceInfo() async {
    final plugin = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final a = await plugin.androidInfo;
        setState(() {
          _deviceId = a.id;
          _fabricante = a.manufacturer;
          _familia = a.brand;
          _modelo = a.model;
        });
      }
    } catch (_) {
      setState(() {
        _deviceId = 'ERROR';
        _fabricante = 'Desconocido';
        _familia = 'Desconocido';
        _modelo = 'Desconocido';
      });
    }
  }

  Future<void> _register() async {
    setState(() => _hasAttemptedValidation = true);
    if (_descController.text.trim().isEmpty) {
      return;
    }

    setState(() => _loading = true);
    try {
      final result = await _api.registerDevice(
        androidId: _deviceId,
        fabricante: _fabricante,
        familia: _familia,
        modelo: _modelo,
        descripcion: _descController.text.trim(),
      );
      if (result['success'] == true) {
        showSuccessToast(
          context,
          'Dispositivo registrado exitosamente. Ya puedes iniciar sesión.',
        );
        Get.back();
      } else {
        showErrorToast(
          context,
          result['message']?.toString() ?? 'No se pudo registrar',
        );
      }
    } catch (e) {
      showErrorToast(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenStatusBar(
      color: context.scaffoldMuted,
      child: Scaffold(
      backgroundColor: context.scaffoldMuted,
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back,
                      color: context.textThemePrimary,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Registrar Dispositivo',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: context.textThemePrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(
                              alpha: context.isAppDark ? 0.2 : 0.1,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: context.borderSubtle),
                          ),
                          child: const Icon(
                            Icons.phonelink_setup_rounded,
                            size: 50,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildInfoField(
                        'ID del Dispositivo',
                        _deviceId,
                        Icons.fingerprint,
                      ),
                      const SizedBox(height: 16),
                      _buildInfoField(
                        'Fabricante',
                        _fabricante,
                        Icons.business,
                      ),
                      const SizedBox(height: 16),
                      _buildInfoField('Familia', _familia, Icons.category),
                      const SizedBox(height: 16),
                      _buildInfoField(
                        'Modelo',
                        _modelo,
                        Icons.phone_android,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Descripción',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.textThemeSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.primary.withValues(
                              alpha: context.isAppDark ? 0.5 : 0.3,
                            ),
                          ),
                        ),
                        child: TextFormField(
                          controller: _descController,
                          maxLength: 100,
                          textCapitalization: TextCapitalization.characters,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: context.textThemePrimary,
                          ),
                          decoration: InputDecoration(
                            hintStyle: TextStyle(color: context.textThemeMuted),
                            prefixIcon: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Icon(
                                Icons.description,
                                color: AppColors.primary,
                              ),
                            ),
                            filled: true,
                            fillColor: context.surfaceElevated,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            counterText: '',
                            errorText: null,
                            errorStyle: const TextStyle(height: 0),
                          ),
                          validator: (_) => null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buildDescripcionError(),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _register,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                            shadowColor: AppColors.primary.withOpacity(0.4),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    color: Colors.white,
                                  ),
                                )
                              : const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'REGISTRAR DISPOSITIVO',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
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

  Widget _buildDescripcionError() {
    if (!_hasAttemptedValidation || _descController.text.trim().isNotEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 4),
      child: Text(
        'Por favor, ingresa una descripción',
        style: TextStyle(
          color: AppColors.error,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildInfoField(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: context.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderSubtle),
        boxShadow: context.cardShadow(blur: 6, dy: 2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(
                alpha: context.isAppDark ? 0.2 : 0.1,
              ),
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
                    color: context.textThemeSecondary,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.textThemePrimary,
                    overflow: TextOverflow.ellipsis,
                  ),
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
