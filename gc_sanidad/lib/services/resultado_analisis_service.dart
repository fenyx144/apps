import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:gc_puesto_mercado_tienda/models/resultado_solicitud.dart';
import 'package:http/http.dart' as http;
import '../models/resultado_analisis_model.dart';
import '../utils/constants.dart';

class ResultadoAnalisisService {
  // === 1. Cargar la lista principal de grupos (sin cambios) ===
  static Future<Map<String, dynamic>> fetchGrupos({
    int page = 1,
    String estado = 'todos',
    String query = '',
  }) async {
    final url =
        Uri.parse(
          '${AppConstants.baseUrlSanidad}/solicitudes_muestras_estado.php',
        ).replace(
          queryParameters: {
            'page': page.toString(),
            'estado': estado,
            'q': query,
          },
        );

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      if (data['success']) {
        final grupos = (data['data'] as List)
            .map((item) => EnvioGrupo.fromJson(item))
            .toList();

        return {
          'grupos': grupos,
          'totalPages': data['total_pages'],
          'currentPage': data['current_page'],
          'totalRecords': data['total_records'],
        };
      }
    }
    throw Exception('Error al cargar solicitudes');
  }

  // === 2. Cargar análisis cualitativos ===
  static Future<List<ResultadoAnalisisCuali>> fetchAnalisisCuali({
    required String codEnvio,
    required int posSolicitud,
  }) async {
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
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success']) {
        return (data['data'] as List?)
                ?.map((item) => ResultadoAnalisisCuali.fromJson(item))
                .toList() ??
            [];
      }
    }
    throw Exception('Error al cargar análisis cualitativos');
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

  // === 3. Cargar documentos separados por tipo ===
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

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success']) {
        List<DocumentoPdf> _parseList(dynamic list) {
          if (list == null) return [];
          return (list as List)
              .map(
                (e) => DocumentoPdf(
                  nombre: e['nombre'] as String,
                  ruta: e['ruta'] as String,
                ),
              )
              .toList();
        }

        return {
          'cualitativos': _parseList(data['cualitativos']),
          'cuantitativos': _parseList(data['cuantitativos']),
        };
      }
    }
    throw Exception('Error al cargar documentos');
  }
}
