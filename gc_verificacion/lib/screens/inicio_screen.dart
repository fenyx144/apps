import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../utils/constants.dart';
import '../widgets/screen_status_bar.dart';
import 'login_screen.dart';
import 'verificacion_screen.dart';

class InicioScreen extends StatelessWidget {
  const InicioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenStatusBar(
      color: AppColors.primaryDark,
      iconBrightness: Brightness.light,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primaryDark,
                AppColors.primary,
                AppColors.primaryVibrant,
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const Spacer(),
                  Container(
                    width: 110,
                    height: 110,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                    child: Image.asset(
                      'assets/images/logo_grs.png',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.face_rounded,
                          size: 52,
                          color: Colors.white,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    AppConstants.appTitle,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      height: 1.25,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  _BotonInicio(
                    icon: Icons.face_rounded,
                    titulo: 'ESCANEO',
                    subtitulo: 'Verificación facial de ingreso',
                    destacado: true,
                    onTap: () => Get.to(
                      () => const VerificacionScreen(),
                      routeName: '/verificacion',
                    ),
                  ),
                  const SizedBox(height: 16),
                  _BotonInicio(
                    icon: Icons.lock_rounded,
                    titulo: 'LOGIN',
                    subtitulo: 'Acceso del supervisor',
                    destacado: false,
                    onTap: () => Get.to(
                      () => const LoginScreen(),
                      routeName: '/login',
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'v${AppConstants.appVersion}',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BotonInicio extends StatelessWidget {
  const _BotonInicio({
    required this.icon,
    required this.titulo,
    required this.subtitulo,
    required this.destacado,
    required this.onTap,
  });

  final IconData icon;
  final String titulo;
  final String subtitulo;
  final bool destacado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: 20,
            vertical: destacado ? 22 : 18,
          ),
          decoration: BoxDecoration(
            color: destacado
                ? Colors.white
                : AppColors.background.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: destacado
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.25),
              width: 1.5,
            ),
            boxShadow: destacado ? AppColors.strongShadow : null,
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: destacado
                      ? AppColors.primary
                      : Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 30,
                  color:
                      destacado ? Colors.white : AppColors.primaryLight,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        color:
                            destacado ? AppColors.background : Colors.white,
                        fontSize: destacado ? 21 : 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitulo,
                      style: TextStyle(
                        color: destacado
                            ? AppColors.textMuted
                            : Colors.white.withValues(alpha: 0.65),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: destacado
                      ? AppColors.primary.withValues(alpha: 0.14)
                      : Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color:
                      destacado ? AppColors.primaryDark : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
