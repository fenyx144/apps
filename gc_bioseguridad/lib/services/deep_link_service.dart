import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/login_screen.dart';
import '../screens/register_cerco_screen.dart';
import '../screens/register_fomites_screen.dart';
import '../utils/bio_navigation.dart';
import '../utils/constants.dart';
import 'catalog_service.dart';
import 'storage_service.dart';

/// Enlace externo `gcbioseguridad://abrir?modulo=fomites&granja=642&dni=...`
/// enviado por otra app (p. ej. rondas). Abre el registro con los datos
/// precargados y, si hace falta, inicia sesión con el catálogo `usuarios`.
abstract final class DeepLinkService {
  static Map<String, String>? _pendiente;
  static bool _splashListo = false;
  static String _ultimo = '';
  static DateTime _ultimoEn = DateTime(2000);

  static Future<void> init() async {
    final links = AppLinks();
    links.uriLinkStream.listen(_recibir);
    try {
      _recibir(await links.getInitialLink()
          .timeout(const Duration(seconds: 2)));
    } catch (_) {}
  }

  static void _recibir(Uri? uri) {
    if (uri == null || uri.scheme != 'gcbioseguridad') return;
    // getInitialLink y el stream pueden entregar el mismo enlace al arrancar.
    final s = uri.toString();
    if (s == _ultimo && DateTime.now().difference(_ultimoEn).inSeconds < 5) {
      return;
    }
    _ultimo = s;
    _ultimoEn = DateTime.now();
    _pendiente = Map<String, String>.from(uri.queryParameters);
    if (_splashListo) unawaited(_procesar());
  }

  /// Lo llama el splash al terminar. `true` si el enlace tomó la navegación.
  static Future<bool> alTerminarSplash() async {
    _splashListo = true;
    if (_pendiente == null) return false;
    await _procesar();
    return true;
  }

  /// Con sesión iniciada: abre el registro pendiente, si lo hay.
  static bool abrirPendiente() {
    final p = _pendiente;
    if (p == null) return false;
    _pendiente = null;
    final mod =
        (p['modulo'] ?? '').toLowerCase().replaceAll(RegExp('[ _-]'), '');
    if (mod == 'fomites') {
      Get.offAll(() => RegisterFomitesScreen(enlace: p),
          routeName: BioNavigation.rutas[BioSecciones.fomites]!);
    } else if (mod.startsWith('cerco')) {
      Get.offAll(() => RegisterCercoScreen(enlace: p),
          routeName: BioNavigation.rutas[BioSecciones.cerco]!);
    } else {
      return false;
    }
    return true;
  }

  static Future<void> _procesar() async {
    final ctx = Get.context;
    final p = _pendiente;
    if (ctx == null || p == null) return;
    final storage = Provider.of<StorageService>(ctx, listen: false);
    final catalog = Provider.of<CatalogService>(ctx, listen: false);
    var logged = await storage.isLoggedIn();

    String n(Object? v) => (v ?? '').toString().trim().toLowerCase();
    final cod = n(p['usuario']);
    final ph = n(p['ph']);
    final dni = n(p['dni']);
    final usuarios = catalog.catalogos['usuarios'];
    final lista =
        usuarios is List ? usuarios.whereType<Map>() : const Iterable<Map>.empty();
    Map? u;
    if (cod.isNotEmpty) {
      // 1) usuario + password_hex  2) usuario solo (código en el catálogo)
      u = lista
          .where((x) =>
              n(x['codigo']) == cod && (ph.isEmpty || n(x['password_hex']) == ph))
          .firstOrNull;
    } else if (dni.isNotEmpty) {
      // 3) respaldo: el DNI está en `libtri` del usuario
      u = lista.where((x) => n(x['libtri']) == dni).firstOrNull;
    }
    final actual = n(storage.getUserCodeSync());
    if (u != null) {
      final codigo = n(u['codigo']);
      // Mismo usuario con sesión: se conserva. Otro: se reemplaza.
      if (!logged || codigo != actual) {
        if (logged) await storage.clearSession();
        await storage.saveLoginSession(
          userCode: codigo,
          userName: (u['nombre'] ?? codigo).toString(),
          deviceId: await _deviceId(),
        );
        logged = true;
      }
    } else if (cod.isNotEmpty || dni.isNotEmpty) {
      // Usuario del enlace no está en el catálogo: login manual, sin cerrar
      // la sesión actual; al entrar sigue al registro.
      logged = false;
    }
    if (logged) {
      if (!abrirPendiente()) BioNavigation.irTrasAutenticacion(sesionActiva: true);
      return;
    }
    // Sin usuario: login normal; al entrar sigue al registro (abrirPendiente).
    Get.offAll(() => const LoginScreen(),
        routeName: BioNavigation.rutas['login']!);
  }

  /// `uuid` del enlace si tiene formato UUID (se usa como id del registro).
  static String? uuidDe(Map<String, String>? enlace) {
    final v = (enlace?['uuid'] ?? '').trim().toLowerCase();
    return RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
            .hasMatch(v)
        ? v
        : null;
  }

  /// Esquema con el que se responde a la app que llamó (rondas/rutero).
  static const String esquemaRetorno = 'grsrutero';

  /// Vuelve a la app que abrió el enlace con el resultado
  /// (`grsrutero://bioseguridad?estado=ok&modulo=...&uuid=...`) y deja esta
  /// app en el dashboard. `false` si no hay app que reciba el enlace.
  static Future<bool> volverAlOrigen(
    Map<String, String> enlace, {
    required String modulo,
    String estado = 'ok',
    String uuid = '',
    bool enviado = false,
    String fecha = '',
  }) async {
    String d2(int v) => v.toString().padLeft(2, '0');
    final t = DateTime.now();
    final uri = Uri(
      scheme: esquemaRetorno,
      host: 'bioseguridad',
      queryParameters: {
        'estado': estado,
        'modulo': modulo,
        'uuid': uuid.isNotEmpty ? uuid : (uuidDe(enlace) ?? ''),
        'ref': enlace['ref'] ?? '',
        'enviado': enviado ? '1' : '0',
        'fecha': fecha.isNotEmpty ? fecha : '${t.year}-${d2(t.month)}-${d2(t.day)}',
        'hora': '${d2(t.hour)}:${d2(t.minute)}',
      },
    );
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (ok) BioNavigation.irTrasAutenticacion(sesionActiva: true);
    return ok;
  }

  /// Pantalla abierta por enlace: al retroceder sin guardar responde
  /// `estado=cancelado` y vuelve al dashboard.
  static Widget conRetorno(
    Map<String, String>? enlace, {
    required String modulo,
    required Widget child,
  }) {
    if (enlace == null) return child;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok =
            await volverAlOrigen(enlace, modulo: modulo, estado: 'cancelado');
        if (!ok) BioNavigation.irTrasAutenticacion(sesionActiva: true);
      },
      child: child,
    );
  }

  static Future<String> _deviceId() async {
    if (!Platform.isAndroid) return 'unknown';
    return (await DeviceInfoPlugin().androidInfo).id;
  }
}
