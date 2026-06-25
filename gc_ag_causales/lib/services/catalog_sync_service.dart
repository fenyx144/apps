import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'catalog_service.dart';
import 'storage_service.dart';
import '../utils/galpones_resolver.dart';

/// Resultado de intentar sincronizar catálogos con el servidor.
class CatalogSyncResult {
  const CatalogSyncResult({
    required this.hadInternet,
    required this.downloadedAnything,
  });

  /// Había conexión a internet al momento del intento.
  final bool hadInternet;

  /// Al menos un catálogo se descargó y guardó correctamente.
  final bool downloadedAnything;

  bool get usedCachedData => !downloadedAnything;
}

/// Descarga automática de catálogos con internet; sin red o si falla, datos locales.
class CatalogSyncService {
  CatalogSyncService({ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;

  static DateTime? _ultimaSyncCompleta;
  static const _debounceSync = Duration(minutes: 2);

  static Future<bool> hasInternet() async {
    try {
      final r = await InternetAddress.lookup('google.com');
      return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    }
  }

  /// Carga siempre los catálogos guardados y, si hay red, intenta actualizarlos.
  Future<CatalogSyncResult> syncAll({
    required StorageService storage,
    required CatalogService catalog,
    String? proyeccionFecha,
    bool forzar = false,
  }) async {
    await catalog.loadFromPrefs();

    if (!forzar &&
        _ultimaSyncCompleta != null &&
        DateTime.now().difference(_ultimaSyncCompleta!) < _debounceSync) {
      return const CatalogSyncResult(
        hadInternet: true,
        downloadedAnything: false,
      );
    }

    if (!await hasInternet()) {
      return const CatalogSyncResult(
        hadInternet: false,
        downloadedAnything: false,
      );
    }

    var downloaded = false;
    var galponesOk = false;
    try {
      final gal = await _api.downloadCencosGalpones();
      if (gal['success'] == true) {
        if (gal['indices'] is GalponesCatalogIndices) {
          await storage.saveCencosGalponesIndexed(
            gal['indices'] as GalponesCatalogIndices,
          );
          galponesOk = true;
          downloaded = true;
        } else if (gal['data'] is Map) {
          await storage.saveCencosGalpones(
            Map<String, dynamic>.from(gal['data'] as Map),
          );
          galponesOk = storage.hasCencosGalponesLocal();
          if (galponesOk) downloaded = true;
        }
      } else {
        debugPrint(
          'CatalogSyncService: falló descarga galpones: ${gal['message']}',
        );
      }

      final proy = await _api.downloadProyeccion(fecha: proyeccionFecha);
      if (proy['success'] == true && proy['data'] is Map) {
        await storage.saveProyeccion(
          Map<String, dynamic>.from(proy['data'] as Map),
        );
        downloaded = true;
      }

      final arbol = await _api.downloadArbolProcesos();
      if (arbol['success'] == true && arbol['data'] is Map) {
        await storage.saveArbolProcesos(
          Map<String, dynamic>.from(arbol['data'] as Map),
        );
        downloaded = true;
      }

      if (await catalog.downloadCatalogos(tablas: ['usuarios'])) {
        downloaded = true;
      }

      if (downloaded) {
        await storage.setLastDownloadDate();
        _ultimaSyncCompleta = DateTime.now();
      }
    } catch (e, st) {
      debugPrint('CatalogSyncService.syncAll: $e\n$st');
    }

    return CatalogSyncResult(
      hadInternet: true,
      downloadedAnything: downloaded,
    );
  }

  /// Solo proyección (p. ej. al cambiar fecha en registro). Sin red usa la guardada.
  Future<CatalogSyncResult> syncProyeccion({
    required StorageService storage,
    required String fecha,
  }) async {
    if (!await hasInternet()) {
      return const CatalogSyncResult(
        hadInternet: false,
        downloadedAnything: false,
      );
    }

    try {
      final proy = await _api.downloadProyeccion(fecha: fecha);
      if (proy['success'] == true && proy['data'] is Map) {
        await storage.saveProyeccion(
          Map<String, dynamic>.from(proy['data'] as Map),
        );
        return const CatalogSyncResult(
          hadInternet: true,
          downloadedAnything: true,
        );
      }
    } catch (e, st) {
      debugPrint('CatalogSyncService.syncProyeccion: $e\n$st');
    }

    return const CatalogSyncResult(
      hadInternet: true,
      downloadedAnything: false,
    );
  }
}
