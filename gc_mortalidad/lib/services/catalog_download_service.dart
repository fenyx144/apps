import 'dart:io';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'catalog_service.dart';
import 'storage_service.dart';

class CatalogDownloadResult {
  final bool success;
  final String message;
  final bool cencosOk;
  final bool motivosOk;
  final bool usuariosOk;

  const CatalogDownloadResult({
    required this.success,
    required this.message,
    this.cencosOk = false,
    this.motivosOk = false,
    this.usuariosOk = false,
  });
}

class CatalogDownloadService {
  CatalogDownloadService({
    ApiService? apiService,
  }) : _apiService = apiService ?? ApiService();

  final ApiService _apiService;

  Future<bool> hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    }
  }

  bool catalogsAreEmpty(StorageService storage) {
    return storage.getCencosLocal().isEmpty ||
        storage.getMotivosMortalidad().isEmpty;
  }

  Future<CatalogDownloadResult> downloadAll({
    required StorageService storage,
    required CatalogService catalogService,
    List<String> catalogTables = const ['usuarios', 'conempre'],
  }) async {
    if (!await hasInternet()) {
      return const CatalogDownloadResult(
        success: false,
        message: 'Sin conexión a internet',
      );
    }

    var cencosOk = false;
    var motivosOk = false;
    var usuariosOk = false;
    final errors = <String>[];

    try {
      final cencosResult = await _apiService.downloadCencosGalpones();
      debugPrint('[CENCOS_DOWNLOAD] success=${cencosResult['success']} message=${cencosResult['message']}');
      if (cencosResult['success'] == true) {
        final cencos = cencosResult['cencos'] as List;
        final galponesPorCenco =
            cencosResult['galponesPorCenco'] as Map<String, List<dynamic>>;
        debugPrint('[CENCOS_DOWNLOAD] cencos count=${cencos.length} galpones keys=${galponesPorCenco.keys.length}');
        if (cencos.isNotEmpty) {
          final first = cencos.first;
          debugPrint('[CENCOS_DOWNLOAD] first cenco codigo=${first.codigo} nombre=${first.nombre}');
        }
        await storage.saveCencosGalpones(
          cencos: cencos
              .map((c) => {
                    'codigo': c.codigo,
                    'nombre': c.nombre,
                    'edad': c.edad,
                    'fec_ing_min': c.fecIngMin ?? '',
                  })
              .toList(),
          galponesPorCenco: galponesPorCenco.map(
            (k, v) => MapEntry(
              k,
              v
                  .map((g) => {
                        'tcencos': g.tcencos,
                        'tcodint': g.tcodint,
                        'fec_ing_min': g.fecIngMin ?? '',
                        'edad': g.edadDias.toString(),
                      })
                  .toList(),
            ),
          ),
        );
        cencosOk = cencos.isNotEmpty;
        // Verificar que se guardo correctamente
        final verify = storage.getCencosLocal();
        debugPrint('[CENCOS_DOWNLOAD] verificacion post-save: getCencosLocal().length=${verify.length}');
      } else {
        errors.add('Granjas: ${cencosResult['message']?.toString() ?? 'Error desconocido'}');
      }
    } catch (e) {
      errors.add('Granjas: Error de conexi\u00f3n');
      debugPrint('Error descargando cencos: $e');
    }

    try {
      final usuariosResult = await catalogService.downloadCatalogos(
        apiCall: _apiService.downloadCatalogos,
        tablas: catalogTables,
      );
      usuariosOk = usuariosResult['success'] == true;
      if (!usuariosOk) {
        errors.add(
          'Usuarios: Error al descargar',
        );
      }
    } catch (e) {
      errors.add('Usuarios: Error de conexi\u00f3n');
      debugPrint('Error descargando usuarios: $e');
    }

    try {
      final motivosResult = await _apiService.downloadMotivosMortalidad();
      if (motivosResult['success'] == true) {
        final motivos = motivosResult['motivos'] as List;
        await storage.saveMotivosMortalidad(
          motivos
              .map((m) => {'tcod_mort': m.codigo, 'tnom_mort': m.nombre})
              .toList(),
        );
        await catalogService.loadFromPrefs();
        motivosOk = motivos.isNotEmpty;
      } else {
        errors.add('Causas: Error al descargar');
      }
    } catch (e) {
      errors.add('Causas: Error de conexi\u00f3n');
      debugPrint('Error descargando motivos: $e');
    }

    if (cencosOk || motivosOk || usuariosOk) {
      await storage.setLastDownloadDate();
    }

    final allOk = cencosOk && motivosOk;
    if (allOk) {
      return CatalogDownloadResult(
        success: true,
        message: 'Catálogos descargados correctamente',
        cencosOk: cencosOk,
        motivosOk: motivosOk,
        usuariosOk: usuariosOk,
      );
    }

    if (cencosOk || motivosOk) {
      return CatalogDownloadResult(
        success: true,
        message: errors.isEmpty
            ? 'Descarga parcial completada'
            : 'Descarga parcial: ${errors.join('; ')}',
        cencosOk: cencosOk,
        motivosOk: motivosOk,
        usuariosOk: usuariosOk,
      );
    }

    return CatalogDownloadResult(
      success: false,
      message: errors.isEmpty ? 'No se pudieron descargar los catálogos' : errors.join('; '),
      cencosOk: cencosOk,
      motivosOk: motivosOk,
      usuariosOk: usuariosOk,
    );
  }

  Future<bool> downloadMotivosIfNeeded(StorageService storage) async {
    if (storage.getMotivosMortalidad().isNotEmpty) return true;
    if (!await hasInternet()) return false;
    try {
      final result = await _apiService.downloadMotivosMortalidad();
      if (result['success'] != true) return false;
      final motivos = result['motivos'] as List;
      if (motivos.isEmpty) return false;
      await storage.saveMotivosMortalidad(
        motivos
            .map((m) => {'tcod_mort': m.codigo, 'tnom_mort': m.nombre})
            .toList(),
      );
      return true;
    } catch (e) {
      debugPrint('Error descargando motivos: $e');
      return false;
    }
  }

  Future<CatalogDownloadResult> downloadIfNeeded({
    required StorageService storage,
    required CatalogService catalogService,
  }) async {
    if (!catalogsAreEmpty(storage)) {
      return const CatalogDownloadResult(
        success: true,
        message: 'Catálogos ya disponibles localmente',
        cencosOk: true,
        motivosOk: true,
      );
    }
    return downloadAll(storage: storage, catalogService: catalogService);
  }
}
