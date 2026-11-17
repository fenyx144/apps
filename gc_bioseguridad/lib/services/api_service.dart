import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import '../utils/documento_persona.dart';
import 'app_version_service.dart';
import 'storage_service.dart';
import '../utils/galpones_resolver.dart';
import '../utils/record_id.dart';
import 'app_http_client.dart';

class ApiService {
  ApiService({http.Client? client}) : _http = client ?? createAppHttpClient();

  final http.Client _http;

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
      final response = await _http
          .post(url, headers: _headers, body: body)
          .timeout(const Duration(seconds: 8));
      if (kDebugMode) {
        debugPrint(
          '[login] ${response.statusCode} ${url.path}\n${response.body}',
        );
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': data['success'] ?? false,
        'message': data['message'] ?? '',
        'errorCode': data['errorCode'],
        'data': data['data'],
      };
    } catch (e, st) {
      // Detalle real solo en consola; al usuario se le muestra 'Sin conexion'
      // si tampoco hay catalogo offline.
      debugPrint('[login] error al contactar servidor: $e\n$st');
      final err = e.toString();
      if (err.contains('HandshakeException') || err.contains('CERTIFICATE_VERIFY_FAILED')) {
        return {
          'success': false,
          'message': 'Certificado HTTPS del servidor no confiable. Reinicie la app tras actualizar.',
          'errorCode': 'TLS_ERROR',
        };
      }
      return {
        'success': false,
        'message': 'Error de conexión',
        'errorCode': 'CONNECTIVITY',
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
      final response = await _http
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
      final response = await _http
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

  /// Catálogos propios de bioseguridad (referencias, tipos, procesos, anomalías,
  /// métricas del cerco, depredadores).
  Future<Map<String, dynamic>> downloadCatalogosBioseguridad() async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.seguimientoPath}'
        '${AppConstants.catalogosBioEndpoint}',
      );
      final response = await _http
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
        final response = await _http
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
      final response = await _http
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
      final response = await _http
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
  Future<Map<String, dynamic>> consultarDni(String dni) =>
      consultarDocumento(dni);

  /// DNI (8 dígitos) o carné de extranjería (CEE) vía Factiliza en el servidor.
  Future<Map<String, dynamic>> consultarDocumento(String documento) async {
    final parsed = DocumentoPersona.parse(documento);
    if (parsed == null) {
      return {
        'success': false,
        'message': 'Ingrese un DNI de 8 dígitos o un carné de extranjería válido.',
      };
    }
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.seguimientoPath}'
        '${AppConstants.consultarDniEndpoint}',
      );
      final response = await _http
          .post(
            url,
            headers: _headers,
            body: jsonEncode({'documento': parsed.id, 'dni': parsed.id}),
          )
          // Corto a propósito: es una consulta puntual mientras el guardia
          // espera, y si no responde la app resuelve el nombre con el catálogo
          // local de usuarios.
          .timeout(const Duration(seconds: 8));
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['success'] == true) {
        final data = decoded['data'];
        return {
          'success': true,
          'dni': data is Map
              ? (data['documento'] ?? data['dni'] ?? parsed.id).toString()
              : parsed.id,
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

  /// Razón social de un RUC consultada en la API Factiliza (vía backend).
  /// Es la misma consulta que hace la web al elegir un proveedor: la app manda
  /// los 11 dígitos y recibe la razón social ya resuelta, sin conocer el token.
  Future<Map<String, dynamic>> consultarRuc(String ruc) async {
    final limpio = ruc.replaceAll(RegExp(r'\D'), '');
    if (limpio.length != 11) {
      return {'success': false, 'message': 'El RUC debe tener 11 dígitos.'};
    }
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.seguimientoPath}'
        '${AppConstants.consultarRucEndpoint}',
      );
      final response = await _http
          .post(url, headers: _headers, body: jsonEncode({'ruc': limpio}))
          // Corto a propósito: es una consulta puntual mientras el guardia
          // espera, y sin respuesta el RUC se acepta igual, sin razón social.
          .timeout(const Duration(seconds: 8));
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['success'] == true) {
        final data = decoded['data'];
        return {
          'success': true,
          'ruc': data is Map ? (data['ruc'] ?? limpio).toString() : limpio,
          'razonsocial': data is Map
              ? (data['razonsocial'] ?? '').toString()
              : '',
        };
      }
      return {
        'success': false,
        'message': decoded is Map
            ? (decoded['message']?.toString() ?? 'No se pudo consultar el RUC.')
            : 'No se pudo consultar el RUC.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Error de conexión: $e'};
    }
  }

  /// Catálogo compacto: proveedores con usuario de planificación web.
  Future<Map<String, dynamic>> downloadProveedoresPlanificacion() async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.seguimientoPath}'
        '${AppConstants.proveedoresPlanificacionEndpoint}',
      );
      final response = await _http
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
            if (ruc.length != 11 && nombre.isEmpty) continue;
            items.add({'ruc': ruc, 'razonsocial': nombre});
          }
        }
        return {'success': true, 'items': items};
      }
      return {
        'success': false,
        'message': decoded is Map
            ? (decoded['message']?.toString() ??
                  'No se pudo descargar proveedores.')
            : 'No se pudo descargar proveedores.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Sin conexión. Inténtelo más tarde.',
        'errorCode': 'CONNECTIVITY',
      };
    }
  }

  /// Proveedores del maestro `ccte` (codigo = RUC de 11 dígitos, nombre = razón
  /// social). Búsqueda parcial en servidor; no descarga los ~12k registros.
  Future<Map<String, dynamic>> buscarProveedorCcte(
    String q, {
    int limite = 25,
  }) async {
    final texto = q.trim();
    if (texto.isEmpty) {
      return {'success': false, 'message': 'Escriba RUC o razón social.'};
    }
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.seguimientoPath}'
        '${AppConstants.buscarProveedorCcteEndpoint}',
      );
      debugPrint('[proveedor/ccte] POST $url q="$texto"');
      final response = await _http
          .post(
            url,
            headers: _headers,
            body: jsonEncode({'q': texto, 'limite': limite}),
          )
          .timeout(const Duration(seconds: 10));
      final body = response.body;
      final bodyLog = body.length > 800 ? '${body.substring(0, 800)}…' : body;
      debugPrint(
        '[proveedor/ccte] HTTP ${response.statusCode}: $bodyLog',
      );
      if (response.statusCode == 404) {
        return {
          'success': false,
          'message':
              'El servidor no tiene el archivo de búsqueda ccte (HTTP 404). '
              'Suba buscar_proveedor_ccte_bioseguridad_movil.php a '
              'sanidad/flutter/bioseguridad/ en producción.',
        };
      }
      if (response.statusCode != 200) {
        return {
          'success': false,
          'message': 'HTTP ${response.statusCode} al buscar proveedor.',
        };
      }
      final dynamic decodedRaw;
      try {
        decodedRaw = jsonDecode(body);
      } catch (_) {
        return {
          'success': false,
          'message':
              'Respuesta no JSON del servidor (¿ruta incorrecta o error PHP?).',
        };
      }
      final decoded = decodedRaw;
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
                  'No se pudo buscar el proveedor.')
            : 'No se pudo buscar el proveedor.',
      };
    } catch (e) {
      debugPrint('[proveedor/ccte] q="$texto" → error: $e');
      return {
        'success': false,
        'message': 'Sin conexión. Inténtelo más tarde.',
        'errorCode': 'CONNECTIVITY',
      };
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
      final response = await _http
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

  /// Consulta informativa del «Estatus Sanitario Granja» del portal web: ¿la
  /// granja del registro está en situación especial y alguno de los DNIs viene
  /// de otra granja que sí lo está?
  /// Devuelve el bloque `data` solo cuando el servidor tiene las tablas del
  /// estatus (`disponible == true`). Ante cualquier otra cosa (sin red, tiempo
  /// agotado, token rechazado, tablas aún no creadas) devuelve `null` y la
  /// pantalla se queda sin etiquetas: esta consulta nunca impide el registro.
  Future<Map<String, dynamic>?> consultarEstatusSanitario({
    required String fechaYmd,
    String granja = '',
    String campania = '',
    List<String> dnis = const [],
    List<String> placas = const [],
  }) async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.seguimientoPath}'
        '${AppConstants.consultarEstatusSanitarioEndpoint}',
      );
      final response = await _http
          .post(
            url,
            headers: _headers,
            body: jsonEncode({
              'fecha': fechaYmd,
              'granja': granja,
              'campania': campania,
              'dnis': dnis,
              'placas': placas,
            }),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['success'] != true) return null;
      final data = decoded['data'];
      if (data is! Map) return null;
      return Map<String, dynamic>.from(data);
    } catch (_) {
      return null;
    }
  }

  /// Descarga el catálogo de avisos del ingreso (granjas en situación especial,
  /// quién ingresó a ellas, ingresos de hoy y edades de granja) para calcular
  /// los avisos sin señal. `null` ante cualquier falla.
  Future<Map<String, dynamic>?> descargarAvisosIngreso({
    required String fechaYmd,
    List<String> destinos = const [],
  }) async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.seguimientoPath}'
        '${AppConstants.descargarAvisosIngresoEndpoint}',
      );
      final response = await _http
          .post(
            url,
            headers: _headers,
            body: jsonEncode({'fecha': fechaYmd, 'destinos': destinos}),
          )
          .timeout(const Duration(seconds: 25));
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

  /// Descarga la nómina DNI proveedor (personal de cada proveedor e
  /// historial reciente). `null` ante cualquier falla.
  Future<Map<String, dynamic>?> descargarNominaProveedores() async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.seguimientoPath}'
        '${AppConstants.descargarNominaProveedoresEndpoint}',
      );
      final response = await _http
          .post(url, headers: _headers, body: jsonEncode(const {}))
          .timeout(const Duration(seconds: 25));
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
      final response = await _http
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

  /// Sube un registro de bioseguridad (Garita, Cerco Eléctrico o Fómites).
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
          ? AppConstants.actualizarBioEndpoint
          : AppConstants.guardarBioEndpoint;
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
        // deduplique por él (y para que plan/ingreso en san_fact_* lo usen como
        // llave primaria).
        'id': EvidenciaRecordId.of(record),
        'usuario': usuario.isNotEmpty ? usuario : record['usuario'],
        'nombre_usuario': record['nombre_usuario'] ?? usuario,
        // Auditoría: quién capturó el dato en el equipo y cuándo.
        'usuarioRegistrador': record['usuario'] ?? usuario,
        'fechaHoraRegistro': record['created_at'],
        'fecha': record['fecha'],
        'granja': record['granja'],
        'campania': record['campania'],
        'turno': record['turno'],
        'app_version': AppConstants.appVersion,
        'registro': record['registro'] ?? const <String, dynamic>{},
        if (avisoDesde != null) 'version_warning_desde': avisoDesde,
      };

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

      final streamed = await _http.send(request).timeout(timeout);
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
            yaExistia: yaExistia,
            imagenesOk: dataMap['imagenes_ok'],
            tieneLista: lista is List,
            enviadas: enviadas,
            confirmadas: confirmadas,
          ),
        };
      }
      if (!isUpdate && decoded is Map && decoded['status'] == 409) {
        final retryRecord = Map<String, dynamic>.from(record);
        retryRecord['guardado_backend'] = true;
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
  /// El registro ya existía (`ya_existia`): es idempotencia por id, cuenta como
  /// subida completa. Si el backend responde `imagenes_ok`, manda ese dato. Si
  /// no, se compara cuántos archivos confirmó contra los enviados (el backend
  /// renombra los archivos, así que no se comparan nombres). Un backend que no
  /// devuelva lista no debe bloquear la subida.
  static bool _imagenesOk({
    required bool yaExistia,
    required dynamic imagenesOk,
    required bool tieneLista,
    required int enviadas,
    required int confirmadas,
  }) {
    if (yaExistia) return true;
    if (imagenesOk == true || imagenesOk?.toString() == '1') return true;
    if (imagenesOk == false || imagenesOk?.toString() == '0') return false;
    if (!tieneLista) return true;
    return confirmadas >= enviadas;
  }

  /// ¿La subida quedó completa (registro en el servidor con sus imágenes)?
  static bool subidaCompleta(Map<String, dynamic> result) {
    if (result['success'] != true) return false;
    final ok = result['imagenesOk'];
    if (ok == false || ok?.toString() == '0') return false;
    return true;
  }

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

  /// Personal activo (bio_personal + proveedores), sin filtrar por el usuario logueado.
  Future<Map<String, dynamic>> downloadPersonalReferencia() async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.seguimientoPath}'
        '${AppConstants.personalReferenciaEndpoint}',
      );
      final response = await _http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        return {'success': false, 'message': 'HTTP ${response.statusCode}'};
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
        'message': decoded is Map
            ? (decoded['message']?.toString() ?? 'personal')
            : 'personal',
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// El servidor identifica la foto entre el personal (1:N).
  /// Respuesta: `data.verificado`, `dni`, `nombre`, `empresa`, `similitud`.
  Future<Map<String, dynamic>> verificarRostro({
    required List<int> jpeg,
  }) async {
    final url = Uri.parse(
      '${AppConstants.baseUrl}${AppConstants.seguimientoPath}'
      '${AppConstants.verificarRostroEndpoint}',
    );
    final reloj = Stopwatch()..start();
    debugPrint('[BioVerif] POST $url bytes=${jpeg.length}');
    try {
      final response = await _http
          .post(
            url,
            headers: _headers,
            body: jsonEncode({'foto': base64Encode(jpeg)}),
          )
          .timeout(const Duration(seconds: 90));
      final decoded = jsonDecode(response.body);
      final data = decoded is Map ? decoded['data'] : null;
      final motivo = data is Map ? data['motivo'] : null;
      debugPrint(
        '[BioVerif] POST $url → ${response.statusCode} '
        '${reloj.elapsedMilliseconds}ms ${response.body.length}B motivo=$motivo',
      );
      if (decoded is! Map) {
        return {'success': false, 'message': 'Respuesta inválida'};
      }
      return {
        'success': decoded['success'] == true && response.statusCode == 200,
        'message': decoded['message']?.toString() ?? '',
        'data': data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
      };
    } on TimeoutException {
      debugPrint('[BioVerif] POST $url → timeout ${reloj.elapsedMilliseconds}ms');
      return {'success': false, 'message': 'timeout'};
    } catch (e) {
      debugPrint('[BioVerif] POST $url → error ${reloj.elapsedMilliseconds}ms $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Foto ya registrada de un DNI. Null si no hay archivo.
  Future<Uint8List?> downloadFotoPersonal(String dni) async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.seguimientoPath}'
        '${AppConstants.fotoPersonalEndpoint}',
      ).replace(queryParameters: {'dni': dni});
      final response = await _http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 || response.bodyBytes.length < 32) {
        return null;
      }
      final tipo = (response.headers['content-type'] ?? '').toLowerCase();
      if (tipo.contains('json') || tipo.contains('text/')) return null;
      return response.bodyBytes;
    } catch (_) {
      return null;
    }
  }
}
