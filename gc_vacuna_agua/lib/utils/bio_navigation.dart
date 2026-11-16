import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../screens/dashboard_screen.dart';
import '../screens/register_decloracion_screen.dart';
import '../screens/register_vacunacion_screen.dart';
import 'constants.dart';

/// Navegación entre las secciones de registro.
/// Vive aquí y no en el drawer porque el propio drawer, el resumen y los
/// reportes navegan a las mismas pantallas: así el nombre de ruta y el widget de
/// cada sección se definen una sola vez.
abstract final class BioNavigation {
  /// Nombres de ruta explícitos de cada sección.
  /// Ojo con GetX: `off`/`to` deduplican por nombre de ruta y ese nombre sale
  /// del `runtimeType` del closure (`_cleanRouteName` quita el prefijo
  /// "() => "). Al pasar una variable `Widget` los casos comparten el nombre
  /// `/Widget` y GetX termina devolviendo `null` sin navegar.
  static const Map<String, String> rutas = {
    BioSecciones.decloracion: '/vac/decloracion',
    BioSecciones.vacunacion: '/vac/vacunacion',
    'dashboard': '/vac/dashboard',
    'reportes': '/vac/reportes',
    'miGranja': '/vac/mi-granja',
  };

  /// Ruta de una sección. [tipo] se mantiene en la firma por compatibilidad con
  /// el drawer, pero ya no hay varios grupos de bioseguridad.
  static String rutaDe(String seccion, {String? tipo}) =>
      rutas[seccion] ?? rutas['dashboard']!;

  /// Pantalla que corresponde a una sección.
  static Widget pantallaDe(String seccion, {String? tipo}) {
    switch (seccion) {
      case BioSecciones.decloracion:
        return const RegisterDecloracionScreen();
      case BioSecciones.vacunacion:
        return const RegisterVacunacionScreen();
      default:
        return DashboardScreen(key: UniqueKey());
    }
  }

  /// Navega a una sección reemplazando la pantalla actual.
  /// Se usa `Get.off` con `routeName` explícito y `preventDuplicates: false`
  /// para poder volver a la misma sección (que la deja como estaba).
  static void ir(String seccion, {String? tipo}) {
    final screen = pantallaDe(seccion, tipo: tipo);
    Get.off(
      () => screen,
      routeName: rutaDe(seccion, tipo: tipo),
      preventDuplicates: false,
      transition: Transition.fadeIn,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  /// Navega en el siguiente frame. Necesario al salir del drawer, para no
  /// disponer el Scaffold mientras la animación de cierre sigue corriendo.
  static void irEnSiguienteFrame(String seccion, {String? tipo}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ir(seccion, tipo: tipo);
    });
  }
}
