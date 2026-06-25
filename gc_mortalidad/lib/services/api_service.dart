import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cenco.dart';
import '../models/galpon.dart';
import '../models/motivo_mortalidad.dart';
import '../utils/constants.dart';

class ApiService {
  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${AppConstants.apiToken}',
        'Content-Type': 'application/json; charset=utf-8',
      };

  Future<String> _getUsuarioSesion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getString(AppConstants.keyUserCode) ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  Future<Map<String, dynamic>> login({
    required String usuario,
    required String password,
    required String androidId,
    required String version,
  }) async {
    try {
      final passwordBase64 = base64Encode(utf8.encode(password));
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.loginEndpoint}',
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
      final raw = response.body.trim();
      if (raw.isEmpty) {
        return {
          'success': false,
          'message':
              'El servidor devolvi? una respuesta vac?a (HTTP ${response.statusCode}).',
          'errorCode': 'EMPTY_RESPONSE',
        };
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return {
          'success': false,
          'message': AppStrings.errorServidor,
          'errorCode': 'INVALID_RESPONSE',
        };
      }
      return {
        'success': decoded['success'] == true,
        'status': decoded['status'],
        'message': decoded['message']?.toString() ?? 'Sin mensaje',
        'errorCode': decoded['errorCode'],
        'data': decoded['data'],
        'debug': decoded['debug']?.toString(),
      };
    } on FormatException catch (e) {
      return {
        'success': false,
        'message': 'Respuesta JSON inv?lida del servidor: $e',
        'errorCode': 'INVALID_JSON',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error de conexion. Verifique su internet e intente de nuevo.',
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
        'status': data['status'],
        'message': data['message'] ?? 'Sin mensaje',
        'errorCode': data['errorCode'],
        'data': data['data'],
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error de conexion. Verifique su internet e intente de nuevo.',
        'errorCode': null,
      };
    }
  }

  Future<Map<String, dynamic>> downloadCatalogos({List<String>? tablas}) async {
    try {
      Uri url;
      if (tablas != null && tablas.isNotEmpty) {
        url = Uri.parse(
          '${AppConstants.baseUrl}${AppConstants.downloadEndpoint}',
        ).replace(queryParameters: {'tablas': tablas.join(',')});
      } else {
        url = Uri.parse(
          '${AppConstants.baseUrl}${AppConstants.downloadEndpoint}',
        );
      }
      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 30));
      final decoded = jsonDecode(response.body);
      final data = decoded is Map<String, dynamic> ? decoded : null;
      if (data == null) {
        return {'success': false, 'message': AppStrings.errorServidor};
      }
      if (response.statusCode == 200 && data['success'] == true) {
        final innerData = data['data'];
        return {
          'success': true,
          'data': innerData is Map<String, dynamic> ? innerData : <String, dynamic>{},
          'message': data['message']?.toString() ?? 'OK',
        };
      }
      return {
        'success': false,
        'message': data['message']?.toString() ?? 'Error al descargar',
      };
    } catch (e) {
      return {'success': false, 'message': 'Error de conexion. Verifique su internet e intente de nuevo.'};
    }
  }

  Future<Map<String, dynamic>> downloadCencosGalpones({String? fecha}) async {
    try {
      final usuario = await _getUsuarioSesion();
      var url = Uri.parse(
        '${AppConstants.baseUrl}/mortalidad/get_cencos_galpones.php',
      );
      final params = <String, String>{};
      if (usuario.isNotEmpty) params['usuario'] = usuario;
      if (fecha != null && fecha.isNotEmpty) params['fecha'] = fecha;
      if (params.isNotEmpty) url = url.replace(queryParameters: params);

      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 401) {
        return {
          'success': false,
          'message': 'Token inv\u00e1lido (401). Verifique la configuraci\u00f3n del servidor.',
        };
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': AppStrings.errorServidor};
      }
      final data = decoded;

      if (data['success'] != true) {
        return {
          'success': false,
          'message': data['message']?.toString() ?? 'Error al descargar cencos',
        };
      }

      final inner = data['data'] as Map<String, dynamic>? ?? {};
      final cencosRaw = inner['cencos'] as List? ?? [];

      final cencos = cencosRaw
          .map((e) => Cenco.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      final galponesPorCenco = <String, List<Galpon>>{};
      for (final cencoData in cencosRaw) {
        final cencoMap = Map<String, dynamic>.from(cencoData as Map);
        final codigoCenco = cencoMap['codigo']?.toString() ?? '';
        final prefijo = codigoCenco.length >= 3 ? codigoCenco.substring(0, 3) : codigoCenco;
        final galponesData = cencoMap['galpones'] as List? ?? [];
        final galpones = galponesData
            .map(
              (g) => Galpon(
                tcencos: prefijo,
                tcodint: (g as Map)['tcodint']?.toString() ?? '',
                fecIngMin: g['fec_ing_min']?.toString(),
                edad: g['edad']?.toString() ?? '0',
              ),
            )
            .toList();
        galponesPorCenco[prefijo] = galpones;
        galponesPorCenco[codigoCenco] = galpones;
      }

      return {
        'success': true,
        'cencos': cencos,
        'galponesPorCenco': galponesPorCenco,
        'message': 'OK',
      };
    } catch (e) {
      return {'success': false, 'message': 'Error al descargar granjas. Verifique su conexi\u00f3n.'};
    }
  }

  Future<Map<String, dynamic>> downloadMotivosMortalidad() async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}/mortalidad/get_motivos_mortalidad.php',
      );
      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 401) {
        return {
          'success': false,
          'message': 'Token inv?lido (401). Verifique la configuraci?n del servidor.',
        };
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': AppStrings.errorServidor};
      }
      final data = decoded;

      if (data['success'] != true) {
        return {
          'success': false,
          'message': data['message']?.toString() ?? 'Error al descargar motivos',
        };
      }

      final inner = data['data'] as Map<String, dynamic>? ?? {};
      final motivosRaw = inner['motivos'] as List? ?? [];
      final motivos = motivosRaw
          .map((e) => MotivoMortalidad.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      return {'success': true, 'motivos': motivos, 'message': 'OK'};
    } catch (e) {
      return {'success': false, 'message': 'Error al descargar causas. Verifique su conexi\u00f3n.'};
    }
  }

  Future<Map<String, dynamic>> getMortalityVisibility({
    String? codigo,
    String? dni,
  }) async {
    try {
      final params = <String, String>{};
      final cod = codigo?.trim() ?? '';
      final dniVal = dni?.trim() ?? '';
      if (cod.isNotEmpty) params['codigo'] = cod;
      if (dniVal.isNotEmpty) params['dni'] = dniVal;

      final url = Uri.parse(
        '${AppConstants.baseUrl}/mortalidad/get_visibilidad_mortalidad.php',
      ).replace(queryParameters: params.isEmpty ? null : params);

      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(response.body);
      final data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      final ok = response.statusCode == 200 && data['success'] == true;
      final payload = data['data'] is Map
          ? Map<String, dynamic>.from(data['data'] as Map)
          : <String, dynamic>{};
      final vis = payload['visibilidad'];
      return {
        'success': ok,
        'visibilidad': vis is Map ? Map<String, dynamic>.from(vis) : <String, dynamic>{},
        'codigo_usuario': payload['codigo_usuario']?.toString() ?? '',
        'message': data['message']?.toString() ?? '',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e',
        'visibilidad': <String, dynamic>{},
        'codigo_usuario': '',
      };
    }
  }

  /// Listado de liquidaci?n desde BD (san_fact_mortalidad_cab).
  Future<Map<String, dynamic>> listarMortalidadLiquidacion({
    required String fecha,
    String? granja,
    String? campania,
    String? galpon,
    String? tipoMortalidad,
  }) async {
    try {
      final params = <String, String>{
        'fecha': fecha,
      };
      if (granja != null && granja.isNotEmpty) {
        params['granja'] = granja;
      }
      if (campania != null && campania.isNotEmpty) {
        params['campania'] = campania;
      }
      if (galpon != null && galpon.isNotEmpty) {
        params['galpon'] = galpon;
      }
      if (tipoMortalidad != null && tipoMortalidad.isNotEmpty) {
        params['tipo_mortalidad'] = tipoMortalidad;
      }

      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.listarMortalidadEndpoint}',
      ).replace(queryParameters: params);

      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 45));
      if (response.statusCode == 401) {
        return {
          'success': false,
          'message': 'Token inv?lido (401). Verifique la configuraci?n del servidor.',
          'registros': <Map<String, dynamic>>[],
        };
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return {
          'success': false,
          'message': 'Respuesta inv?lida del servidor',
          'registros': <Map<String, dynamic>>[],
        };
      }

      final ok = response.statusCode == 200 && decoded['success'] == true;
      final inner = decoded['data'] is Map
          ? Map<String, dynamic>.from(decoded['data'] as Map)
          : <String, dynamic>{};
      final raw = inner['registros'];
      final registros = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map) {
            registros.add(Map<String, dynamic>.from(item));
          }
        }
      }

      return {
        'success': ok,
        'message': decoded['message']?.toString() ?? '',
        'registros': registros,
        'total': inner['total'] ?? registros.length,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error de conexion. Verifique su internet e intente de nuevo.',
        'registros': <Map<String, dynamic>>[],
      };
    }
  }

  Future<Map<String, dynamic>> uploadMortalidadMovil({
    required Map<String, dynamic> record,
  }) async {
    try {
      final payload = Map<String, dynamic>.from(record);
      final tid = payload['tidandroid']?.toString().trim() ?? '';
      if (tid.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final deviceId = (prefs.getString(AppConstants.keyDeviceId) ?? '').trim();
        if (deviceId.isNotEmpty) {
          payload['tidandroid'] = deviceId;
        }
      }

      final url = Uri.parse(
        '${AppConstants.baseUrl}/mortalidad/guardar_mortalidad_movil.php',
      );
      final request = http.MultipartRequest('POST', url);
      request.headers['Authorization'] = 'Bearer ${AppConstants.apiToken}';
      request.fields['data'] = jsonEncode({'mortalidad': [payload]});

      final detalles = payload['detalles'];
      if (detalles is List) {
        for (final rawDet in detalles) {
          if (rawDet is! Map) continue;
          final det = Map<String, dynamic>.from(rawDet);
          final detId = det['id']?.toString().trim() ?? '';
          if (detId.isEmpty) continue;

          final fotos = det['fotos'];
          if (fotos is! List) continue;

          for (var i = 0; i < fotos.length; i++) {
            final f = fotos[i];
            String? path;
            if (f is Map) {
              path = f['path']?.toString();
            } else if (f is String) {
              path = f;
            }
            if (path == null || path.isEmpty) continue;

            final file = File(path);
            if (!await file.exists()) continue;

            request.files.add(
              await http.MultipartFile.fromPath('img_${detId}_$i', file.path),
            );
          }
        }
      }

      final streamed = await request.send().timeout(const Duration(minutes: 5));
      final response = await http.Response.fromStream(streamed);

      Map<String, dynamic> data;
      try {
        final decoded = jsonDecode(response.body);
        data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      } catch (_) {
        return {
          'success': false,
          'message': AppStrings.errorServidor,
          'status': response.statusCode,
        };
      }

      final ok = response.statusCode == 200 && data['success'] == true;

      return {
        'success': ok,
        'status': response.statusCode,
        'message': data['message']?.toString() ?? 'Sin mensaje',
        'errorCode': data['errorCode']?.toString(),
        'data': data['data'],
        'debug': data['debug']?.toString(),
      };
    } catch (e) {
      return {'success': false, 'message': 'Error de conexion. Verifique su internet e intente de nuevo.'};
    }
  }

  Future<Map<String, dynamic>> listarAuditoriaPendiente({
    String? fechaDesde,
    String? fechaHasta,
    String? granjaCodigo,
    String? campaniaCodigo,
    String? galponCodigo,
  }) async {
    try {
      final params = <String, String>{};
      if (fechaDesde != null && fechaDesde.isNotEmpty) {
        params['fecha_desde'] = fechaDesde;
      }
      if (fechaHasta != null && fechaHasta.isNotEmpty) {
        params['fecha_hasta'] = fechaHasta;
      }
      if (granjaCodigo != null && granjaCodigo.isNotEmpty) {
        params['granja_codigo'] = granjaCodigo;
      }
      if (campaniaCodigo != null && campaniaCodigo.isNotEmpty) {
        params['campania_codigo'] = campaniaCodigo;
      }
      if (galponCodigo != null && galponCodigo.isNotEmpty) {
        params['galpon_codigo'] = galponCodigo;
      }
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.listarAuditoriaEndpoint}',
      ).replace(queryParameters: params.isEmpty ? null : params);

      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 45));

      final decoded = jsonDecode(response.body);
      final data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      final ok = response.statusCode == 200 && data['success'] == true;

      return {
        'success': ok,
        'message': data['message']?.toString() ?? 'Sin mensaje',
        'data': data['data'],
      };
    } catch (e) {
      return {'success': false, 'message': 'Error de conexion. Verifique su internet e intente de nuevo.'};
    }
  }

  Future<Map<String, dynamic>> listarMisAuditorias({
    required String usuario,
    String? fechaDesde,
    String? fechaHasta,
  }) async {
    try {
      final params = <String, String>{'usuario': usuario};
      if (fechaDesde != null && fechaDesde.isNotEmpty) {
        params['fecha_desde'] = fechaDesde;
      }
      if (fechaHasta != null && fechaHasta.isNotEmpty) {
        params['fecha_hasta'] = fechaHasta;
      }
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.listarMisAuditoriasEndpoint}',
      ).replace(queryParameters: params);

      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 45));

      final decoded = jsonDecode(response.body);
      final data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      final ok = response.statusCode == 200 && data['success'] == true;

      return {
        'success': ok,
        'message': data['message']?.toString() ?? 'Sin mensaje',
        'data': data['data'],
      };
    } catch (e) {
      return {'success': false, 'message': 'Error de conexion. Verifique su internet e intente de nuevo.'};
    }
  }

  Future<Map<String, dynamic>> downloadCantidadPollos({
    required String tcencos,
    String? fecha,
    String? galpon,
  }) async {
    try {
      final params = <String, String>{'tcencos': tcencos};
      if (fecha != null && fecha.isNotEmpty) {
        params['fecha'] = fecha;
      }
      if (galpon != null && galpon.isNotEmpty) {
        params['galpon'] = galpon;
      }
      final url = Uri.parse(
        '${AppConstants.baseUrl}/mortalidad/get_cantidad_pollos.php',
      ).replace(queryParameters: params);

      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 401) {
        return {
          'success': false,
          'message': 'Token inv\u00e1lido (401). Verifique la configuraci\u00f3n del servidor.',
        };
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Respuesta inv\u00e1lida del servidor'};
      }

      final ok = decoded['success'] == true;
      final inner = decoded['data'] is Map
          ? Map<String, dynamic>.from(decoded['data'] as Map)
          : <String, dynamic>{};
      final items = (inner['items'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          <Map<String, dynamic>>[];

      return {
        'success': ok,
        'items': items,
        'message': decoded['message']?.toString() ?? '',
      };
    } catch (e) {
      return {'success': false, 'message': 'Error: $e', 'items': <Map<String, dynamic>>[]};
    }
  }

  /// Descarga cantidades de pollos para MULTIPLES tcencos en una ventana de 15 d?as.
  Future<Map<String, dynamic>> downloadCantidadPollosBatch({
    required List<String> tcencosList,
    String? fechaCentral,
  }) async {
    try {
      final params = <String, String>{
        'tcencos': jsonEncode(tcencosList),
      };
      if (fechaCentral != null && fechaCentral.isNotEmpty) {
        params['fecha_central'] = fechaCentral;
      }
      final url = Uri.parse(
        '${AppConstants.baseUrl}/mortalidad/get_cantidad_pollos_batch.php',
      ).replace(queryParameters: params);

      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 401) {
        return {
          'success': false,
          'message': 'Token inv\u00e1lido (401). Verifique la configuraci\u00f3n del servidor.',
        };
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Respuesta inv\u00e1lida del servidor'};
      }

      final ok = decoded['success'] == true;
      final inner = decoded['data'] is Map
          ? Map<String, dynamic>.from(decoded['data'] as Map)
          : <String, dynamic>{};
      final rawItems = inner['items'];
      // items puede ser {} (objeto) o [] (array vacio)
      Map<String, dynamic> itemsMap;
      if (rawItems is Map) {
        itemsMap = Map<String, dynamic>.from(rawItems);
      } else {
        itemsMap = <String, dynamic>{};
      }

      // Convertir cada valor a List<Map<String, dynamic>>
      final items = itemsMap.map(
        (k, v) => MapEntry(
          k,
          (v as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? <Map<String, dynamic>>[],
        ),
      );

      return {
        'success': ok,
        'items': items,
        'message': decoded['message']?.toString() ?? '',
      };
    } catch (e) {
      debugPrint('[CANTIDAD_BATCH_ERROR] $e');
      return {'success': false, 'message': 'Error: $e', 'items': <String, List<Map<String, dynamic>>>{}};
    }
  }

  Future<Map<String, dynamic>> listarBloquesLiquidacion({
    String? usuario,
    String? fechaDesde,
    String? fechaHasta,
    String? granjaCodigo,
    String? campaniaCodigo,
    String? galponCodigo,
  }) async {
    try {
      final params = <String, String>{};
      if (usuario != null && usuario.isNotEmpty) {
        params['usuario'] = usuario;
      }
      if (fechaDesde != null && fechaDesde.isNotEmpty) {
        params['fecha_desde'] = fechaDesde;
      }
      if (fechaHasta != null && fechaHasta.isNotEmpty) {
        params['fecha_hasta'] = fechaHasta;
      }
      if (granjaCodigo != null && granjaCodigo.isNotEmpty) {
        params['granja_codigo'] = granjaCodigo;
      }
      if (campaniaCodigo != null && campaniaCodigo.isNotEmpty) {
        params['campania_codigo'] = campaniaCodigo;
      }
      if (galponCodigo != null && galponCodigo.isNotEmpty) {
        params['galpon_codigo'] = galponCodigo;
      }
      final url = Uri.parse(
        '${AppConstants.baseUrl}/mortalidad/listar_liquidacion_bloques.php',
      ).replace(queryParameters: params.isEmpty ? null : params);

      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 45));

      if (response.statusCode == 401) {
        return {'success': false, 'message': 'Token inv\u00e1lido (401). Verifique la configuraci\u00f3n del servidor.'};
      }

      final rawBody = response.body.trim();
      if (rawBody.isEmpty) {
        return {'success': false, 'message': 'El servidor devolvi\u00f3 una respuesta vac\u00eda.'};
      }

      final decoded = jsonDecode(rawBody);
      final data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      final ok = response.statusCode == 200 && data['success'] == true;

      if (!ok) {
        final serverDebug = data['debug']?.toString();
        if (serverDebug != null && serverDebug.isNotEmpty) {
          debugPrint('[LIQUIDACION_SERVER_ERROR] $serverDebug');
        }
        return {
          'success': false,
          'message': data['message']?.toString() ?? 'Error del servidor',
        };
      }

      return {
        'success': true,
        'message': data['message']?.toString() ?? 'Sin mensaje',
        'data': data['data'],
      };
    } on FormatException catch (e) {
      debugPrint('[LIQUIDACION_PARSE_ERROR] $e');
      return {'success': false, 'message': 'Respuesta inv\u00e1lida del servidor.'};
    } catch (e) {
      debugPrint('[LIQUIDACION_CONN_ERROR] $e');
      return {'success': false, 'message': null};
    }
  }

  Future<Map<String, dynamic>> guardarAuditoriaMovil({
    required String usuario,
    required List<Map<String, dynamic>> registros,
    String observacionesGenerales = '',
  }) async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}${AppConstants.guardarAuditoriaEndpoint}',
      );
      final request = http.MultipartRequest('POST', url);
      request.headers['Authorization'] = 'Bearer ${AppConstants.apiToken}';
      request.fields['usuario'] = usuario;

      final payload = <Map<String, dynamic>>[];
      for (final a in registros) {
        final clave = a['clave']?.toString() ?? '';
        final fotos = a['fotos'];
        final fotosList = fotos is List ? List<String>.from(fotos.map((e) => e.toString())) : <String>[];
        payload.add({
          'clave': clave,
          'aprobado': a['aprobado'] == true,
          'registro_uuids': a['registro_uuids'] ?? [],
          'observaciones': a['observaciones']?.toString() ?? '',
        });

        final safeClave = clave.replaceAll(':', '_').replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
        for (var i = 0; i < fotosList.length; i++) {
          final path = fotosList[i];
          final file = File(path);
          if (await file.exists()) {
            request.files.add(
              await http.MultipartFile.fromPath(
                'aud_img_${safeClave}_$i',
                file.path,
              ),
            );
          }
        }
      }

      request.fields['data'] = jsonEncode({
        'observaciones': observacionesGenerales,
        'registros': payload,
      });

      final streamed = await request.send().timeout(const Duration(minutes: 5));
      final response = await http.Response.fromStream(streamed);

      Map<String, dynamic> data;
      try {
        final decoded = jsonDecode(response.body);
        data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      } catch (_) {
        return {
          'success': false,
          'message': AppStrings.errorServidor,
        };
      }

      final ok = response.statusCode == 200 && data['success'] == true;
      return {
        'success': ok,
        'message': data['message']?.toString() ?? 'Sin mensaje',
        'data': data['data'],
        'errorCode': data['errorCode']?.toString(),
        'debug': data['debug']?.toString(),
      };
    } catch (e) {
      return {'success': false, 'message': 'Error de conexion. Verifique su internet e intente de nuevo.'};
    }
  }
}
