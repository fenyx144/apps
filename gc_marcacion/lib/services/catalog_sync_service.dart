import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../utils/galpones_resolver.dart';
import 'api_service.dart';
import 'app_version_service.dart';
import 'catalog_service.dart';
import 'storage_service.dart';

class CatalogSyncResult {
  const CatalogSyncResult({
    required this.hadInternet,
    required this.cencosOk,
    required this.proyeccionOk,
    this.cencosCount = 0,
    this.catalogosOk = false,
    this.usuariosCount = 0,
    this.personalOk = false,
    this.personalCount = 0,
    this.avisoPersonal = '',
    this.errorMessage,
  });

  final bool hadInternet;
  final bool cencosOk;
  final bool proyeccionOk;
  final int cencosCount;
  final bool catalogosOk;
  final int usuariosCount;
  final bool personalOk;
  final int personalCount;
  final String avisoPersonal;
  final String? errorMessage;
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

  Future<CatalogSyncResult> syncAll({
    required StorageService storage,
    required CatalogService catalog,
    bool includeUsuariosConempre = true,
  }) async {
    await catalog.loadFromPrefs();
    if (!await hasInternet()) {
      return const CatalogSyncResult(
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
    final errors = <String>[];

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
        errors.add(gal['message']?.toString() ?? 'Error granjas');
      }
    } catch (e) {
      errors.add('Granjas: Error de conexión');
    }

    try {
      final fecha = DateTime.now().toIso8601String().substring(0, 10);
      final proy = await _api.downloadProyeccion(fecha: fecha);
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

    try {
      await syncAppInfo(storage: storage);
    } catch (e) {
      debugPrint('CatalogSync versión: $e');
    }

    if (includeUsuariosConempre) {
      try {
        final ok = await catalog.downloadCatalogos(
          tablas: ['usuarios', 'conempre'],
        );
        if (ok) {
          catalogosOk = true;
          final usuarios = catalog.catalogos['usuarios'];
          if (usuarios is List) usuariosCount = usuarios.length;
        } else {
          errors.add('Usuarios: no se pudieron descargar');
        }
      } catch (e) {
        errors.add('Usuarios: Error de conexión');
      }
    }

    var personalOk = false;
    var personalCount = 0;
    var avisoPersonal = '';
    try {
      final personal = await catalog.downloadMarcacion();
      personalOk = personal.ok;
      avisoPersonal = personal.aviso;
      personalCount = catalog.personal.length;
      if (!personalOk) {
        errors.add(
          personal.aviso.isEmpty ? 'Personal: no se descargó' : personal.aviso,
        );
      }
    } catch (e) {
      errors.add('Personal: Error de conexión');
    }

    if (cencosOk || proyeccionOk || catalogosOk || personalOk) {
      await storage.setLastDownloadDate();
    }

    return CatalogSyncResult(
      hadInternet: true,
      cencosOk: cencosOk,
      proyeccionOk: proyeccionOk,
      cencosCount: cencosCount,
      catalogosOk: catalogosOk,
      usuariosCount: usuariosCount,
      personalOk: personalOk,
      personalCount: personalCount,
      avisoPersonal: avisoPersonal,
      errorMessage: errors.isEmpty ? null : errors.join(' | '),
    );
  }

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
}
