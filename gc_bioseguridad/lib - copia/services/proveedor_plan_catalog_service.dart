import 'dart:convert';

import 'package:bioseguridad/services/api_service.dart';
import 'package:bioseguridad/services/proveedor_historial_service.dart';
import 'package:bioseguridad/services/storage_service.dart';
import 'package:bioseguridad/widgets/proveedor_dialog.dart';
import 'package:flutter/foundation.dart';

/// Catálogo descargado del servidor: proveedores que planifican en la web.
///
/// Se guarda en el dispositivo y se usa offline en el diálogo de proveedor.
class ProveedorPlanCatalogService {
  ProveedorPlanCatalogService(this._storage, {ApiService? api})
    : _api = api ?? ApiService();

  final StorageService _storage;
  final ApiService _api;

  List<_Fila> _cache = const [];
  bool _cacheLoaded = false;

  void _ensureCache() {
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    _cache = _parseJson(_storage.getProveedoresPlanCatalogJson());
  }

  /// Descarga y reemplaza el catálogo local.
  Future<bool> descargar() async {
    final res = await _api.downloadProveedoresPlanificacion();
    if (res['success'] != true) {
      debugPrint(
        '[proveedores_plan] descarga fallida: ${res['message'] ?? ''}',
      );
      return false;
    }
    final items = res['items'];
    if (items is! List) return false;
    final encoded = jsonEncode({
      'actualizadoEn': DateTime.now().toIso8601String(),
      'items': items,
    });
    await _storage.saveProveedoresPlanCatalogJson(encoded);
    _cacheLoaded = false;
    _ensureCache();
    debugPrint('[proveedores_plan] ${_cache.length} proveedor(es) en catálogo');
    return _cache.isNotEmpty;
  }

  List<ProveedorCcteItem> buscar(String q) {
    _ensureCache();
    final texto = q.trim();
    if (texto.isEmpty) return const [];

    final digits = texto.replaceAll(RegExp(r'\D'), '');
    final soloDigitos =
        digits.isNotEmpty && RegExp(r'^[\d\s.\-]+$').hasMatch(texto);
    final tieneLetras = RegExp(r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]').hasMatch(texto);

    if (texto.length < 3 && digits.length != 11) return const [];

    final out = <ProveedorCcteItem>[];
    for (final row in _cache) {
      var coincide = false;
      if (soloDigitos && digits.length >= 3) {
        coincide = row.ruc.startsWith(digits);
      }
      if (!coincide && tieneLetras && texto.length >= 3) {
        coincide = ProveedorHistorialService.claveNombre(
          row.nombre,
        ).contains(ProveedorHistorialService.claveNombre(texto));
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
      if (out.length >= ProveedorHistorialService.maxResultadosBusqueda) break;
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
        if (ruc.length != 11 && nombre.isEmpty) continue;
        out.add(_Fila(ruc: ruc.length == 11 ? ruc : '', nombre: nombre));
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

/// Une historial del equipo y catálogo de planificación sin duplicar RUC/nombre.
List<ProveedorCcteItem> fusionarBusquedaLocal(
  List<ProveedorCcteItem> historial,
  List<ProveedorCcteItem> catalogoPlan,
) {
  final out = <ProveedorCcteItem>[];
  final vistosRuc = <String>{};
  final vistosNombre = <String>{};

  void agregar(ProveedorCcteItem it) {
    if (it.ruc.length == 11) {
      if (!vistosRuc.add(it.ruc)) return;
    } else {
      final k = ProveedorHistorialService.claveNombre(it.razonsocial);
      if (k.isEmpty || !vistosNombre.add(k)) return;
    }
    out.add(it);
  }

  for (final it in historial) {
    agregar(it);
  }
  for (final it in catalogoPlan) {
    agregar(it);
  }
  return out;
}
