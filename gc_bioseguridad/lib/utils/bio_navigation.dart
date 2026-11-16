import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../screens/dashboard_screen.dart';
import '../screens/login_screen.dart';
import '../screens/register_cerco_screen.dart';
import '../screens/register_control_ingreso_screen.dart';
import '../screens/register_salida_screen.dart';
import '../screens/register_fomites_screen.dart';
import '../screens/bio_empresa/bio_almacen_home_screen.dart';
import '../screens/bio_empresa/bio_consumo_screen.dart';
import '../screens/bio_empresa/bio_relevo_screen.dart';
import '../screens/register_garita_screen.dart';
import '../screens/register_articulos_screen.dart';
import '../services/deep_link_service.dart';
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
    BioSecciones.ingreso: '/bio/ingreso',
    BioSecciones.salida: '/bio/salida',
    BioSecciones.cerco: '/bio/cerco',
    BioSecciones.fomites: '/bio/fomites',
    BioSecciones.articulos: '/bio/articulos',
    BioSecciones.anomalias: '/bio/anomalias',
    'dashboard': '/bio/dashboard',
    'login': '/bio/login',
    'reportes': '/bio/reportes',
    'miGranja': '/bio/mi-granja',
    BioEmpresaSecciones.almacen: '/bio/empresa/almacen',
    BioEmpresaSecciones.consumo: '/bio/empresa/consumo',
    BioEmpresaSecciones.relevo: '/bio/empresa/relevo',
  };

  static Widget pantallaEmpresa(String seccion) {
    switch (seccion) {
      case BioEmpresaSecciones.almacen:
        return const BioAlmacenHomeScreen();
      case BioEmpresaSecciones.consumo:
        return const BioConsumoScreen();
      case BioEmpresaSecciones.relevo:
        return const BioRelevoScreen();
      default:
        return const BioAlmacenHomeScreen();
    }
  }

  /// Tras splash o login: deja una sola ruta en el stack (evita navigator vacío).
  static void irTrasAutenticacion({required bool sesionActiva}) {
    Get.offAll(
      () => sesionActiva ? const DashboardScreen() : const LoginScreen(),
      routeName: sesionActiva ? rutas['dashboard']! : rutas['login']!,
    );
  }

  static void irAlDashboardTrasLogin() {
    // Si llegó un enlace de otra app, sigue a ese registro.
    if (DeepLinkService.abrirPendiente()) return;
    Get.offAll(
      () => const DashboardScreen(),
      routeName: rutas['dashboard']!,
    );
  }

  /// Ruta de una sección. Anomalías existe en los tres tipos de bioseguridad, así
  /// que el tipo se agrega al final para que cada grupo tenga su propia ruta.
  static String rutaDe(String seccion, {String? tipo}) {
    final base = rutas[seccion] ?? rutas['dashboard']!;
    if (tipo == null || tipo == BioTipos.fisica) return base;
    return '$base/$tipo';
  }

  /// Pantalla que corresponde a una sección, con el tipo de bioseguridad ya
  /// seleccionado en Anomalías (física, química o biológica).
  static Widget pantallaDe(String seccion, {String? tipo}) {
    switch (seccion) {
      case BioSecciones.ingreso:
        return const RegisterControlIngresoScreen();
      case BioSecciones.salida:
        return const RegisterSalidaScreen();
      case BioSecciones.cerco:
        return const RegisterCercoScreen();
      case BioSecciones.fomites:
        return const RegisterFomitesScreen();
      case BioSecciones.articulos:
        return const RegisterArticulosScreen();
      case BioSecciones.anomalias:
        return RegisterGaritaScreen(
          bioseguridadInicial: BioTipos.descripcion[tipo ?? BioTipos.fisica] ??
              BioTipos.descripcion[BioTipos.fisica]!,
          tipoInicial: tipo ?? BioTipos.fisica,
        );
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
