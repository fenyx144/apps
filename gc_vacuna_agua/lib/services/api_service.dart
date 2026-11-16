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

  /// Catálogos propios de Vacuna al Agua (equipo de medición y turnos).
  Future<Map<String, dynamic>> downloadCatalogosVacuna() async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.seguimientoPath}'
        '${AppConstants.catalogosVacunaEndpoint}',
      );
      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        return {
          'success': false,
          'message': 'HTTP ${response.statusCode}',
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
        'message': decoded is Map ? decoded['message']?.toString() : 'Error',
      };
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
        debugPrint('ApiService: descargando CENCOS/galpones $url');
        final response = await http
            .get(url, headers: _headers)
            .timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) {
          lastError = 'HTTP ${response.statusCode} en ${url.path}';
          debugPrint('ApiService: $lastError');
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
        if (decoded is Map && decoded['success'] == true && decoded['data'] is Map) {
          final data = Map<String, dynamic>.from(decoded['data'] as Map);
          final indices = GalponesResolver.buildIndicesFromApiData(data);
          debugPrint(
            'ApiService: OK CENCOS=${indices.cencos.length}, '
            'granjas=${indices.galponesPorGranja.length} (desde ${url.path})',
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
        return {'success': false, 'message': 'Error HTTP ${response.statusCode}'};
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
        '${AppConstants.baseUrl}${AppConstants.catalogosPath}/get_cencos_proyeccion_movil.php',
      ).replace(queryParameters: {
        'fecha': f,
        if (usuario.isNotEmpty) 'usuario': usuario,
      });
      debugPrint('ApiService: descargando proyección $url');
      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        return {'success': false, 'message': 'Error HTTP ${response.statusCode}'};
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
      debugPrint('ApiService: error downloadProyeccion: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Nombre de un DNI consultado en la API Factiliza (vía backend).
  /// El token de Factiliza vive solo en el servidor, así que la app envía el
  /// documento y recibe el nombre ya armado.
  Future<Map<String, dynamic>> consultarDni(String dni) async {
    final limpio = dni.replaceAll(RegExp(r'\D'), '');
    if (limpio.length != 8) {
      return {'success': false, 'message': 'El DNI debe tener 8 dígitos.'};
    }
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.seguimientoPath}'
        '${AppConstants.consultarDniEndpoint}',
      );
      final response = await http
          .post(url, headers: _headers, body: jsonEncode({'dni': limpio}))
          // Corto a propósito: es una consulta puntual mientras el guardia
          // espera, y si no responde la app resuelve el nombre con el catálogo
          // local de usuarios.
          .timeout(const Duration(seconds: 8));
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['success'] == true) {
        final data = decoded['data'];
        return {
          'success': true,
          'dni': data is Map ? (data['dni'] ?? limpio).toString() : limpio,
          'nombre': data is Map ? (data['nombre'] ?? '').toString() : '',
        };
      }
      return {
        'success': false,
        'message': decoded is Map
            ? (decoded['message']?.toString() ?? 'No se pudo consultar el DNI.')
            : 'No se pudo consultar el DNI.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Error de conexión: $e'};
    }
  }

  /// Consulta informativa de la «Planificación de visitas» del portal web:
  /// ¿la placa o los DNIs estaban programados para esa granja en esa fecha?
  /// Devuelve el bloque `data` del servidor solo cuando la planificación está
  /// disponible (`disponible == true`). Ante cualquier otra cosa (sin red,
  /// tiempo agotado, token rechazado, tablas aún no creadas en el servidor)
  /// devuelve `null` y la pantalla se queda en estado neutro, sin avisos: esta
  /// consulta nunca debe estorbar ni impedir el registro.
  Future<Map<String, dynamic>?> consultarPlanificacion({
    required String fechaYmd,
    String granja = '',
    String placa = '',
    List<String> dnis = const [],
  }) async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.seguimientoPath}'
        '${AppConstants.consultarPlanificacionEndpoint}',
      );
      final response = await http
          .post(
            url,
            headers: _headers,
            body: jsonEncode({
              'fecha': fechaYmd,
              'granja': granja,
              'placa': placa,
              'dnis': dnis,
            }),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['success'] != true) return null;
      final data = decoded['data'];
      if (data is! Map || data['disponible'] != true) return null;
      return Map<String, dynamic>.from(data);
    } catch (_) {
      return null;
    }
  }

  /// Descarga la planificación de visitas (hoy y los próximos [dias]) para
  /// trabajar sin señal. Devuelve `data` solo si la planificación está
  /// disponible en el servidor; ante cualquier falla, `null`.
  Future<Map<String, dynamic>?> descargarPlanificacion({
    required String desde,
    int dias = 7,
  }) async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.seguimientoPath}'
        '${AppConstants.descargarPlanificacionEndpoint}',
      );
      final response = await http
          .post(
            url,
            headers: _headers,
            body: jsonEncode({'desde': desde, 'dias': dias}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['success'] != true) return null;
      final data = decoded['data'];
      if (data is! Map || data['disponible'] != true) return null;
      return Map<String, dynamic>.from(data);
    } catch (_) {
      return null;
    }
  }

  Future<File?> _compressImage(String path) async {
    try {
      final dir = await getTemporaryDirectory();
      final out = p.join(
        dir.path,
        'bio_${DateTime.now().millisecondsSinceEpoch}.jpg',
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

  /// Sube un registro de Vacuna al Agua (Decloración o Vacunación).
  /// El backend responde 409 cuando el grupo (fecha + granja/campaña + turno
  /// [+ filtro | referencia + proceso]) ya existe; en ese caso se reintenta
  /// automáticamente como actualización.
  Future<Map<String, dynamic>> uploadBioseguridad(
    Map<String, dynamic> record, {
    bool isUpdate = false,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    try {
      final endpoint = isUpdate
          ? AppConstants.actualizarVacunaEndpoint
          : AppConstants.guardarVacunaEndpoint;
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.seguimientoPath}$endpoint',
      );
      final request = http.MultipartRequest('POST', url);
      request.headers['Authorization'] = 'Bearer ${AppConstants.apiToken}';

      final usuario = await _getUsuarioSesion();
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final avisoDesde = AppVersionService.warningDesdeForApi(storage);
      final reporte = (record['reporte'] ?? '').toString();

      final dataPayload = <String, dynamic>{
        'reporte': reporte,
        // Llave del registro: el uuid local viaja como `id` para que el backend
        // deduplique por él (y para que rplanvisita/rcontrolingreso lo usen como
        // llave primaria).
        'id': EvidenciaRecordId.of(record),
        'usuario': usuario.isNotEmpty ? usuario : record['usuario'],
        'nombre_usuario': record['nombre_usuario'] ?? usuario,
        // Auditoría: quién capturó el dato en el equipo y cuándo.
        'usuarioRegistrador': record['usuario'] ?? usuario,
        'fechaHoraRegistro': record['created_at'] ??
            DateTime.now().toIso8601String(),
        'fecha': record['fecha'],
        'granja': record['granja'],
        'campania': record['campania'],
        'turno': record['turno'],
        'app_version': AppConstants.appVersion,
        'registro': record['registro'] ?? const <String, dynamic>{},
        if (avisoDesde != null) 'version_warning_desde': avisoDesde,
      };

      final registroMap = dataPayload['registro'];
      if (registroMap is Map) {
        if (reporte == 'decloracion') {
          dataPayload['galpones'] = registroMap['galpones'] ?? ['TODOS'];
          dataPayload['galpones_todos'] = registroMap['galpones_todos'] ?? true;
        } else if (reporte == 'vacunacion' &&
            registroMap['galpones'] is List) {
          dataPayload['galpones'] = registroMap['galpones'];
        }
      }

      request.fields['data'] = jsonEncode(dataPayload);

      // Cuántos archivos viajaron realmente: sirve para verificar contra las
      // imágenes que el backend confirma haber guardado.
      var enviadas = 0;
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
          enviadas++;
          request.files.add(
            await http.MultipartFile.fromPath('imagen$idx', compressed.path),
          );
          idx++;
        }
      }

      final streamed = await request.send().timeout(timeout);
      final body = await streamed.stream.bytesToString().timeout(timeout);
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['success'] == true) {
        final dataMap = decoded['data'] is Map
            ? Map<String, dynamic>.from(decoded['data'] as Map)
            : <String, dynamic>{};
        final yaExistia = dataMap['ya_existia'] == true ||
            dataMap['ya_existia']?.toString() == '1';
        final lista = dataMap['imagenes_lista'];
        final confirmadas = lista is List ? lista.length : 0;
        return {
          'success': true,
          'data': decoded['data'],
          'message': decoded['message'],
          'yaExistia': yaExistia,
          'imagenesEnviadas': enviadas,
          'imagenesConfirmadas': confirmadas,
          'imagenesOk': _imagenesOk(
            imagenesOk: dataMap['imagenes_ok'],
            tieneLista: lista is List,
            enviadas: enviadas,
            confirmadas: confirmadas,
          ),
        };
      }
      // Solo reintenta como actualización si este uuid ya se había enviado antes.
      // Un 409 por granja/campaña/fecha con uuid nuevo no debe pisar otro registro.
      if (!isUpdate &&
          decoded is Map &&
          decoded['status'] == 409 &&
          record['guardado_backend'] == true) {
        final retryRecord = Map<String, dynamic>.from(record);
        return uploadBioseguridad(retryRecord, isUpdate: true);
      }
      return {
        'success': false,
        'message': decoded is Map ? decoded['message'] : 'Error al subir',
        'imagenesOk': false,
      };
    } catch (e) {
      return {'success': false, 'message': e.toString(), 'imagenesOk': false};
    }
  }

  /// Verifica que el backend confirmó las imágenes locales que se enviaron.
  /// `imagenes_ok` manda, también cuando el uuid ya estaba insertado: esa
  /// reenvío repara archivos que no habían llegado. Sin esa señal, un registro
  /// sin imágenes que enviar queda completo; si se enviaron, se compara la
  /// lista confirmada (el backend renombra los archivos).
  static bool _imagenesOk({
    required dynamic imagenesOk,
    required bool tieneLista,
    required int enviadas,
    required int confirmadas,
  }) {
    if (imagenesOk == true || imagenesOk?.toString() == '1') return true;
    if (imagenesOk == false || imagenesOk?.toString() == '0') return false;
    if (enviadas == 0 || !tieneLista) return true;
    return confirmadas >= enviadas;
  }

  /// ¿La subida quedó completa (registro en el servidor con sus imágenes)?
  static bool subidaCompleta(Map<String, dynamic> result) =>
      result['success'] == true && result['imagenesOk'] == true;

  /// Compatibilidad con el nombre previo.
  Future<Map<String, dynamic>> uploadSeguimiento(
    Map<String, dynamic> record, {
    bool isUpdate = false,
    Duration timeout = const Duration(minutes: 3),
  }) =>
      uploadBioseguridad(record, isUpdate: isUpdate, timeout: timeout);

  /// Id del registro (UUID local) usado para deduplicar en la app.
  static String recordId(Map<String, dynamic> record) =>
      EvidenciaRecordId.of(record);

  /// Laboratorios habilitados en configuración web (catálogo completo).
  Future<Map<String, dynamic>> downloadProveedoresVacuna() async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.seguimientoPath}'
        '${AppConstants.proveedoresVacunaEndpoint}',
      );
      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['success'] == true) {
        final data = decoded['data'];
        final rawItems = data is Map ? data['items'] : null;
        final items = <Map<String, String>>[];
        if (rawItems is List) {
          for (final row in rawItems) {
            if (row is! Map) continue;
            final ruc = (row['ruc'] ?? '').toString().replaceAll(
              RegExp(r'\D'),
              '',
            );
            final nombre = (row['razonsocial'] ?? row['nombre'] ?? '')
                .toString()
                .trim();
            if (ruc.length != 11 || nombre.isEmpty) continue;
            items.add({'ruc': ruc, 'razonsocial': nombre});
          }
        }
        return {'success': true, 'items': items};
      }
      return {
        'success': false,
        'message': decoded is Map
            ? (decoded['message']?.toString() ??
                  'No se pudo descargar laboratorios.')
            : 'No se pudo descargar laboratorios.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error de conexión: $e',
      };
    }
  }

  /// Maestro `ccte`: RUC y razón social (búsqueda parcial en servidor).
  Future<Map<String, dynamic>> buscarProveedorCcte(
    String q, {
    int limite = 25,
    /// Sin filtro del catálogo web: todo el maestro ccte (fallback en línea).
    bool fallbackCcte = false,
  }) async {
    final texto = q.trim();
    if (texto.isEmpty) {
      return {'success': false, 'message': 'Escriba RUC o razón social.'};
    }
    final propio = await _buscarProveedorCcteEn(
      '${AppConstants.baseUrl}${AppConstants.seguimientoPath}'
      '${AppConstants.buscarProveedorCcteEndpoint}',
      texto,
      limite,
      fallbackCcte: fallbackCcte,
    );
    // En producción el script de vacuna todavía no está subido (404). Bioseguridad
    // ya responde la misma consulta de ccte en ese servidor.
    if (propio['errorCode'] == 'NOT_FOUND') {
      debugPrint(
        '[laboratorio/ccte] sin script de vacuna, consulta bioseguridad',
      );
      return _buscarProveedorCcteEn(
        '${AppConstants.baseUrl}/bioseguridad'
        '/buscar_proveedor_ccte_bioseguridad_movil.php',
        texto,
        limite,
        fallbackCcte: fallbackCcte,
      );
    }
    return propio;
  }

  Future<Map<String, dynamic>> _buscarProveedorCcteEn(
    String urlTexto,
    String texto,
    int limite, {
    bool fallbackCcte = false,
  }) async {
    try {
      final url = Uri.parse(urlTexto);
      debugPrint('[laboratorio/ccte] POST $url q="$texto"');
      final response = await http
          .post(
            url,
            headers: _headers,
            body: jsonEncode({
              'q': texto,
              'limite': limite,
              if (fallbackCcte) 'fallback': true,
            }),
          )
          .timeout(const Duration(seconds: 10));
      final body = response.body;
      final bodyLog = body.length > 800 ? '${body.substring(0, 800)}…' : body;
      debugPrint('[laboratorio/ccte] HTTP ${response.statusCode}: $bodyLog');
      if (response.statusCode != 200) {
        return {
          'success': false,
          'message': 'HTTP ${response.statusCode} al buscar.',
          'errorCode': response.statusCode == 404 ? 'NOT_FOUND' : null,
        };
      }
      final dynamic decodedRaw;
      try {
        decodedRaw = jsonDecode(body);
      } catch (_) {
        return {
          'success': false,
          'message': 'Respuesta no JSON del servidor.',
        };
      }
      if (decodedRaw is Map && decodedRaw['success'] == true) {
        final data = decodedRaw['data'];
        final rawItems = data is Map
            ? (data['items'] ?? decodedRaw['items'])
            : decodedRaw['items'];
        final items = <Map<String, String>>[];
        if (rawItems is List) {
          for (final row in rawItems) {
            if (row is! Map) continue;
            final ruc = (row['ruc'] ?? '').toString().replaceAll(
              RegExp(r'\D'),
              '',
            );
            final nombre = (row['razonsocial'] ?? row['nombre'] ?? '')
                .toString()
                .trim();
            if (ruc.length != 11 || nombre.isEmpty) continue;
            items.add({'ruc': ruc, 'razonsocial': nombre});
          }
        }
        debugPrint('[laboratorio/ccte] ${items.length} coincidencia(s)');
        return {'success': true, 'items': items};
      }
      return {
        'success': false,
        'message': decodedRaw is Map
            ? (decodedRaw['message']?.toString() ?? 'Sin resultados')
            : 'Respuesta inválida',
      };
    } catch (e) {
      debugPrint('[laboratorio/ccte] q="$texto" → error: $e');
      return {
        'success': false,
        'message': 'Sin conexión.',
        'errorCode': 'CONNECTIVITY',
      };
    }
  }
}
