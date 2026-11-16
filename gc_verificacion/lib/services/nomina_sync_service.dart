import 'dart:io';

import '../utils/constants.dart';
import 'api_service.dart';
import 'nomina_store.dart';
import 'storage_service.dart';

class NominaSyncResult {
  const NominaSyncResult({
    required this.hadInternet,
    this.full = false,
    this.altas = 0,
    this.bajas = 0,
    this.omitidos = 0,
    this.total = 0,
    this.version = '',
    this.errorMessage,
  });

  final bool hadInternet;
  final bool full;
  final int altas;
  final int bajas;
  final int omitidos;
  final int total;
  final String version;
  final String? errorMessage;
}

class NominaSyncService {
  NominaSyncService({ApiService? api}) : _api = api ?? ApiService();

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

  static String clavePara(StorageService storage) {
    final enom = (storage.getLoginEnom() ?? '').trim();
    return enom.isEmpty ? AppConstants.offlineSalt : enom;
  }

  String _clave(StorageService storage) => clavePara(storage);

  Future<NominaSyncResult> syncAll({
    required StorageService storage,
    required NominaStore store,
  }) async {
    if (!await hasInternet()) {
      return const NominaSyncResult(
        hadInternet: false,
        errorMessage: 'Sin conexión a internet',
      );
    }
    await store.load(clave: _clave(storage));
    await _subirPendientes(storage, store);
    final desde = store.integro ? storage.getNominaVersion() : '';
    final res = await _api.downloadNomina(
      desde: desde.isEmpty ? null : desde,
      usuario: storage.getUserCodeSync(),
    );
    if (res['success'] != true || res['data'] is! Map) {
      return NominaSyncResult(
        hadInternet: true,
        errorMessage:
            res['message']?.toString() ?? 'No se descargó la nómina',
      );
    }
    final data = Map<String, dynamic>.from(res['data'] as Map);
    final version = (data['version'] ?? '').toString();
    final full = data['full'] == true;
    final sinCambios = data['sin_cambios'] == true;
    var altas = 0;
    var bajas = 0;
    var omitidos = 0;
    if (!sinCambios) {
      final la = (data['altas'] as List?) ?? [];
      final lb = (data['bajas'] as List?) ?? [];
      final clave = _clave(storage);
      if (full) {
        final r = await store.applyFull(la, clave: clave);
        altas = r.altas;
        omitidos = r.omitidos;
      } else {
        final r = await store.applyDelta(altas: la, bajas: lb, clave: clave);
        altas = r.altas;
        bajas = r.bajas;
        omitidos = r.omitidos;
      }
    }
    await storage.savePuedeEnrolar(data['puede_enrolar'] == true);
    if (version.isNotEmpty) await storage.saveNominaVersion(version);
    await storage.saveNominaTotal(store.total);
    await storage.setLastDownloadDate();
    return NominaSyncResult(
      hadInternet: true,
      full: full,
      altas: altas,
      bajas: bajas,
      omitidos: omitidos,
      total: store.total,
      version: version,
    );
  }

  Future<void> _subirPendientes(
    StorageService storage,
    NominaStore store,
  ) async {
    final pendientes = storage.getPlantillasPendientes();
    if (pendientes.isEmpty) return;
    for (final dni in pendientes) {
      final p = store.find(dni);
      if (p == null) {
        await storage.removePlantillaPendiente(dni);
        continue;
      }
      try {
        final res = await _api.uploadPlantilla(
          dni: p.dni,
          nombre: p.nombre,
          vector: p.vector.toList(),
          miniatura: p.miniatura,
          modelo: AppConstants.faceModel,
          usuario: storage.getUserCodeSync() ?? '',
          tidandroid: storage.getDeviceId() ?? '',
        );
        if (res['success'] == true ||
            res['denegado'] == true) {
          await storage.removePlantillaPendiente(dni);
        }
      } catch (_) {
        return;
      }
    }
  }
}
