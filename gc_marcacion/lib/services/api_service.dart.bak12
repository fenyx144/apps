import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';
import '../utils/galpones_resolver.dart';
import 'app_version_service.dart';
import 'storage_service.dart';

class ApiService {
  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${AppConstants.apiToken}',
        'Content-Type': 'application/json; charset=utf-8',
      };

  Future<String> _getUsuarioSesion() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(AppConstants.keyUserCode) ?? '').trim();
  }

  Future<Map<String, dynamic>> login({
    required String usuario,
    required String password,
    required String androidId,
    required String version,
  }) async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.loginEndpoint}',
      );
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final avisoDesde = AppVersionService.warningDesdeForApi(storage);
      final body = jsonEncode({
        'usuario': usuario,
        'password': base64Encode(utf8.encode(password)),
        'android': androidId,
        'version': version,
        'app': AppConstants.appName,
        if (avisoDesde != null) 'version_warning_desde': avisoDesde,
      });
      final response = await http
          .post(url, headers: _headers, body: body)
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': data['success'] ?? false,
        'message': data['message'] ?? '',
        'errorCode': data['errorCode'],
        'data': data['data'],
      };
    } catch (e) {
      return {'success': false, 'message': 'Error de conexión: $e'};
    }
  }

  Future<Map<String, dynamic>> registerDevice({
    required String androidId,
    required String fabricante,
    required String familia,
    required String modelo,
    required String descripcion,
  }) async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.registerDeviceEndpoint}',
      );
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final avisoDesde = AppVersionService.warningDesdeForApi(storage);
      final body = jsonEncode({
        'android': androidId,
        'fabricante': fabricante,
        'familia': familia,
        'modelo': modelo,
        'descripcion': descripcion,
        'version': AppConstants.appVersion,
        'app': AppConstants.appName,
        if (avisoDesde != null) 'version_warning_desde': avisoDesde,
      });
      final response = await http
          .post(url, headers: _headers, body: body)
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': data['success'] ?? false,
        'message': data['message'] ?? '',
        'errorCode': data['errorCode'],
        'data': data['data'],
      };
    } catch (e) {
      return {'success': false, 'message': 'Error de conexión: $e'};
    }
  }

  Future<Map<String, dynamic>> downloadCatalogos({List<String>? tablas}) async {
    try {
      var url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.downloadEndpoint}',
      );
      if (tablas != null && tablas.isNotEmpty) {
        url = url.replace(queryParameters: {'tablas': tablas.join(',')});
      }
      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'data': data['data'] is Map ? data['data'] : {},
        };
      }
      return {'success': false, 'message': data['message'] ?? 'Error'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> downloadCencosGalpones() async {
    final usuario = await _getUsuarioSesion();

    Uri withUsuario(String path) {
      final base = Uri.parse('${AppConstants.baseUrl}$path');
      if (usuario.isEmpty) return base;
      return base.replace(queryParameters: {'usuario': usuario});
    }

    final candidates = <Uri>[
      withUsuario(
        '${AppConstants.catalogosPath}/get_cencos_galpones_movil.php',
      ),
      withUsuario(
        '${AppConstants.catalogosPath}/get_cencos_galpones.php',
      ),
    ];

    String lastError = 'No se pudo descargar CENCOS/galpones';
    for (final url in candidates) {
      try {
        final response = await http
            .get(url, headers: _headers)
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) {
          lastError = 'HTTP ${response.statusCode} en ${url.path}';
          continue;
        }
        final decoded = jsonDecode(response.body);
        if (decoded is Map &&
            decoded['success'] == true &&
            decoded['data'] is Map) {
          final data = Map<String, dynamic>.from(decoded['data'] as Map);
          final indices = GalponesResolver.buildIndicesFromApiData(data);
          if (indices.cencos.isEmpty) {
            lastError = 'Respuesta OK pero sin CENCOS (${url.path})';
            continue;
          }
          return {
            'success': true,
            'data': data,
            'indices': indices,
          };
        }
        lastError = decoded is Map
            ? (decoded['message']?.toString() ?? 'Respuesta inválida')
            : 'Respuesta inválida';
      } catch (e) {
        lastError = e.toString();
        debugPrint('ApiService: error CENCOS $url: $e');
      }
    }
    return {'success': false, 'message': lastError};
  }

  Future<Map<String, dynamic>> downloadAppInfo({
    String? versionWarningDesde,
  }) async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.catalogosPath}/get_app_info_movil.php',
      ).replace(queryParameters: {
        'tcod': AppConstants.appName,
        'version': AppConstants.appVersion,
        if (versionWarningDesde != null && versionWarningDesde.isNotEmpty)
          'version_warning_desde': versionWarningDesde,
      });
      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return {
          'success': false,
          'message': 'Error HTTP ${response.statusCode}',
        };
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map &&
          decoded['success'] == true &&
          decoded['data'] is Map) {
        return {
          'success': true,
          'data': Map<String, dynamic>.from(decoded['data'] as Map),
        };
      }
      return {
        'success': false,
        'message': decoded is Map ? decoded['message'] : 'Error',
        'errorCode': decoded is Map ? decoded['errorCode'] : null,
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> downloadProyeccion({String? fecha}) async {
    try {
      final usuario = await _getUsuarioSesion();
      final f = fecha ?? DateTime.now().toIso8601String().substring(0, 10);
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.catalogosPath}/get_cencos_proyeccion_movil.php',
      ).replace(queryParameters: {
        'fecha': f,
        if (usuario.isNotEmpty) 'usuario': usuario,
      });
      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        return {
          'success': false,
          'message': 'Error HTTP ${response.statusCode}',
        };
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['success'] == true) {
        return {'success': true, 'data': decoded['data']};
      }
      return {
        'success': false,
        'message': decoded is Map ? decoded['message'] : 'Error',
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> downloadCatalogosMarcacion() async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.seguimientoPath}'
        '${AppConstants.catalogosMarcacionEndpoint}',
      );
      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 25));
      final body = response.body.trim();
      if (response.statusCode != 200) {
        final corto = body.length > 180 ? body.substring(0, 180) : body;
        return {
          'success': false,
          'message': corto.isEmpty
              ? 'HTTP ${response.statusCode}'
              : 'HTTP ${response.statusCode}: $corto',
        };
      }
      if (body.isEmpty) {
        return {'success': false, 'message': 'Respuesta vacía del servidor'};
      }
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['success'] == true && decoded['data'] is Map) {
        return {
          'success': true,
          'data': Map<String, dynamic>.from(decoded['data'] as Map),
          'message': decoded['message']?.toString() ?? '',
        };
      }
      return {
        'success': false,
        'message': decoded is Map
            ? (decoded['message']?.toString() ?? 'Error')
            : 'Error',
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Sube marcaciones. El servidor inserta en `marc` y responde por uuid.
  Future<Map<String, dynamic>> uploadMarcaciones(
    List<Map<String, dynamic>> registros,
  ) async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.seguimientoPath}'
        '${AppConstants.guardarMarcacionEndpoint}',
      );
      final response = await http
          .post(
            url,
            headers: _headers,
            body: jsonEncode({'registros': registros}),
          )
          .timeout(const Duration(seconds: 40));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return {'success': false, 'message': 'Respuesta inválida'};
      }
      return {
        'success': decoded['success'] == true,
        'message': decoded['message']?.toString() ?? '',
        'data': decoded['data'],
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Borra en el servidor (tabla marc) marcas ya enviadas.
  Future<Map<String, dynamic>> borrarMarcaciones(
    List<Map<String, dynamic>> registros,
  ) async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.seguimientoPath}'
        '${AppConstants.borrarMarcacionEndpoint}',
      );
      final response = await http
          .post(
            url,
            headers: _headers,
            body: jsonEncode({'registros': registros}),
          )
          .timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return {'success': false, 'message': 'Respuesta inválida'};
      }
      return {
        'success': decoded['success'] == true,
        'message': decoded['message']?.toString() ?? '',
        'data': decoded['data'],
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}
