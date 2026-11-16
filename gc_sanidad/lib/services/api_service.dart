import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../controllers/registro_envio_muestra_controller.dart';
import '../utils/constants.dart';

class ApiService {
  // Headers comunes
  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${AppConstants.apiToken}',
    'Content-Type': 'application/json; charset=utf-8',
  };

  // Login - CORREGIDO
  Future<Map<String, dynamic>> login({
    required String usuario,
    required String password,
    required String androidId,
    required String version,
  }) async {
    try {
      final passwordBase64 = base64Encode(utf8.encode(password));

      final url = Uri.parse(
        '${AppConstants.baseUrlSanidad}${AppConstants.loginEndpoint}',
      );

      final body = jsonEncode({
        'usuario': usuario,
        'password': passwordBase64,
        'android': androidId,
        'version': version,
        'app': AppConstants.appName,
      });

      final response = await http
          .post(url, headers: _headers, body: body)
          .timeout(const Duration(seconds: 30));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      print(response);
      return {
        'success': data['success'] ?? false,
        'status': data['status'],
        'message': data['message'] ?? 'Sin mensaje',
        'errorCode': data['errorCode'],
        'data': data['data'],
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error de conexión: ${e.toString()}',
        'errorCode': null,
      };
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
        '${AppConstants.baseUrlSanidad}${AppConstants.registerDeviceEndpoint}',
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
          .timeout(const Duration(seconds: 30));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      debugPrint(response.toString());
      return {
        'success': data['success'] ?? false,
        'status': data['status'],
        'message': data['message'] ?? 'Sin mensaje',
        'errorCode': data['errorCode'],
        'data': data['data'],
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error de conexión: ${e.toString()}',
        'errorCode': null,
      };
    }
  }

  Future<Map<String, dynamic>> downloadCatalogos({List<String>? tablas}) async {
    try {
      Uri url;
      if (tablas != null && tablas.isNotEmpty) {
        // Construir URL con parámetro 'tablas=mercados,proveedores,...'
        final tablasParam = tablas.join(',');
        url = Uri.parse(
          '${AppConstants.baseUrlSanidad}${AppConstants.downloadEndpoint}',
        ).replace(queryParameters: {'tablas': tablasParam});
      } else {
        url = Uri.parse(
          '${AppConstants.baseUrlSanidad}${AppConstants.downloadEndpoint}',
        );
      }

      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 30));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'data': data['data'],
          'message': data['message'],
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Error al descargar catálogos',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error de conexión: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> uploadData(Map<String, dynamic> data) async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrlSanidad}${AppConstants.uploadEndpoint}',
      );

      final body = jsonEncode(data);

      final response = await http
          .post(url, headers: _headers, body: body)
          .timeout(const Duration(seconds: 60));

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData?['success'] == true) {
        return {
          'success': true,
          'message': responseData['message'] ?? 'Éxito',
          'detalle':
              responseData['detalle'] ??
              {}, // ¡Esto es clave para los códigos!
        };
      } else {
        return {
          'success': false,
          'message': responseData?['message'] ?? 'Error en el servidor',
          'detalle': null,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error de conexión: ${e.toString()}',
        'detalle': null,
      };
    }
  }

  Future<Map<String, dynamic>> uploadMultiple(
    Map<String, dynamic> payload,
  ) async {
    final url = Uri.parse(
      '${AppConstants.baseUrlSanidad}${AppConstants.uploadEndpoint}',
    );
    final response = await http
        .post(url, headers: _headers, body: jsonEncode(payload))
        .timeout(const Duration(seconds: 60));
    debugPrint(response.statusCode.toString());
    debugPrint(response.body);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      print('aqui');
      throw Exception('Error HTTP ${response.statusCode}: ${response.body}');
    }
  }
  // services/api_service.dart

  Future<Map<String, dynamic>> getConfiguracionMuestra(
    String tipoMuestraCodigo,
  ) async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrlSanidad}/get_config_muestra.php?tipo_muestra_codigo=$tipoMuestraCodigo',
      );

      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 30));
      print('response: $response');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('data: $data');
        if (data['error'] != null) {
          throw Exception(data['error']);
        }
        return {'success': true, 'data': data};
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> getOrigenAves(String tipo) async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrlSanidad}/get_origen_aves.php?tipo=${Uri.encodeComponent(tipo)}',
      );

      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data['error'] != null) {
          throw Exception(data['error']);
        }
        if (data is List) {
          return {
            'success': true,
            'data': data.cast<Map<String, dynamic>>(),
          };
        }
        if (data is Map<String, dynamic> && data['data'] is List) {
          return {
            'success': true,
            'data': (data['data'] as List).cast<Map<String, dynamic>>(),
          };
        }
        return {'success': true, 'data': <Map<String, dynamic>>[]};
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> buscarGriDisponibles({
    required String granja,
    required String campania,
    required String galpon,
    double? cantidad,
    double? cantMachos,
    double? cantHembras,
    String modulo = 'MUESTRA',
  }) async {
    try {
      final query = {
        'granja': granja,
        'campania': campania,
        'galpon': galpon,
        'modulo': modulo,
        if (cantidad != null) 'cantidad': cantidad.toString(),
        if (cantMachos != null) 'cantMachos': cantMachos.toString(),
        if (cantHembras != null) 'cantHembras': cantHembras.toString(),
      };
      final url = Uri.parse(
        '${AppConstants.baseUrlSanidad}/buscar_gri_disponibles_movil.php',
      ).replace(queryParameters: query);
      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'success': false, 'items': []};
    } catch (e) {
      return {'success': false, 'items': [], 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> guardarMuestra(
    final Map<String, dynamic> formData,
  ) async {
    try {
      debugPrint('formData: $formData.');
      final url = Uri.parse(
        '${AppConstants.baseUrlSanidad}/guardar_muestra.php',
      );
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode(formData),
      );
      debugPrint('response: ${response.body}.');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        // Error del servidor (500, 400, etc.) no es offline
        return {'error': 'HTTP ${response.statusCode}'};
      }
    } catch (e) {
      return {'error_offline': true, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> reserveCodigoEnvio(String usuarioCodigo) async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrlSanidad}/reserve_codigo_envio.php',
      );

      // Añadir X-User-ID al header
      final headers = {
        ..._headers, // Incluye 'Authorization: Bearer ...'
        'X-User-ID': usuarioCodigo,
      };
      print('headers: $headers');
      final response = await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data.containsKey('error')) {
          return {'success': false, 'message': data['error'] as String};
        }
        return {'success': true, 'data': data};
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error de conexión: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> reserveCodigoEnvio2(String usuarioCodigo) async {
    try {
      // Añadimos el usuario_id como parámetro en la URL
      final url = Uri.parse(
        '${AppConstants.baseUrlSanidad}/reserve_codigo_envio.php', // ?usuario_id=${Uri.encodeComponent(usuarioCodigo)}
      );

      print('Reservando código para usuario: $usuarioCodigo');
      print('URL: $url');

      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 45)); // un poco más de margen

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        // Si la API devuelve un campo 'error', lo tratamos como fallo
        if (data.containsKey('error')) {
          return {'success': false, 'message': data['error'] as String};
        }

        // Si todo va bien, devolvemos el resultado
        return {'success': true, 'data': data};
      } else {
        // Error HTTP explícito
        return {
          'success': false,
          'message': 'Error HTTP ${response.statusCode}: ${response.body}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error de conexión o timeout: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> getWithToken(String url) async {
    try {
      final headers = {
        'Authorization': 'Bearer ${AppConstants.apiToken}',
        'Content-Type': 'application/json; charset=utf-8',
      };
      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data;
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  Future<Uint8List?> downloadPdf(
    String url,
    Map<String, String> extraHeaders,
  ) async {
    try {
      final headers = {..._headers, ...extraHeaders};
      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        print(
          'Error al descargar PDF: ${response.statusCode} - ${response.body}',
        );
        return null;
      }
    } catch (e) {
      print('Excepción al descargar PDF: $e');
      return null;
    }
  }

  Future<Uint8List?> downloadPreviewPdf(Map<String, String> fields) async {
    try {
      final uri = Uri.parse(
        '${AppConstants.baseUrlSanidad}/generar_preview_pdf.php',
      );
      final headers = {
        'Authorization': 'Bearer ${AppConstants.apiToken}',
        'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
      };
      final response = await http
          .post(uri, headers: headers, body: fields)
          .timeout(const Duration(seconds: 90));

      final contentType = response.headers['content-type'] ?? '';
      if (response.statusCode == 200 &&
          (contentType.contains('pdf') ||
              response.bodyBytes.length > 4 &&
                  String.fromCharCodes(response.bodyBytes.take(4)) == '%PDF')) {
        return response.bodyBytes;
      }

      debugPrint(
        'Preview PDF error ${response.statusCode}: ${response.body.substring(0, response.body.length.clamp(0, 300))}',
      );
      return null;
    } catch (e) {
      debugPrint('Excepción preview PDF: $e');
      return null;
    }
  }
}
