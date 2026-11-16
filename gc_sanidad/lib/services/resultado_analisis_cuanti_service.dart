// services/resultado_analisis_cuanti_service.dart
/*import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/resultado_analisis_model.dart';
import '../utils/constants.dart';

class ResultadoAnalisisCuantiService {
  static Future<Map<String, dynamic>> fetchGrupos({
    int page = 1,
    String estado = 'todos',
    String query = '',
  }) async {
    final url = Uri.parse('${AppConstants.baseUrlSanidad}/solicitudes_muestras_estado_cuanti.php')
        .replace(queryParameters: {
      'page': page.toString(),
      'estado': estado,
      'q': query,
    });

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
        };
      }
    }
    throw Exception('Error al cargar solicitudes cuantitativas');
  }
}*/
