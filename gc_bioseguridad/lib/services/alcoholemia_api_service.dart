import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/constants.dart';
import 'app_http_client.dart';

/// Envío de anomalías AGC ligadas a ingreso (alcoholemia / artículos).
class AlcoholemiaApiService {
  AlcoholemiaApiService({http.Client? client})
      : _client = client ?? createAppHttpClient();

  final http.Client _client;

  Uri _url(String path) => Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.seguimientoPath}$path',
      );

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${AppConstants.apiToken}',
        'Content-Type': 'application/json; charset=utf-8',
      };

  Future<bool> guardarAlcoholemiaAgc(Map<String, dynamic> body) async {
    final res = await _client
        .post(
          _url('/guardar_alcoholemia_agc_movil.php'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return false;
    final j = jsonDecode(res.body);
    return j is Map && j['success'] == true;
  }

  Future<({bool ok, String? message})> guardarArticuloAnomalia({
    required String granja,
    required String campania,
    required String fecha,
    required String dni,
    required String nombre,
    required String articulo,
    required String accion,
    String? anomalia,
    String? agenteCausal,
    String? efecto,
    String? fotoPath,
    String usuario = '',
  }) async {
    final body = {
      'granja': granja,
      'campania': campania,
      'fecha': fecha,
      'dni': dni,
      'nombre': nombre,
      'articulo': articulo,
      'accion': accion,
      if (usuario.trim().isNotEmpty) 'usuario': usuario.trim(),
      if (anomalia != null && anomalia.trim().isNotEmpty) 'anomalia': anomalia,
      if (agenteCausal != null && agenteCausal.trim().isNotEmpty)
        'agente_causal': agenteCausal,
      if (efecto != null && efecto.trim().isNotEmpty) 'efecto': efecto,
      if (fotoPath != null) 'foto_path_local': fotoPath,
    };
    try {
      final res = await _client
          .post(
            _url('/guardar_articulo_agc_movil.php'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 25));
      Map<String, dynamic>? j;
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) {
          j = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
      if (res.statusCode == 200 && j?['success'] == true) {
        return (ok: true, message: null);
      }
      final msg = j?['message']?.toString().trim();
      if (msg != null && msg.isNotEmpty) {
        return (ok: false, message: msg);
      }
      if (res.statusCode == 404) {
        return (
          ok: false,
          message: 'Servidor sin guardar_articulo_agc_movil.php (actualice PHP).',
        );
      }
      return (
        ok: false,
        message: 'Error HTTP ${res.statusCode} al registrar anomalía.',
      );
    } catch (e) {
      return (ok: false, message: 'Sin conexión al registrar anomalía AGC.');
    }
  }
}