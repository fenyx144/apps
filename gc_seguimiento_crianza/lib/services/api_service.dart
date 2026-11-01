import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import 'app_version_service.dart';
import 'storage_service.dart';
import '../utils/galpones_resolver.dart';
import '../utils/record_id.dart';

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

    final candidates = <({Uri url, bool auth})>[
      (
        url: withUsuario(
          '${AppConstants.seguimientoPath}/get_cencos_galpones_movil.php',
        ),
        auth: true,
      ),
      (
        url: withUsuario(
          '${AppConstants.seguimientoPath}/get_cencos_galpones.php',
        ),
        auth: true,
      ),
    ];

    String lastError = 'No se pudo descargar CENCOS/galpones';
    for (final c in candidates) {
      final url = c.url;
      try {
        final headers = c.auth
            ? _headers
            : <String, String>{
                'Content-Type': 'application/json; charset=utf-8',
              };
        debugPrint(
          'ApiService: descargando CENCOS/galpones $url (auth=${c.auth})',
        );
        final response = await http
            .get(url, headers: headers)
            .timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) {
          lastError = 'HTTP ${response.statusCode} en ${url.path}';
          debugPrint(
            'ApiService: $lastError body=${response.body.length > 160 ? response.body.substring(0, 160) : response.body}',
          );
          continue;
        }
        dynamic decoded;
        try {
          decoded = jsonDecode(response.body);
        } catch (_) {
          lastError = 'JSON inválido en ${url.path}';
          debugPrint('ApiService: $lastError');
          continue;
        }
        if (decoded is Map &&
            decoded['success'] == true &&
            decoded['data'] is Map) {
          final data = Map<String, dynamic>.from(decoded['data'] as Map);
          final indices = GalponesResolver.buildIndicesFromApiData(data);
          debugPrint(
            'ApiService: OK CENCOS=${indices.cencos.length}, '
            'granjas=${indices.galponesPorGranja.length}, '
            'galpones=${indices.totalGalpones} (desde ${url.path})',
          );
          if (indices.cencos.isEmpty) {
            lastError = 'Respuesta OK pero sin CENCOS (${url.path})';
            continue;
          }
          return {
            'success': true,
            'data': data,
            'indices': indices,
            'source': url.path,
          };
        }
        lastError = decoded is Map
            ? (decoded['message']?.toString() ?? 'Respuesta inválida')
            : 'Respuesta inválida';
        debugPrint('ApiService: $lastError en ${url.path}');
      } catch (e) {
        lastError = e.toString();
        debugPrint('ApiService: error downloadCencosGalpones ($url): $e');
      }
    }
    return {'success': false, 'message': lastError};
  }

  Future<Map<String, dynamic>> downloadAppInfo({
    String? versionWarningDesde,
  }) async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.seguimientoPath}/get_app_info_movil.php',
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
      if (decoded is Map && decoded['success'] == true && decoded['data'] is Map) {
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
        '${AppConstants.baseUrl}${AppConstants.seguimientoPath}/get_cencos_proyeccion_movil.php',
      ).replace(queryParameters: {
        'fecha': f,
        if (usuario.isNotEmpty) 'usuario': usuario,
      });
      debugPrint('ApiService: descargando proyección $url');
      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        final snippet = response.body.length > 200
            ? response.body.substring(0, 200)
            : response.body;
        debugPrint(
          'ApiService: HTTP ${response.statusCode} proyección: $snippet',
        );
        return {
          'success': false,
          'message': 'Error HTTP ${response.statusCode}',
        };
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['success'] == true) {
        _logProyeccionCampanias(decoded['data'], f);
        return {'success': true, 'data': decoded['data']};
      }
      return {
        'success': false,
        'message': decoded is Map ? decoded['message'] : 'Error',
      };
    } catch (e) {
      debugPrint('ApiService: error downloadProyeccion: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// [galpon] acepta uno o varios códigos separados por coma (promedio en servidor).
  Future<Map<String, dynamic>> getCampaniaInfo({
    required String granja,
    required String campania,
    String galpon = '',
    String? fecha,
  }) async {
    try {
      final f = fecha ?? DateTime.now().toIso8601String().substring(0, 10);
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.seguimientoPath}/get_campania_info_movil.php',
      ).replace(queryParameters: {
        'granja': granja,
        'campania': campania,
        'galpon': galpon,
        'fecha': f,
      });
      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 20));
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

  Future<File?> _compressImage(String path) async {
    try {
      final dir = await getTemporaryDirectory();
      final out = p.join(
        dir.path,
        'sc_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      final result = await FlutterImageCompress.compressAndGetFile(
        path,
        out,
        quality: 75,
        minWidth: 1280,
        minHeight: 1280,
      );
      if (result == null) return File(path);
      return File(result.path);
    } catch (_) {
      return File(path);
    }
  }

  Future<Map<String, dynamic>> uploadSeguimiento(
    Map<String, dynamic> record, {
    bool isUpdate = false,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    try {
      final endpoint = isUpdate
          ? 'actualizar_seguimiento_movil.php'
          : 'guardar_seguimiento_movil.php';
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.seguimientoPath}/$endpoint',
      );
      final request = http.MultipartRequest('POST', url);
      request.headers['Authorization'] = 'Bearer ${AppConstants.apiToken}';

      final usuario = await _getUsuarioSesion();
      final recordId = EvidenciaRecordId.of(record);
      if (recordId.isEmpty) {
        return {
          'success': false,
          'message': 'El registro no tiene id (UUID).',
        };
      }

      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final avisoDesde = AppVersionService.warningDesdeForApi(storage);
      final dataPayload = {
        'usuario': usuario.isNotEmpty ? usuario : record['usuario'],
        'granja': record['granja'],
        'campania': record['campania'],
        'galpon': record['galpon'] ?? '',
        'obs': record['obs'] ?? '',
        'agente_causal': record['agente_causal'] ?? '',
        'fecha': record['fecha'],
        'edad': record['edad'],
        'id': recordId,
        'app_version': AppConstants.appVersion,
        if (avisoDesde != null) 'version_warning_desde': avisoDesde,
      };

      request.fields['data'] = jsonEncode(dataPayload);

      final imagenes = record['imagenes'];
      if (imagenes is List) {
        var idx = 1;
        for (final img in imagenes) {
          if (idx > 3) break;
          final path = img is Map ? img['path']?.toString() : img.toString();
          if (path == null || path.isEmpty) continue;
          final file = File(path);
          if (!await file.exists()) continue;
          final compressed = await _compressImage(path);
          if (compressed == null) continue;
          request.files.add(await http.MultipartFile.fromPath(
            'imagen$idx',
            compressed.path,
          ));
          idx++;
        }
      }

      final streamed = await request.send().timeout(timeout);
      final body = await streamed.stream.bytesToString().timeout(timeout);
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['success'] == true) {
        return {
          'success': true,
          'data': decoded['data'],
          'message': decoded['message'],
        };
      }
      if (!isUpdate &&
          decoded is Map &&
          decoded['status'] == 409 &&
          decoded['data'] is Map) {
        final existingId = (decoded['data'] as Map)['id']?.toString() ?? recordId;
        final retryRecord = Map<String, dynamic>.from(record);
        retryRecord['id'] = existingId;
        retryRecord['guardado_backend'] = true;
        return uploadSeguimiento(retryRecord, isUpdate: true);
      }
      return {
        'success': false,
        'message': decoded is Map ? decoded['message'] : 'Error al subir',
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Diagnóstico: verifica si el backend envía fechas HC por campaña.
  static void _logProyeccionCampanias(dynamic data, String fecha) {
    if (data is! Map) return;
    final campMap = data['campanias_por_granja'];
    if (campMap is! Map || campMap.isEmpty) {
      debugPrint(
        'ApiService: proyección fecha=$fecha sin campanias_por_granja',
      );
      return;
    }
    var total = 0;
    var conInicio = 0;
    var conFin = 0;
    final multi = <String, List<String>>{};
    campMap.forEach((gk, raw) {
      if (raw is! List) return;
      final g3 = gk.toString();
      final lineas = <String>[];
      for (final item in raw) {
        if (item is! Map) continue;
        total++;
        final camp = item['campania']?.toString() ?? '?';
        final fi = item['fecha_inicio']?.toString().trim() ??
            item['fec_inicio']?.toString().trim() ??
            '';
        final ff = item['fecha_fin']?.toString().trim() ??
            item['fec_fin']?.toString().trim() ??
            '';
        if (fi.isNotEmpty && fi != '0000-00-00') conInicio++;
        if (ff.isNotEmpty && ff != '0000-00-00') conFin++;
        lineas.add('$camp[inicio=${fi.isEmpty ? "—" : fi}, fin=${ff.isEmpty ? "—" : ff}]');
      }
      if (lineas.length > 1) multi[g3] = lineas;
    });
    debugPrint(
      'ApiService: proyección fecha=$fecha campañas=$total '
      'con_fecha_inicio=$conInicio con_fecha_fin=$conFin',
    );
    final fuenteFechas = data['fuente_fechas']?.toString();
    if (fuenteFechas != null && fuenteFechas.isNotEmpty) {
      debugPrint('ApiService: fuente_fechas=$fuenteFechas');
    }
    if (total > 0 && conInicio == 0) {
      debugPrint(
        'ApiService: AVISO — el backend NO envía fecha_inicio/fecha_fin '
        '(esperado fuente_fechas=hc_cab vía get_cencos_proyeccion_movil.php).',
      );
    }
    if (multi.isNotEmpty) {
      debugPrint('ApiService: granjas con varias campañas (fecha=$fecha):');
      var n = 0;
      multi.forEach((g3, lineas) {
        if (n >= 8) return;
        debugPrint('  granja $g3: ${lineas.join(" | ")}');
        n++;
      });
      if (multi.length > 8) {
        debugPrint('  ... y ${multi.length - 8} granjas más');
      }
    }
  }
}
