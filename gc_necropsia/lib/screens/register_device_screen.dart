import 'package:flutter/material.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';
import '../utils/toast_helper.dart';

class RegisterDeviceScreen extends StatefulWidget {
  const RegisterDeviceScreen({super.key});

  @override
  State<RegisterDeviceScreen> createState() => _RegisterDeviceScreenState();
}

class _RegisterDeviceScreenState extends State<RegisterDeviceScreen> {
  final _formKey = GlobalKey<FormState>();
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

    // Agregar listener para ocultar error cuando el usuario escriba
    _descripcionController.addListener(() {
      if (_hasAttemptedValidation && _descripcionController.text.trim().isNotEmpty) {
        setState(() {}); // Actualizar UI para ocultar error
      }
    });
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
        _androidId = 'ERROR';
        _fabricante = 'Desconocido';
        _familia = 'Desconocido';
        _modelo = 'Desconocido';
      });
    }
  }

  Future<void> _handleRegister() async {
    // Marcar que se intentó validar
    setState(() {
      _hasAttemptedValidation = true;
    });

    // Validar campo manualmente antes de mostrar el diálogo
    if (_descripcionController.text.trim().isEmpty) {
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

      final errorCode = result['errorCode'] as String?;

      if (errorCode == 'DEVICE_ALREADY_ACTIVE') {
        _handleDeviceAlreadyActive(context);
        return;
      }

      if (errorCode == 'DEVICE_INACTIVE') {
        showInfoToast(context, 'Este dispositivo está registrado pero ha sido desactivado.');
        return;
      }

      if (result['success']) {
        showSuccessToast(context, 'Dispositivo registrado exitosamente. Ya puedes iniciar sesión.');
        if (!mounted) return;
        Navigator.of(context).pop(); // Vuelve al login
      } else {
        showErrorToast(context, 'Ocurrió un error. Inténtelo nuevamente.');
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.check_circle_outline,
                color: AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Dispositivo ya registrado',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ],
        ),
        content: const Text(
          'Este dispositivo ya está registrado y activo en el sistema.',
          style: TextStyle(fontSize: 15, color: Colors.black87, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Vuelve al login
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Ir al Login'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: true, // EVITA SOLAPAMIENTO CON BARRA DE NAVEGACIÓN INFERIOR
        child: Column(
          children: [
            // HEADER SIMPLE (como en login, pero sin curva)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Registrar Dispositivo',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // CONTENIDO PRINCIPAL (COMPACTO Y COHERENTE CON LOGIN)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icono central
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.phonelink_setup_rounded,
                            size: 50,
                            color: AppColors.primary,
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Campos de información (compactos)
                      _buildInfoField('ID del Dispositivo', _androidId, Icons.fingerprint),
                      const SizedBox(height: 16),
                      _buildInfoField('Fabricante', _fabricante, Icons.business),
                      const SizedBox(height: 16),
                      _buildInfoField('Familia', _familia, Icons.category),
                      const SizedBox(height: 16),
                      _buildInfoField('Modelo', _modelo, Icons.phone_android),

                      const SizedBox(height: 24),

                      Text(
                        'Descripción',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                        ),
                        child: TextFormField(
                          controller: _descripcionController,
                          maxLength: 100,
                          textCapitalization: TextCapitalization.characters,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                          decoration: InputDecoration(
                            hintStyle: TextStyle(color: AppColors.textMuted),
                            prefixIcon: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Icon(Icons.description, color: AppColors.primary),
                            ),
                            filled: true,
                            fillColor: AppColors.cardBackground,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            counterText: '',
                            errorText: null, // No mostrar error dentro del input
                            errorStyle: const TextStyle(height: 0), // Ocultar espacio del error
                          ),
                          validator: (value) {
                            // Siempre retornar null para que no se muestre error dentro del input
                            // La validación se maneja manualmente en _handleRegister
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buildDescripcionError(),

                      const SizedBox(height: 32),

                      // BOTÓN COMPACTO Y ESTILO LOGIN
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleRegister,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 4,
                            shadowColor: AppColors.primary.withOpacity(0.4),
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
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle, size: 20),
                                    SizedBox(width: 8),
                                    Text('REGISTRAR DISPOSITIVO', style: TextStyle(fontWeight: FontWeight.w700)),
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
    );
  }

  Widget _buildDescripcionError() {
    // Solo mostrar error si se intentó validar y el campo está vacío
    if (!_hasAttemptedValidation || _descripcionController.text.trim().isNotEmpty) {
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
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
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
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
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
