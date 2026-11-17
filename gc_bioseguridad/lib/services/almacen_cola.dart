import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';
import 'app_http_client.dart';
import 'storage_service.dart';

/// Cola offline de movimientos de almacén. Se sube con el resto al sincronizar.
class AlmacenCola {
  AlmacenCola(this.storage, {http.Client? client})
      : _http = client ?? createAppHttpClient();

  final StorageService storage;
  final http.Client _http;

  static const _cola = 'bio_almacen_cola';
  static const _cache = 'bio_almacen_cache';

  List<Map<String, dynamic>> get operaciones {
    final raw = storage.prefsString(_cola);
    if (raw == null || raw.isEmpty) return [];
    try {
      final data = jsonDecode(raw);
      if (data is! List) return [];
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<Map<String, dynamic>> pendientesDe(String granja) {
    return operaciones.where((op) {
      if (op['synced'] == true) return false;
      if (granja.isEmpty) return true;
      return (op['granja'] ?? '').toString() == granja;
    }).toList();
  }

  int get pendientes => operaciones.where((op) => op['synced'] != true).length;

  Map<String, dynamic> cacheDe(String granja) {
    final raw = storage.prefsString(_cache);
    if (raw == null || raw.isEmpty) return {};
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return {};
      final item = data[granja];
      if (item is Map) return Map<String, dynamic>.from(item);
    } catch (_) {}
    return {};
  }

  Future<void> _guardarOps(List<Map<String, dynamic>> ops) async {
    await storage.setPrefsString(_cola, jsonEncode(ops));
  }

  Future<void> _guardarCache(String granja, Map<String, dynamic> data) async {
    Map<String, dynamic> todo = {};
    final raw = storage.prefsString(_cache);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) todo = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    todo[granja] = data;
    await storage.setPrefsString(_cache, jsonEncode(todo));
  }

  Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final codigo = (prefs.getString(AppConstants.keyUserCode) ?? '').trim();
    return {
      'Authorization': 'Bearer ${AppConstants.apiToken}',
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
      if (codigo.isNotEmpty) 'X-Usuario-Codigo': codigo,
    };
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(
      '${AppConstants.baseUrl}${AppConstants.seguimientoPath}$path',
    );
    if (query == null || query.isEmpty) return base;
    return base.replace(queryParameters: query);
  }

  Future<void> encolar(Map<String, dynamic> op) async {
    final ops = operaciones;
    ops.add(op);
    await _guardarOps(ops);
  }

  Future<bool> sincronizar() async {
    final ops = operaciones;
    final pend = ops.where((op) => op['synced'] != true).toList();
    if (pend.isEmpty) return true;
    try {
      final res = await _http
          .post(
            _uri(AppConstants.guardarAlmacenEndpoint),
            headers: await _headers(),
            body: jsonEncode({'ops': pend}),
          )
          .timeout(const Duration(seconds: 25));
      final decoded = jsonDecode(res.body);
      if (decoded is! Map || decoded['success'] != true) return false;
      final data = decoded['data'];
      final resultados = data is Map ? data['resultados'] : null;
      if (resultados is! List) return false;
      final okIds = <String>{};
      for (final r in resultados) {
        if (r is Map && r['ok'] == true) {
          okIds.add((r['uuid'] ?? '').toString());
        }
      }
      if (okIds.isEmpty) return false;
      final queda = ops.where((op) {
        final id = (op['uuid'] ?? op['id'] ?? '').toString();
        return !okIds.contains(id);
      }).toList();
      await _guardarOps(queda);
      return queda.every((op) => op['synced'] == true);
    } catch (e) {
      debugPrint('[Almacen] sync $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> descargar(String granja) async {
    try {
      final res = await _http
          .get(
            _uri(AppConstants.getAlmacenEndpoint, {
              if (granja.isNotEmpty) 'granja': granja,
            }),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map || decoded['success'] != true) return null;
      final data = decoded['data'];
      if (data is! Map) return null;
      final map = Map<String, dynamic>.from(data);
      if (granja.isNotEmpty) await _guardarCache(granja, map);
      return map;
    } catch (e) {
      debugPrint('[Almacen] GET $e');
      return null;
    }
  }
}
