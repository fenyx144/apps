import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'storage_service.dart';
import '../widgets/proveedor_dialog.dart';

/// Catálogo de laboratorios habilitados en Sanidad (configuración web).
class ProveedorVacunaCatalogService {
  ProveedorVacunaCatalogService(this._storage, {ApiService? api})
    : _api = api ?? ApiService();

  final StorageService _storage;
  final ApiService _api;

  List<_Fila> _cache = const [];
  bool _cacheLoaded = false;

  void _ensureCache() {
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    _cache = _parseJson(_storage.getProveedoresVacunaCatalogJson());
  }

  /// Hay al menos un laboratorio en la descarga de configuración web.
  bool get tieneProveedoresHabilitados {
    _ensureCache();
    return _cache.isNotEmpty;
  }

  Future<bool> descargar() async {
    final res = await _api.downloadProveedoresVacuna();
    if (res['success'] != true) {
      debugPrint(
        '[proveedores_vacuna] descarga fallida: ${res['message'] ?? ''}',
      );
      return false;
    }
    final items = res['items'];
    if (items is! List) return false;
    final encoded = jsonEncode({
      'actualizadoEn': DateTime.now().toIso8601String(),
      'items': items,
    });
    await _storage.saveProveedoresVacunaCatalogJson(encoded);
    _cacheLoaded = false;
    _ensureCache();
    debugPrint('[proveedores_vacuna] ${_cache.length} laboratorio(s)');
    return true;
  }

  List<ProveedorCcteItem> buscar(String q) {
    _ensureCache();
    final texto = q.trim();
    if (texto.isEmpty) {
      return _cache
          .map(
            (row) => ProveedorCcteItem(
              ruc: row.ruc,
              razonsocial:
                  row.nombre.isNotEmpty ? row.nombre : 'RUC ${row.ruc}',
              catalogoPlanificacion: true,
            ),
          )
          .toList();
    }

    final digits = texto.replaceAll(RegExp(r'\D'), '');
    final soloDigitos =
        digits.isNotEmpty && RegExp(r'^[\d\s.\-]+$').hasMatch(texto);
    final tieneLetras = RegExp(r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]').hasMatch(texto);

    if (texto.length < 3 && digits.length != 11) return const [];

    const max = 25;
    final out = <ProveedorCcteItem>[];
    for (final row in _cache) {
      var coincide = false;
      if (soloDigitos && digits.length >= 3) {
        coincide = row.ruc.startsWith(digits);
      }
      if (!coincide && tieneLetras && texto.length >= 3) {
        coincide = row.nombre.toUpperCase().contains(texto.toUpperCase());
      }
      if (!coincide && digits.length == 11 && row.ruc == digits) {
        coincide = true;
      }
      if (!coincide) continue;
      out.add(
        ProveedorCcteItem(
          ruc: row.ruc,
          razonsocial: row.nombre.isNotEmpty ? row.nombre : 'RUC ${row.ruc}',
          catalogoPlanificacion: true,
        ),
      );
      if (out.length >= max) break;
    }
    return out;
  }

  static List<_Fila> _parseJson(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const [];
      final items = decoded['items'];
      if (items is! List) return const [];
      final out = <_Fila>[];
      for (final row in items) {
        if (row is! Map) continue;
        final ruc = (row['ruc'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
        final nombre = (row['razonsocial'] ?? row['nombre'] ?? '')
            .toString()
            .trim();
        if (ruc.length != 11 || nombre.isEmpty) continue;
        out.add(_Fila(ruc: ruc, nombre: nombre));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}

class _Fila {
  const _Fila({required this.ruc, required this.nombre});

  final String ruc;
  final String nombre;
}
