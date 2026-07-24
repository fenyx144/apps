import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
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
      final body = jsonEncode({
        'usuario': usuario,
        'password': base64Encode(utf8.encode(password)),
        'android': androidId,
        'version': version,
        'app': AppConstants.appName,
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
      final body = jsonEncode({
        'android': androidId,
        'fabricante': fabricante,
        'familia': familia,
        'modelo': modelo,
        'descripcion': descripcion,
        'app': AppConstants.appName,
      });
      final response = await http
          .post(url, headers: _headers, body: body)
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': data['success'] ?? false,
        'message': data['message'] ?? '',
        'errorCode': data['errorCode'],
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
          .timeout(const Duration(seconds: 30));
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
    try {
      final usuario = await _getUsuarioSesion();
      final baseUri = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.seguimientoPath}/get_cencos_galpones_movil.php',
      );
      final url = usuario.isNotEmpty
          ? baseUri.replace(queryParameters: {'usuario': usuario})
          : baseUri;
      debugPrint('ApiService: descargando CENCOS/galpones $url');
      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        debugPrint('ApiService: HTTP ${response.statusCode} en get_cencos_galpones_movil');
        return {
          'success': false,
          'message': 'Error HTTP ${response.statusCode}',
        };
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['success'] == true && decoded['data'] is Map) {
        final data = Map<String, dynamic>.from(decoded['data'] as Map);
        final indices = GalponesResolver.buildIndicesFromApiData(data);
        debugPrint(
          'ApiService: CENCOS=${indices.cencos.length}, '
          'granjas=${indices.galponesPorGranja.length}, '
          'galpones=${indices.totalGalpones}',
        );
        return {
          'success': true,
          'data': data,
          'indices': indices,
        };
      }
      return {
        'success': false,
        'message': decoded is Map ? (decoded['message'] ?? 'Error') : 'Error',
      };
    } catch (e) {
      debugPrint('ApiService: error downloadCencosGalpones: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> downloadProyeccion({String? fecha}) async {
    try {
      final usuario = await _getUsuarioSesion();
      final f = fecha ?? DateTime.now().toIso8601String().substring(0, 10);
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.seguimientoPath}/get_cencos_proyeccion_movil.php?fecha=$f&usuario=$usuario',
      );
      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 60));
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

      final dataPayload = {
        'usuario': usuario.isNotEmpty ? usuario : record['usuario'],
        'granja': record['granja'],
        'campania': record['campania'],
        'galpon': record['galpon'] ?? '',
        'obs': record['obs'] ?? '',
        'fecha': record['fecha'],
        'edad': record['edad'],
        'id': recordId,
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

      final streamed = await request.send().timeout(const Duration(minutes: 3));
      final body = await streamed.stream.bytesToString();
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
}
