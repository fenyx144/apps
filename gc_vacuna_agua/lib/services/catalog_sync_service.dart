import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'app_version_service.dart';
import 'catalog_service.dart';
import 'proveedor_vacuna_catalog_service.dart';
import 'storage_service.dart';
import '../utils/galpones_resolver.dart';

class CatalogSyncResult {
  const CatalogSyncResult({
    required this.hadInternet,
    required this.cencosOk,
    required this.proyeccionOk,
    this.cencosCount = 0,
    this.catalogosOk = false,
    this.usuariosCount = 0,
    this.vacunaCatalogosOk = false,
    this.errorMessage,
    this.fecIngWarning,
  });

  final bool hadInternet;
  final bool cencosOk;
  final bool proyeccionOk;
  final int cencosCount;
  final bool catalogosOk;
  final int usuariosCount;

  /// Catálogos propios de Vacuna al Agua (equipo de vacunación y turnos).
  final bool vacunaCatalogosOk;
  final String? errorMessage;
  final String? fecIngWarning;
}

class CatalogSyncService {
  CatalogSyncService({ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;

  Future<bool> hasInternet() async {
    try {
      final r = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 4));
      return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  bool hasUsableLocalCatalogs(StorageService storage) {
    return storage.hasCencosGalponesLocal() || storage.getProyeccion() != null;
  }

  /// Descarga manual desde el menú (Descargar). No invocar en login ni pantallas.
  Future<CatalogSyncResult> syncAll({
    required StorageService storage,
    required CatalogService catalog,
    bool includeUsuariosConempre = true,
  }) async {
    await catalog.loadFromPrefs();

    if (!await hasInternet()) {
      return CatalogSyncResult(
        hadInternet: false,
        cencosOk: false,
        proyeccionOk: false,
        errorMessage: 'Sin conexión a internet',
      );
    }

    var cencosOk = false;
    var proyeccionOk = false;
    var catalogosOk = false;
    var cencosCount = 0;
    var usuariosCount = 0;
    String? fecIngWarning;
    final errors = <String>[];

    // 1. Descargar CENCOS/galpones
    try {
      final gal = await _api.downloadCencosGalpones();
      if (gal['success'] == true) {
        if (gal['indices'] is GalponesCatalogIndices) {
          final indices = gal['indices'] as GalponesCatalogIndices;
          await storage.saveCencosGalponesIndexed(indices);
          cencosCount = indices.cencos.length;
          cencosOk = indices.cencos.isNotEmpty;
        } else if (gal['data'] is Map) {
          await storage.saveCencosGalpones(
            Map<String, dynamic>.from(gal['data'] as Map),
          );
          cencosCount = storage.getCencosListaLocal().length;
          cencosOk = storage.hasCencosGalponesLocal();
        }
      } else {
        errors.add(gal['message']?.toString() ?? 'Error CENCOS/galpones');
      }
    } catch (e) {
      errors.add('CENCOS/galpones: Error de conexión');
    }
    if (cencosOk) {
      await storage.setLastDownloadDate();
      final stats = storage.statsFecIngMin();
      debugPrint(
        'CatalogSync: galpones con fec_ing_min=${stats.conFecIng}/${stats.total}',
      );
      if (stats.total > 0 && stats.conFecIng == 0) {
        fecIngWarning =
            'Catálogo sin fechas de ingreso; edad offline no disponible.';
      }
    }

    // 2. Descargar proyección (siempre desde hoy: ventana historico_anual ccos)
    try {
      final fechaCatalogo = DateTime.now().toIso8601String().substring(0, 10);
      final proy = await _api.downloadProyeccion(fecha: fechaCatalogo);
      if (proy['success'] == true && proy['data'] is Map) {
        await storage.saveProyeccion(
          Map<String, dynamic>.from(proy['data'] as Map),
        );
        proyeccionOk = true;
      } else {
        errors.add(proy['message']?.toString() ?? 'Error proyección');
      }
    } catch (e) {
      errors.add('Proyección: Error de conexión');
    }
    if (proyeccionOk) {
      await storage.setLastDownloadDate();
    }

    // 3. Catálogo g_app (versión mínima — cache offline)
    try {
      await syncAppInfo(storage: storage);
    } catch (e) {
      errors.add('Versión app: Error de conexión');
    }

    // 4. usuarios/conempre
    if (includeUsuariosConempre) {
      try {
        final ok = await catalog.downloadCatalogos(
          tablas: ['usuarios', 'conempre'],
        );
        if (ok) {
          catalogosOk = true;
          final usuarios = catalog.catalogos['usuarios'];
          if (usuarios is List) usuariosCount = usuarios.length;
          await storage.setLastDownloadDate();
        } else {
          errors.add('Usuarios/conempre: no se pudieron descargar');
        }
      } catch (e) {
        errors.add('Usuarios/conempre: Error de conexión');
      }
    }

    // 5. Catálogos propios de Vacuna al Agua (equipo y turnos)
    var vacunaCatalogosOk = false;
    try {
      vacunaCatalogosOk = await catalog.downloadCatalogosVacuna();
      final provOk =
          await ProveedorVacunaCatalogService(storage).descargar();
      if (!provOk) {
        errors.add('Laboratorios (proveedores Vacuna al Agua): no se descargaron');
      }
      if (vacunaCatalogosOk || provOk) {
        await storage.setLastDownloadDate();
      }
      if (!vacunaCatalogosOk) {
        errors.add('Catálogos de Vacuna al Agua: no se pudieron descargar');
      }
    } catch (e) {
      errors.add('Catálogos de Vacuna al Agua: Error de conexión');
    }

    // 6. Planificación de visitas: se retiró en Vacuna al Agua.

    return CatalogSyncResult(
      hadInternet: true,
      cencosOk: cencosOk,
      proyeccionOk: proyeccionOk,
      cencosCount: cencosCount,
      catalogosOk: catalogosOk,
      usuariosCount: usuariosCount,
      vacunaCatalogosOk: vacunaCatalogosOk,
      errorMessage: errors.isEmpty ? null : errors.join(' | '),
      fecIngWarning: fecIngWarning,
    );
  }

  /// Descarga CENCOS/galpones si el equipo todavía no los tiene.
  /// Es el único catálogo que trae `fec_ing_min` (la fecha de ingreso con la
  /// que se calcula la edad de las aves): la proyección solo manda los códigos
  /// de galpón. Sin esta descarga el campo «Galpones» de Vacunación queda
  /// vacío, porque hasta ahora solo lo bajaba «Descargar» del menú.
  Future<bool> syncGalpones({
    required StorageService storage,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    try {
      final gal = await _api.downloadCencosGalpones().timeout(timeout);
      if (gal['success'] != true) {
        debugPrint(
          'CatalogSync: CENCOS/galpones falló: '
          '${gal['message'] ?? 'sin mensaje'}',
        );
        return false;
      }
      if (gal['indices'] is GalponesCatalogIndices) {
        await storage.saveCencosGalponesIndexed(
          gal['indices'] as GalponesCatalogIndices,
        );
      } else if (gal['data'] is Map) {
        await storage.saveCencosGalpones(
          Map<String, dynamic>.from(gal['data'] as Map),
        );
      } else {
        return false;
      }
      await storage.setLastDownloadDate();
      return storage.hasCencosGalponesLocal();
    } catch (e) {
      debugPrint('CatalogSync: error al descargar CENCOS/galpones: $e');
      return false;
    }
  }

  /// Sincroniza proyección ccos y la fusiona con el histórico local (≥ 1 año).
  /// [fecha] se ignora para la descarga: el backend usa hoy como referencia del rango.
  Future<bool> syncAppInfo({required StorageService storage}) async {
    final info = await _api.downloadAppInfo(
      versionWarningDesde: AppVersionService.warningDesdeForApi(storage),
    );
    if (info['success'] == true && info['data'] is Map) {
      await AppVersionService.mergeServerPayload(
        storage,
        Map<String, dynamic>.from(info['data'] as Map),
      );
      return true;
    }
    return false;
  }

  AppVersionStatus localAppVersionStatus(StorageService storage) {
    return AppVersionService.fromStorage(storage);
  }

  Future<CatalogSyncResult> syncProyeccion({
    required StorageService storage,
    String? fecha,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (!await hasInternet()) {
      return CatalogSyncResult(
        hadInternet: false,
        cencosOk: storage.hasCencosGalponesLocal(),
        proyeccionOk: storage.getProyeccion() != null,
        cencosCount: storage.getCencosListaLocal().length,
        errorMessage: 'Sin conexión a internet',
      );
    }

    try {
      final fechaCatalogo = DateTime.now().toIso8601String().substring(0, 10);
      final proy = await _api
          .downloadProyeccion(fecha: fechaCatalogo)
          .timeout(timeout);
      if (proy['success'] == true && proy['data'] is Map) {
        await storage.saveProyeccion(
          Map<String, dynamic>.from(proy['data'] as Map),
        );
        await syncAppInfo(storage: storage);
        return CatalogSyncResult(
          hadInternet: true,
          cencosOk: storage.getCencosListaLocal().isNotEmpty,
          proyeccionOk: true,
          cencosCount: storage.getCencosListaLocal().length,
        );
      }
      return CatalogSyncResult(
        hadInternet: true,
        cencosOk: storage.getCencosListaLocal().isNotEmpty,
        proyeccionOk: false,
        cencosCount: storage.getCencosListaLocal().length,
        errorMessage: proy['message']?.toString(),
      );
    } on TimeoutException {
      return CatalogSyncResult(
        hadInternet: true,
        cencosOk: storage.hasCencosGalponesLocal(),
        proyeccionOk: false,
        cencosCount: storage.getCencosListaLocal().length,
        errorMessage: 'Conexión lenta',
      );
    } catch (e) {
      return CatalogSyncResult(
        hadInternet: true,
        cencosOk: storage.hasCencosGalponesLocal(),
        proyeccionOk: false,
        cencosCount: storage.getCencosListaLocal().length,
        errorMessage: e.toString(),
      );
    }
  }
}
