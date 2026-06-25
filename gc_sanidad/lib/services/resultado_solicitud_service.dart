import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/resultado_solicitud.dart';
import '../utils/constants.dart';

class ResultadoSolicitudService {
  static Future<List<ResultadoAnalisisCuali>> fetchAnalisisCuali({
    required String codEnvio,
    required int posSolicitud,
  }) async {
    print('codEnvio: $codEnvio');
    print('posSolicitud: $posSolicitud');
    final url =
        Uri.parse(
          '${AppConstants.baseUrlSanidad}/obtener_resultados_analisis_cuali.php',
        ).replace(
          queryParameters: {
            'codEnvio': codEnvio,
            'posSolicitud': posSolicitud.toString(),
          },
        );

    final response = await http.get(url);
    print('response: ${response.statusCode}');
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      print('data: $data');
      if (data['success']) {
        return (data['data'] as List)
            .map((item) => ResultadoAnalisisCuali.fromJson(item))
            .toList();
      }
    }
    throw Exception('Error al cargar análisis');
  }

  static Future<List<DocumentoPdf>> fetchDocumentos({
    required String codEnvio,
    required int posSolicitud,
  }) async {
    final url =
        Uri.parse(
          '${AppConstants.baseUrlSanidad}/obtener_documentos.php',
        ).replace(
          queryParameters: {
            'codEnvio': codEnvio,
            'posSolicitud': posSolicitud.toString(),
          },
        );

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      print('data: $data');
      if (data['success']) {
        return (data['data'] as List)
            .map((item) => DocumentoPdf.fromJson(item))
            .toList();
      }
    }
    throw Exception('Error al cargar documentos');
  }
static Future<List<ResultadoAnalisisCuanti>> fetchAnalisisCuanti({
    required String codEnvio,
    required int posSolicitud,
  }) async {
    final url =
        Uri.parse(
          '${AppConstants.baseUrlSanidad}/obtener_resultados_analisis_cuanti.php',
        ).replace(
          queryParameters: {
            'codEnvio': codEnvio,
            'posSolicitud': posSolicitud.toString(),
          },
        );

    final response = await http.get(url);
    debugPrint(response.body.toString());
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success']) {
        return (data['data'] as List?)
                ?.map((item) => ResultadoAnalisisCuanti.fromJson(item))
                .toList() ??
            [];
      }
    }
    throw Exception('Error al cargar análisis cuantitativos');
  }
  // services/resultado_solicitud_service.dart
  static Future<Map<String, List<DocumentoPdf>>> fetchDocumentosSeparados({
    required String codEnvio,
    required int posSolicitud,
  }) async {
    final url =
        Uri.parse(
          '${AppConstants.baseUrlSanidad}/obtener_documentos.php',
        ).replace(
          queryParameters: {
            'codEnvio': codEnvio,
            'posSolicitud': posSolicitud.toString(),
          },
        );

    final response = await http.get(
      url,
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw Exception('Error al cargar documentos');
    }

    final data = jsonDecode(response.body);
    if (!data['success'])
      throw Exception(data['message'] ?? 'Error desconocido');

    List<DocumentoPdf> parseList(List<dynamic>? list) {
      if (list == null) return [];
      return list
          .map(
            (e) => DocumentoPdf(
              nombre: e['nombre'] as String,
              ruta: e['ruta'] as String,
            ),
          )
          .toList();
    }

    return {
      'cualitativos': parseList(data['cualitativos']),
      'cuantitativos': parseList(data['cuantitativos']),
    };
  }
}
