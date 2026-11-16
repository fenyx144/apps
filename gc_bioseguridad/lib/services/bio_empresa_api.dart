import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';
import 'app_http_client.dart';

/// API bioseguridad con el mismo Bearer y usuario que el login GRS (tabla `usuario`).
class BioEmpresaApi {
  BioEmpresaApi({http.Client? client}) : _client = client ?? createAppHttpClient();

  final http.Client _client;

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

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
  }) async {
    var url = Uri.parse('${AppConstants.bioEmpresaApiBase}$path');
    if (query != null && query.isNotEmpty) {
      url = url.replace(queryParameters: query);
    }
    late final http.Response res;
    try {
      res = await _client
          .get(url, headers: await _headers())
          .timeout(const Duration(seconds: 15));
    } on SocketException {
      throw BioEmpresaApiException(
        'sin_conexion',
        'Sin conexión al servidor (${url.host}). Revise Wi‑Fi/VPN y que la URL base sea correcta.',
      );
    } on HandshakeException {
      throw BioEmpresaApiException(
        'tls',
        'No se pudo validar el certificado HTTPS del servidor. Use red interna o contacte a sistemas.',
      );
    } on TimeoutException {
      throw BioEmpresaApiException(
        'timeout',
        'El servidor no respondió a tiempo.\n'
        'Compruebe que exista en el servidor htdocs/bioseguridad/api/public '
        '(mismo host que el login, no bajo sanidad/flutter).',
      );
    }
    if (kDebugMode) {
      debugPrint('[BioEmpresaApi] GET $url → ${res.statusCode}');
    }
    final body = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) {
      throw BioEmpresaApiException(
        'HTTP ${res.statusCode}',
        _mensajeDesdeCuerpo(body) ?? body,
      );
    }
    final data = jsonDecode(body);
    if (data is! Map<String, dynamic>) {
      throw BioEmpresaApiException('respuesta_invalida', 'Respuesta no válida');
    }
    final ok = data['ok'] == true || data['success'] == true;
    if (!ok) {
      final err = data['error'];
      final msg = err is Map
          ? (err['message']?.toString() ?? 'No autorizado')
          : (data['message']?.toString() ?? 'No autorizado');
      throw BioEmpresaApiException(
        err is Map ? (err['code']?.toString() ?? 'error') : 'error',
        msg,
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final url = Uri.parse('${AppConstants.bioEmpresaApiBase}$path');
    late final http.Response res;
    try {
      res = await _client
          .post(url, headers: await _headers(), body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
    } on SocketException {
      throw BioEmpresaApiException(
        'sin_conexion',
        'Sin conexión al servidor (${url.host}). Revise Wi‑Fi/VPN y que la URL base sea correcta.',
      );
    } on HandshakeException {
      throw BioEmpresaApiException(
        'tls',
        'No se pudo validar el certificado HTTPS del servidor. Use red interna o contacte a sistemas.',
      );
    } on TimeoutException {
      throw BioEmpresaApiException(
        'timeout',
        'El servidor no respondió a tiempo.\n'
        'Compruebe que exista en el servidor htdocs/bioseguridad/api/public '
        '(mismo host que el login, no bajo sanidad/flutter).',
      );
    }
    final raw = utf8.decode(res.bodyBytes);
    final data = jsonDecode(raw);
    if (data is! Map<String, dynamic>) {
      throw BioEmpresaApiException('respuesta_invalida', 'Respuesta no válida');
    }
    return data;
  }

  /// Personal activo del portal (`bio_personal`), con `foto_ruta` del alta.
  Future<List<Map<String, dynamic>>> listarPersonalActivo() async {
    final out = <Map<String, dynamic>>[];
    var page = 1;
    while (page <= 40) {
      final data = await get(
        '/personal',
        query: {
          'estado': 'ACTIVO',
          'page': '$page',
          'per_page': '500',
        },
      );
      final filas = _filasPersonal(data['data'] ?? data);
      if (filas.isEmpty) break;
      out.addAll(filas);
      final payload = data['data'];
      final total = payload is Map
          ? int.tryParse('${payload['total']}') ?? out.length
          : out.length;
      if (out.length >= total || filas.length < 500) break;
      page++;
    }
    return out;
  }

  /// Acepta `data.items`, `data.rows`, `data.personas` o una lista directa.
  static List<Map<String, dynamic>> _filasPersonal(dynamic payload) {
    final lista = _listaDe(payload);
    return [
      for (final e in lista)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  }

  static List<dynamic> _listaDe(dynamic payload) {
    if (payload is List) return payload;
    if (payload is Map) {
      for (final key in ['items', 'rows', 'personas', 'data']) {
        final v = payload[key];
        if (v is List) return v;
        if (v is Map) {
          final anidada = _listaDe(v);
          if (anidada.isNotEmpty) return anidada;
        }
      }
    }
    return const [];
  }

  /// Bytes de `foto_ruta` (`storage/personal/...`). No persiste el archivo.
  Future<Uint8List?> descargarArchivo(String ruta) async {
    final limpia = ruta.trim();
    if (limpia.isEmpty) return null;
    final url = limpia.startsWith('http')
        ? Uri.parse(limpia)
        : Uri.parse(
            '${AppConstants.bioEmpresaApiBase}/${limpia.replaceFirst(RegExp(r'^/'), '')}',
          );
    try {
      final res = await _client
          .get(url, headers: await _headers())
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200 || res.bodyBytes.length < 32) return null;
      final tipo = (res.headers['content-type'] ?? '').toLowerCase();
      if (tipo.contains('json') || tipo.contains('text/')) return null;
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  /// ¿Hay login local en la app? (no implica que la API responda).
  Future<bool> appConSesion() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getBool(AppConstants.keyIsLoggedIn) ?? false) &&
        (prefs.getString(AppConstants.keyUserCode) ?? '').trim().isNotEmpty;
  }

  String? _mensajeDesdeCuerpo(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] is Map) {
        return j['error']['message']?.toString();
      }
    } catch (_) {}
    return null;
  }
}

class BioEmpresaApiException implements Exception {
  BioEmpresaApiException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => message;
}
