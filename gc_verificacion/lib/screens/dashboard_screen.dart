import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/theme_colors.dart';
import '../widgets/app_drawer.dart';
import '../widgets/screen_status_bar.dart';
import '../widgets/section_app_bar.dart';
import 'eventos_screen.dart';
import 'personal_screen.dart';
import 'verificacion_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final nombre = storage.getUserName() ?? 'Usuario';
    final eventosHoy = storage.eventosDelDia(DateTime.now()).length;
    final pendientes = storage.eventosPendientesCount();
    final nomina = storage.getNominaTotal();

    return ScreenStatusBar(
      color: AppColors.primary,
      iconBrightness: Brightness.light,
      child: Scaffold(
        backgroundColor: context.scaffoldMuted,
        drawer: const AppDrawer(),
        appBar: const SectionAppBar(
          title: 'Panel',
          sectionIcon: Icons.dashboard_rounded,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppColors.headerGradient,
                borderRadius: BorderRadius.circular(AppColors.radiusXl),
                boxShadow: AppColors.mediumShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Hola,',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    nombre,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Sesión de supervisor activa',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _Dato(valor: '$eventosHoy', etiqueta: 'Eventos hoy'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Dato(valor: '$pendientes', etiqueta: 'Pendientes'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Dato(valor: '$nomina', etiqueta: 'En nómina'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _Accion(
              icon: Icons.face_rounded,
              titulo: AppStrings.menuVerificacion,
              subtitulo: 'Ir al escaneo facial',
              onTap: () => Get.to(
                () => const VerificacionScreen(),
                routeName: '/verificacion',
              ),
            ),
            _Accion(
              icon: Icons.history_rounded,
              titulo: AppStrings.menuEventos,
              subtitulo: 'Registros del día',
              onTap: () =>
                  Get.to(() => const EventosScreen(), routeName: '/eventos'),
            ),
            _Accion(
              icon: Icons.people_rounded,
              titulo: AppStrings.menuPersonal,
              subtitulo: 'Personal enrolado',
              onTap: () =>
                  Get.to(() => const PersonalScreen(), routeName: '/personal'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.valor, required this.etiqueta});

  final String valor;
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: context.surfaceCard,
        borderRadius: BorderRadius.circular(AppColors.radiusLg),
        border: Border.all(color: context.borderSubtle, width: 1.5),
      ),
      child: Column(
        children: [
          Text(
            valor,
            style: TextStyle(
              color: context.textThemePrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            etiqueta,
            style: TextStyle(
              color: context.textThemeMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Accion extends StatelessWidget {
  const _Accion({
    required this.icon,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
  });

  final IconData icon;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppColors.radiusLg),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: context.surfaceCard,
              borderRadius: BorderRadius.circular(AppColors.radiusLg),
              border: Border.all(color: context.borderSubtle, width: 1.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: TextStyle(
                          color: context.textThemePrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitulo,
                        style: TextStyle(
                          color: context.textThemeMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 15,
                  color: context.textThemeMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
