import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cenco.dart';
import '../models/galpon.dart';
import '../utils/constants.dart';

class ApiService {
  // Headers comunes
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
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      debugPrint(data.toString());
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
          '${AppConstants.baseUrl}${AppConstants.downloadEndpoint}',
        ).replace(queryParameters: {'tablas': tablasParam});
      } else {
        url = Uri.parse(
          '${AppConstants.baseUrl}${AppConstants.downloadEndpoint}',
        );
      }

      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 15));

      final decoded = jsonDecode(response.body);
      final data = decoded is Map<String, dynamic> ? decoded : null;
        print(data);
      if (data == null) {
        return {
          'success': false,
          'message': 'Respuesta inválida del servidor',
        };
      }

      if (response.statusCode == 200 && data['success'] == true) {
        final innerData = data['data'];
        return {
          'success': true,
          'data': innerData is Map<String, dynamic> ? innerData : <String, dynamic>{},
          'message': data['message']?.toString() ?? 'OK',
        };
      } else {
        return {
          'success': false,
          'message': data['message']?.toString() ?? 'Error al descargar catálogos',
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
        '${AppConstants.baseUrl}${AppConstants.uploadEndpoint}',
      );

      final body = jsonEncode(data);

      final response = await http
          .post(url, headers: _headers, body: body)
          .timeout(const Duration(seconds: 60));

      final responseData = jsonDecode(response.body);
      print(responseData);
      if (response.statusCode == 200 && responseData['success'] == true) {
        return {
          'success': true,
          'detalle': responseData['detalle'],
          'message': responseData['message'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Error al subir datos',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error de conexión: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> uploadMultiple(
    Map<String, dynamic> payload,
  ) async {
    final url = Uri.parse(
      '${AppConstants.baseUrl}/necropcias/guardar_necropsia_movil.php',
    );
    final response = await http
        .post(url, headers: _headers, body: jsonEncode(payload))
        .timeout(const Duration(seconds: 60));

    print(response);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      print('aqui');
      throw Exception('Error HTTP ${response.statusCode}: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> uploadNecropsiasMovil(
    List<Map<String, dynamic>> necropsias,
  ) async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}/necropcias/guardar_necropsia_movil.php',
      );

      // Crear request multipart
      final request = http.MultipartRequest('POST', url);

      // Agregar headers de autorización
      request.headers.addAll({
        'Authorization': 'Bearer ${AppConstants.apiToken}',
      });

      // Separar evidencias de cada necropsia para enviarlas como archivos
      final necropsiasSinEvidencias = <Map<String, dynamic>>[];

      for (var necropsia in necropsias) {
        final necropsiaSinEvidencias = Map<String, dynamic>.from(necropsia);
        final evidenciasCompletas = necropsia['evidencias_completas'] as Map<String, dynamic>? ?? {};

        // Extraer evidencias para enviarlas como archivos
        necropsiaSinEvidencias.remove('evidencias');
        necropsiaSinEvidencias.remove('evidencias_completas');

        // Agregar información de evidencias como metadata (nivel + cantidad)
        final evidenciasMetadata = <String, Map<String, String>>{};

        // Procesar evidencias por nivel (puede haber múltiples imágenes por nivel)
        // CRÍTICO: Usar bucle for normal con await en lugar de Future.forEach
        // para asegurar que todas las imágenes se procesen secuencialmente
        debugPrint('📸 uploadNecropsiasMovil - Procesando ${evidenciasCompletas.length} niveles de evidencias');
        int totalImagenesProcesadas = 0;

        for (var entry in evidenciasCompletas.entries) {
          final nivelKey = entry.key; // ej: "INMUNOLOGICO_INDICE BURSAL"
          final imagenesListRaw = entry.value;

          // CRÍTICO: Asegurar que imagenesList sea una List, convertir si es necesario
          List<dynamic> imagenesList = [];
          if (imagenesListRaw is List) {
            imagenesList = imagenesListRaw;
          } else if (imagenesListRaw != null) {
            debugPrint('⚠️ imagenesList no es List, tipo: ${imagenesListRaw.runtimeType}, convirtiendo...');
            imagenesList = [imagenesListRaw];
          }

          debugPrint('   📸 Procesando nivel $nivelKey con ${imagenesList.length} imágenes');

          if (imagenesList.isNotEmpty) {
            final primeraImagen = imagenesList[0] as Map<String, dynamic>? ?? {};
            final sistema = primeraImagen['sistema'] ?? '';
            final nivel = primeraImagen['nivel'] ?? '';

            // IMPORTANTE: Normalizar nivelKey para que coincida con la clave del archivo
            // Reemplazar espacios y caracteres especiales con guiones bajos
            final normalizedKey = nivelKey.replaceAll(' ', '_').replaceAll('/', '_').replaceAll('\\', '_');

            evidenciasMetadata[normalizedKey] = {
              'sistema': sistema,
              'nivel': nivel,
              'cantidad': imagenesList.length.toString(),
              'original_key': nivelKey, // Guardar la clave original para referencia
            };

            debugPrint('DEBUG - nivelKey original: $nivelKey, normalized: $normalizedKey');

            // Agregar cada imagen del nivel al request (con compresión)
            // IMPORTANTE: Usar índice local (0, 1, 2) para cada nivel, no global
            // IMPORTANTE: Usar normalizedKey para construir la clave del archivo (ya está declarado arriba)
            for (int localIndex = 0; localIndex < imagenesList.length; localIndex++) {
              final imagenData = imagenesList[localIndex];
              if (imagenData is Map<String, dynamic>) {
                final imagePath = imagenData['path'] as String? ?? '';
                if (imagePath.isNotEmpty) {
                  try {
                    final originalFile = File(imagePath);
                    if (originalFile.existsSync()) {
                      final originalSize = await originalFile.length();
                      debugPrint('📷 Imagen original [$normalizedKey][$localIndex]: ${(originalSize / 1024 / 1024).toStringAsFixed(2)} MB');

                      if (originalSize > 0) {
                        // Comprimir imagen antes de enviar
                        File? compressedFile;
                        String? compressedPath;

                        try {
                          final tempDir = await getTemporaryDirectory();
                          final extension = path.extension(imagePath).toLowerCase();

                          // CRÍTICO: Si la imagen es PNG (especialmente las editadas), la compresión a PNG suele quedar muy pesada
                          // y puede rebotar por límites del servidor (UPLOAD_ERR_INI_SIZE). Convertimos a JPEG para bajar tamaño.
                          final bool compressToJpeg = extension == '.png';
                          final outExt = compressToJpeg ? '.jpg' : '.jpg'; // siempre jpg para fotos
                          final fileName =
                              'compressed_${DateTime.now().millisecondsSinceEpoch}_${normalizedKey}_$localIndex$outExt';
                          compressedPath = path.join(tempDir.path, fileName);

                          // Compresión adaptativa para no reventar límites del backend (p.ej. 8MB por request).
                          final int maxDim = originalSize > 2 * 1024 * 1024 ? 1024 : 1280;
                          final int quality = originalSize > 2 * 1024 * 1024 ? 60 : 70;

                          final compressedData = await FlutterImageCompress.compressWithFile(
                            imagePath,
                            minWidth: maxDim,
                            minHeight: maxDim,
                            quality: quality,
                            format: CompressFormat.jpeg,
                          );

                          if (compressedData != null && compressedData.isNotEmpty) {
                            compressedFile = File(compressedPath);
                            await compressedFile.writeAsBytes(compressedData);

                            // CRÍTICO: Verificar que el archivo se haya escrito correctamente
                            if (!compressedFile.existsSync()) {
                              debugPrint('✗ Error: El archivo comprimido no existe después de escribirlo: $compressedPath');
                              continue;
                            }

                            final compressedSize = await compressedFile.length();
                            if (compressedSize == 0) {
                              debugPrint('✗ Error: El archivo comprimido está vacío: $compressedPath');
                              continue;
                            }

                            final compressionRatio = ((1 - compressedSize / originalSize) * 100).toStringAsFixed(1);
                            debugPrint('✓ Imagen comprimida [$normalizedKey][$localIndex]: ${(compressedSize / 1024 / 1024).toStringAsFixed(2)} MB (${compressionRatio}% reducción)');

                            // Crear nombre único para el archivo
                            final granja = necropsia['granja'] ?? '';
                            final galpon = necropsia['galpon'] ?? '';
                            final numreg = necropsia['numreg'] ?? '';
                            final fectra = (necropsia['fectra'] as String? ?? '').replaceAll('-', '');
                            final sistemaLower = sistema.toLowerCase();
                            final nivelLower = nivel.toLowerCase().replaceAll(' ', '_').replaceAll('/', '_');

                            final finalExtension = 'jpg';
                            final finalFileName = '${granja}_${galpon}_${numreg}_${fectra}_${sistemaLower}_${nivelLower}_$localIndex.$finalExtension';

                            // IMPORTANTE: Usar normalizedKey que ya fue declarado arriba
                            final fileKey = 'evidencia_${normalizedKey}_$localIndex';

                            try {
                              // CRÍTICO: Verificar que el archivo existe y tiene contenido antes de agregarlo
                              if (!compressedFile.existsSync()) {
                                debugPrint('✗ Error: El archivo comprimido no existe: ${compressedFile.path}');
                                continue;
                              }

                              final fileSize = await compressedFile.length();
                              if (fileSize == 0) {
                                debugPrint('✗ Error: El archivo comprimido está vacío: ${compressedFile.path}');
                                continue;
                              }

                              // IMPORTANTE: Usar fromPath para que el archivo se lea cuando se envíe el request
                              // Esto asegura que el Content-Type se establezca correctamente
                              final multipartFile = await http.MultipartFile.fromPath(
                                fileKey,
                                compressedFile.path,
                                filename: finalFileName,
                              );
                              request.files.add(multipartFile);
                              totalImagenesProcesadas++;
                              debugPrint('✓ Imagen agregada al request: $finalFileName (key: $fileKey, path: ${compressedFile.path}, size: $fileSize bytes) [Total: $totalImagenesProcesadas]');

                              // NO eliminar el archivo temporal aquí - se eliminará después de enviar el request
                            } catch (e) {
                              debugPrint('✗ Error al crear MultipartFile: $e');
                            }
                          } else {
                            debugPrint('⚠ Error: No se pudo comprimir la imagen [$normalizedKey][$localIndex] o los datos están vacíos');
                            // Fallback: enviar original (esto pasa seguido con PNG editados)
                            final originalFileCheck = File(imagePath);
                            if (!originalFileCheck.existsSync()) {
                              debugPrint('✗ Error: El archivo original no existe: $imagePath');
                              continue;
                            }

                            final fileSize = await originalFileCheck.length();
                            if (fileSize == 0) {
                              debugPrint('✗ Error: El archivo original está vacío: $imagePath');
                              continue;
                            }

                            final granja = necropsia['granja'] ?? '';
                            final galpon = necropsia['galpon'] ?? '';
                            final numreg = necropsia['numreg'] ?? '';
                            final fectra = (necropsia['fectra'] as String? ?? '').replaceAll('-', '');
                            final sistemaLower = sistema.toLowerCase();
                            final nivelLower = nivel.toLowerCase().replaceAll(' ', '_').replaceAll('/', '_');

                            final originalExt = path.extension(imagePath).replaceAll('.', '').toLowerCase();
                            final safeExt = originalExt.isEmpty ? 'jpg' : originalExt;
                            final fileName = '${granja}_${galpon}_${numreg}_${fectra}_${sistemaLower}_${nivelLower}_$localIndex.$safeExt';

                            final fileKey = 'evidencia_${normalizedKey}_$localIndex';
                            try {
                              final multipartFile = await http.MultipartFile.fromPath(
                                fileKey,
                                imagePath,
                                filename: fileName,
                              );
                              request.files.add(multipartFile);
                              totalImagenesProcesadas++;
                              debugPrint('✓ Imagen original (fallback) agregada: $fileName (key: $fileKey, path: $imagePath, size: $fileSize bytes) [Total: $totalImagenesProcesadas]');
                            } catch (e) {
                              debugPrint('✗ Error al crear MultipartFile para imagen original (fallback): $e');
                            }
                          }
                        } catch (compressionError) {
                          debugPrint('⚠ Error al comprimir imagen [$normalizedKey][$localIndex]: $compressionError');
                          // Si falla la compresión, intentar enviar la original (pero con warning)
                          if (originalSize > 5 * 1024 * 1024) { // 5MB
                            debugPrint('⚠ ADVERTENCIA: Imagen muy grande sin comprimir (${(originalSize / 1024 / 1024).toStringAsFixed(2)} MB)');
                          }

                          // Intentar enviar original si es pequeña
                          final originalFileCheck = File(imagePath);
                          if (!originalFileCheck.existsSync()) {
                            debugPrint('✗ Error: El archivo original no existe: $imagePath');
                            continue;
                          }

                          final granja = necropsia['granja'] ?? '';
                          final galpon = necropsia['galpon'] ?? '';
                          final numreg = necropsia['numreg'] ?? '';
                          final fectra = (necropsia['fectra'] as String? ?? '').replaceAll('-', '');
                          final sistemaLower = sistema.toLowerCase();
                          final nivelLower = nivel.toLowerCase().replaceAll(' ', '_').replaceAll('/', '_');

                          final fileName = '${granja}_${galpon}_${numreg}_${fectra}_${sistemaLower}_${nivelLower}_$localIndex.jpg';

                            // IMPORTANTE: Usar normalizedKey que ya fue declarado arriba
                          final fileKey = 'evidencia_${normalizedKey}_$localIndex';

                          try {
                            // CRÍTICO: Verificar que el archivo existe y tiene contenido
                            if (!originalFileCheck.existsSync()) {
                              debugPrint('✗ Error: El archivo original no existe: $imagePath');
                              continue;
                            }

                            final fileSize = await originalFileCheck.length();
                            if (fileSize == 0) {
                              debugPrint('✗ Error: El archivo original está vacío: $imagePath');
                              continue;
                            }

                              // IMPORTANTE: Usar fromPath para que el archivo se lea cuando se envíe el request
                          final multipartFile = await http.MultipartFile.fromPath(
                              fileKey,
                              imagePath,
                              filename: fileName,
                            );
                            request.files.add(multipartFile);
                            totalImagenesProcesadas++;
                            debugPrint('✓ Imagen original agregada: $fileName (key: $fileKey, path: $imagePath, size: $fileSize bytes) [Total: $totalImagenesProcesadas]');
                          } catch (e) {
                            debugPrint('✗ Error al crear MultipartFile para imagen original: $e');
                          }
                        }
                      } else {
                        debugPrint('⚠ Advertencia: Archivo vacío: $imagePath');
                      }
                    } else {
                      debugPrint('✗ Archivo NO existe: $imagePath');
                    }
                  } catch (e, stackTrace) {
                    debugPrint('✗ Error al procesar imagen [$normalizedKey][$localIndex]: $e');
                    debugPrint('Stack trace: $stackTrace');
                  }
                }
              }
            }
          }
        }

        debugPrint('📸 uploadNecropsiasMovil - Total imágenes procesadas para esta necropsia: $totalImagenesProcesadas');
        debugPrint('📸 uploadNecropsiasMovil - Total archivos en request hasta ahora: ${request.files.length}');

        // Agregar metadata de evidencias al JSON
        if (evidenciasMetadata.isNotEmpty) {
          necropsiaSinEvidencias['evidencias_metadata'] = evidenciasMetadata;
          debugPrint('📋 evidencias_metadata agregado:');
          evidenciasMetadata.forEach((key, value) {
            debugPrint('   - $key: cantidad=${value['cantidad']}, sistema=${value['sistema']}, nivel=${value['nivel']}');
          });
        } else {
          debugPrint('⚠️ evidencias_metadata está vacío para esta necropsia');
        }

        necropsiasSinEvidencias.add(necropsiaSinEvidencias);
      }

      // Agregar datos JSON al request
      final dataJson = jsonEncode({'necropcias': necropsiasSinEvidencias});
      final jsonSize = dataJson.length;
      request.fields['data'] = dataJson;

      // Log de verificación: verificar que las claves de archivos coincidan con evidencias_metadata
      debugPrint('🔍 Verificación de coincidencia de claves:');
      for (var necropsia in necropsiasSinEvidencias) {
        final evidenciasMetadata = necropsia['evidencias_metadata'] as Map<String, dynamic>? ?? {};
        evidenciasMetadata.forEach((metadataKey, metadataValue) {
          final cantidad = int.tryParse(metadataValue['cantidad']?.toString() ?? '0') ?? 0;
          debugPrint('   📋 Metadata key: $metadataKey, cantidad: $cantidad');

          // Verificar que existan archivos con esta clave
          for (int i = 0; i < cantidad; i++) {
            final expectedFileKey = 'evidencia_${metadataKey}_$i';
            final fileExists = request.files.any((file) => file.field == expectedFileKey);
            if (fileExists) {
              debugPrint('     ✓ Archivo encontrado: $expectedFileKey');
            } else {
              debugPrint('     ✗ Archivo NO encontrado: $expectedFileKey');
              // Buscar archivos similares
              for (var file in request.files) {
                if (file.field.contains(metadataKey) || file.field.contains('evidencia_')) {
                  debugPrint('       → Archivo similar encontrado: ${file.field}');
                }
              }
            }
          }
        });
      }

      // Calcular tamaño real de archivos leyendo desde disco
      // NOTA: Los archivos comprimidos están en tempDir y aún no se han eliminado
      int totalFilesSize = 0;
      final tempDir = await getTemporaryDirectory();
      final tempDirFiles = Directory(tempDir.path);

      // Buscar archivos comprimidos en el directorio temporal
      if (tempDirFiles.existsSync()) {
        final files = tempDirFiles.listSync(recursive: false);
        for (var file in files) {
          if (file is File && file.path.contains('compressed_')) {
            try {
              final fileSize = await file.length();
              totalFilesSize += fileSize;
              debugPrint('📁 Archivo temporal encontrado: ${path.basename(file.path)} - ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
            } catch (e) {
              debugPrint('⚠ Error al leer tamaño del archivo ${file.path}: $e');
            }
          }
        }
      }

      // Si no se encontraron archivos o el cálculo es 0, usar estimación conservadora
      if (totalFilesSize == 0 && request.files.isNotEmpty) {
        // Usar estimación de 6MB por archivo comprimido (más conservadora)
        totalFilesSize = request.files.length * 6 * 1024 * 1024;
        debugPrint('⚠ No se pudieron calcular tamaños reales, usando estimación: 6MB por archivo');
      }

      final totalEstimatedSize = jsonSize + totalFilesSize;
      debugPrint('📦 Tamaño del JSON: ${(jsonSize / 1024 / 1024).toStringAsFixed(2)} MB');
      debugPrint('📦 Tamaño real de archivos: ${(totalFilesSize / 1024 / 1024).toStringAsFixed(2)} MB');
      debugPrint('📦 Tamaño total estimado: ${(totalEstimatedSize / 1024 / 1024).toStringAsFixed(2)} MB');
      debugPrint('📦 Número de archivos agregados al request: ${request.files.length}');

      // Log detallado de cada archivo agregado
      for (int i = 0; i < request.files.length; i++) {
        final file = request.files[i];
        debugPrint('   📎 Archivo #${i + 1}: field=${file.field}, filename=${file.filename}');
      }

      // Límite de seguridad: 45MB (dejando margen al límite de 50MB del servidor)
      const maxSizeBytes = 45 * 1024 * 1024; // 45MB
      if (totalEstimatedSize > maxSizeBytes) {
        return {
          'success': false,
          'message': 'El tamaño total de los datos (${(totalEstimatedSize / 1024 / 1024).toStringAsFixed(2)} MB) excede el límite permitido (45 MB). Por favor, reduzca el número de imágenes o comprímalas más.',
          'total_size_mb': (totalEstimatedSize / 1024 / 1024).toStringAsFixed(2),
          'max_size_mb': '45',
        };
      }

      // CRÍTICO: Recopilar rutas de archivos temporales antes de enviar
      final tempFilesToDelete = <File>[];
      if (tempDirFiles.existsSync()) {
        final files = tempDirFiles.listSync(recursive: false);
        for (var f in files) {
          if (f is File && f.path.contains('compressed_')) {
            tempFilesToDelete.add(f);
          }
        }
      }

      // Enviar request
      debugPrint('📤 Enviando request multipart con ${request.files.length} archivos...');
      final streamedResponse = await request.send().timeout(const Duration(seconds: 180));
      final response = await http.Response.fromStream(streamedResponse);

      // Limpiar archivos temporales después de enviar
      for (var file in tempFilesToDelete) {
        try {
          if (file.existsSync()) {
            await file.delete();
            debugPrint('🗑️ Archivo temporal eliminado: ${file.path}');
          }
        } catch (e) {
          debugPrint('⚠️ Error al eliminar archivo temporal ${file.path}: $e');
        }
      }

      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response body: ${response.body}');

      // Verificar si la respuesta es JSON válido
      if (response.body.trim().isEmpty) {
        return {
          'success': false,
          'message': 'Respuesta vacía del servidor',
        };
      }

      // Intentar decodificar JSON
      Map<String, dynamic> responseData;
      try {
        responseData = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Error decodificando JSON: $e');
        debugPrint('Respuesta del servidor: ${response.body}');
        return {
          'success': false,
          'message': 'Error en la respuesta del servidor: ${response.body.substring(0, 100)}...',
        };
      }

      if (response.statusCode == 200) {
        return {
          'success': responseData['success'] ?? false,
          'code': responseData['code'],
          'message': responseData['message'] ?? 'Sin mensaje',
          'detalle': responseData['detalle'] ?? {},
          'codigosNecropsia': responseData['codigosNecropsia'] ??
              (responseData['detalle'] is Map
                  ? (responseData['detalle'] as Map)['codigosNecropsia']
                  : null),
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Error al guardar necropsias',
        };
      }
    } catch (e) {
      debugPrint('Error en uploadNecropsiasMovil: $e');
      return {
        'success': false,
        'message': 'Error de conexión: ${e.toString()}',
      };
    }
  }

  /// Actualiza registros de necropsia existentes (para ediciones)
  /// Similar a uploadNecropsiasMovil pero usa el endpoint de actualización
  Future<Map<String, dynamic>> updateNecropsiasMovil(
    List<Map<String, dynamic>> necropsias,
  ) async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}/necropcias/actualizar_necropsia_movil.php',
      );

      // Crear request multipart
      final request = http.MultipartRequest('POST', url);

      // Agregar headers de autorización
      request.headers.addAll({
        'Authorization': 'Bearer ${AppConstants.apiToken}',
      });

      // Separar evidencias de cada necropsia para enviarlas como archivos
      final necropsiasSinEvidencias = <Map<String, dynamic>>[];

      for (var necropsia in necropsias) {
        final necropsiaSinEvidencias = Map<String, dynamic>.from(necropsia);
        final evidenciasCompletas = necropsia['evidencias_completas'] as Map<String, dynamic>? ?? {};

        debugPrint('📸 updateNecropsiasMovil - Procesando necropsia:');
        debugPrint('   - tuuid: ${necropsia['tuuid']}');
        debugPrint('   - evidencias_completas presente: ${evidenciasCompletas.isNotEmpty}');
        debugPrint('   - niveles con evidencias: ${evidenciasCompletas.keys.length}');
        if (evidenciasCompletas.isNotEmpty) {
          evidenciasCompletas.forEach((key, value) {
            final imagenes = value as List? ?? [];
            debugPrint('     - $key: ${imagenes.length} imágenes');
          });
        }

        // Extraer evidencias para enviarlas como archivos
        necropsiaSinEvidencias.remove('evidencias');
        necropsiaSinEvidencias.remove('evidencias_completas');

        // Agregar información de evidencias como metadata (nivel + cantidad)
        final evidenciasMetadata = <String, Map<String, String>>{};

        // Procesar evidencias por nivel (mismo código que uploadNecropsiasMovil)
        // CRÍTICO: Usar bucle for normal con await en lugar de Future.forEach
        // para asegurar que todas las imágenes se procesen secuencialmente
        for (var entry in evidenciasCompletas.entries) {
          final nivelKey = entry.key;
          final imagenesListRaw = entry.value;

          // CRÍTICO: Asegurar que imagenesList sea una List, convertir si es necesario
          List<dynamic> imagenesList = [];
          if (imagenesListRaw is List) {
            imagenesList = imagenesListRaw;
          } else if (imagenesListRaw != null) {
            debugPrint('⚠️ imagenesList no es List, tipo: ${imagenesListRaw.runtimeType}, convirtiendo...');
            imagenesList = [imagenesListRaw];
          }

          debugPrint('   📸 Procesando nivel $nivelKey con ${imagenesList.length} imágenes');

          if (imagenesList.isNotEmpty) {
            final primeraImagen = imagenesList[0] as Map<String, dynamic>? ?? {};
            final sistema = primeraImagen['sistema'] ?? '';
            final nivel = primeraImagen['nivel'] ?? '';

            final normalizedKey = nivelKey.replaceAll(' ', '_').replaceAll('/', '_').replaceAll('\\', '_');

            evidenciasMetadata[normalizedKey] = {
              'sistema': sistema,
              'nivel': nivel,
              'cantidad': imagenesList.length.toString(),
              'original_key': nivelKey,
            };

            // Agregar cada imagen del nivel al request (con compresión)
            for (int localIndex = 0; localIndex < imagenesList.length; localIndex++) {
              final imagenData = imagenesList[localIndex];
              if (imagenData is Map<String, dynamic>) {
                final imagePath = imagenData['path'] as String? ?? '';
                if (imagePath.isNotEmpty) {
                  try {
                    final originalFile = File(imagePath);
                    if (originalFile.existsSync()) {
                      final originalSize = await originalFile.length();

                      if (originalSize > 0) {
                        File? compressedFile;
                        String? compressedPath;

                        try {
                          final tempDir = await getTemporaryDirectory();
                          // Igual que en upload: convertir a JPG para reducir tamaño total y evitar límites del backend (p.ej. 8MB).
                          final fileName =
                              'compressed_${DateTime.now().millisecondsSinceEpoch}_${normalizedKey}_$localIndex.jpg';
                          compressedPath = path.join(tempDir.path, fileName);

                          // Compresión adaptativa para no reventar límites del backend (p.ej. 8MB por request).
                          final int maxDim = originalSize > 2 * 1024 * 1024 ? 1024 : 1280;
                          final int quality = originalSize > 2 * 1024 * 1024 ? 60 : 70;

                          final compressedData = await FlutterImageCompress.compressWithFile(
                            imagePath,
                            minWidth: maxDim,
                            minHeight: maxDim,
                            quality: quality,
                            format: CompressFormat.jpeg,
                          );

                          if (compressedData != null && compressedData.isNotEmpty) {
                            compressedFile = File(compressedPath);
                            await compressedFile.writeAsBytes(compressedData);

                            // CRÍTICO: Verificar que el archivo se haya escrito correctamente
                            if (!compressedFile.existsSync()) {
                              debugPrint('✗ Error: El archivo comprimido no existe después de escribirlo: $compressedPath');
                              continue;
                            }

                            final compressedSize = await compressedFile.length();
                            if (compressedSize == 0) {
                              debugPrint('✗ Error: El archivo comprimido está vacío: $compressedPath');
                              continue;
                            }

                            final granja = necropsia['granja'] ?? '';
                            final galpon = necropsia['galpon'] ?? '';
                            final numreg = necropsia['numreg'] ?? '';
                            final fectra = (necropsia['fectra'] as String? ?? '').replaceAll('-', '');
                            final sistemaLower = sistema.toLowerCase();
                            final nivelLower = nivel.toLowerCase().replaceAll(' ', '_').replaceAll('/', '_');

                            final finalExtension = 'jpg';
                            final finalFileName = '${granja}_${galpon}_${numreg}_${fectra}_${sistemaLower}_${nivelLower}_$localIndex.$finalExtension';

                            final fileKey = 'evidencia_${normalizedKey}_$localIndex';

                            try {
                              final multipartFile = await http.MultipartFile.fromPath(
                                fileKey,
                                compressedFile.path, // Usar compressedFile.path en lugar de compressedPath
                                filename: finalFileName,
                              );
                              request.files.add(multipartFile);
                              debugPrint('✓ Imagen agregada al request (update): $finalFileName (key: $fileKey, size: ${compressedSize} bytes)');

                              // Limpiar archivo temporal después de un delay
                              Future.delayed(const Duration(seconds: 30), () {
                                try {
                                  if (compressedFile != null && compressedFile.existsSync()) {
                                    compressedFile.deleteSync();
                                  }
                                } catch (e) {
                                  debugPrint('Error al eliminar archivo temporal: $e');
                                }
                              });
                            } catch (e) {
                              debugPrint('✗ Error al crear MultipartFile (update): $e');
                            }
                          } else {
                            debugPrint('⚠ Error: No se pudo comprimir la imagen [$normalizedKey][$localIndex] o los datos están vacíos');
                            // Fallback: enviar original (esto pasa seguido con PNG editados)
                            final originalFileCheck = File(imagePath);
                            if (!originalFileCheck.existsSync()) {
                              debugPrint('✗ Error: El archivo original no existe: $imagePath');
                              continue;
                            }

                            try {
                              final fileBytes = await originalFileCheck.readAsBytes();
                              if (fileBytes.isEmpty) {
                                debugPrint('✗ Error: El archivo original está vacío al leerlo: $imagePath');
                                continue;
                              }

                              final granja = necropsia['granja'] ?? '';
                              final galpon = necropsia['galpon'] ?? '';
                              final numreg = necropsia['numreg'] ?? '';
                              final fectra = (necropsia['fectra'] as String? ?? '').replaceAll('-', '');
                              final sistemaLower = sistema.toLowerCase();
                              final nivelLower = nivel.toLowerCase().replaceAll(' ', '_').replaceAll('/', '_');

                              final originalExt = path.extension(imagePath).replaceAll('.', '').toLowerCase();
                              final safeExt = originalExt.isEmpty ? 'jpg' : originalExt;
                              final fileName = '${granja}_${galpon}_${numreg}_${fectra}_${sistemaLower}_${nivelLower}_$localIndex.$safeExt';

                              final fileKey = 'evidencia_${normalizedKey}_$localIndex';
                              final multipartFile = http.MultipartFile.fromBytes(
                                fileKey,
                                fileBytes,
                                filename: fileName,
                              );
                              request.files.add(multipartFile);
                              debugPrint('✓ Imagen original (fallback) agregada (update): $fileName (key: $fileKey, size: ${fileBytes.length} bytes)');
                            } catch (e) {
                              debugPrint('✗ Error al crear MultipartFile para imagen original (fallback update): $e');
                            }
                          }
                        } catch (compressionError) {
                          debugPrint('⚠ Error al comprimir imagen: $compressionError');
                          // Intentar enviar original si es pequeña
                          if (originalSize <= 5 * 1024 * 1024) {
                            final originalFileCheck = File(imagePath);
                            if (!originalFileCheck.existsSync()) {
                              debugPrint('✗ Error: El archivo original no existe: $imagePath');
                              continue;
                            }

                            final granja = necropsia['granja'] ?? '';
                            final galpon = necropsia['galpon'] ?? '';
                            final numreg = necropsia['numreg'] ?? '';
                            final fectra = (necropsia['fectra'] as String? ?? '').replaceAll('-', '');
                            final sistemaLower = sistema.toLowerCase();
                            final nivelLower = nivel.toLowerCase().replaceAll(' ', '_').replaceAll('/', '_');

                            final extension = imagePath.split('.').last.toLowerCase();
                            final fileName = '${granja}_${galpon}_${numreg}_${fectra}_${sistemaLower}_${nivelLower}_$localIndex.$extension';

                            final fileKey = 'evidencia_${normalizedKey}_$localIndex';

                            try {
                              // CRÍTICO: Leer el archivo en bytes ANTES de crear el MultipartFile
                              final fileBytes = await originalFileCheck.readAsBytes();
                              if (fileBytes.isEmpty) {
                                debugPrint('✗ Error: El archivo original está vacío al leerlo: $imagePath');
                                continue;
                              }

                              // Crear MultipartFile desde bytes en lugar de fromPath
                              final multipartFile = http.MultipartFile.fromBytes(
                                fileKey,
                                fileBytes,
                                filename: fileName,
                              );
                              request.files.add(multipartFile);
                              debugPrint('✓ Imagen original agregada (update): $fileName (key: $fileKey, size: ${fileBytes.length} bytes)');
                            } catch (e) {
                              debugPrint('✗ Error al crear MultipartFile para imagen original (update): $e');
                            }
                          }
                        }
                      }
                    }
                  } catch (e) {
                    debugPrint('✗ Error al procesar imagen: $e');
                  }
                }
              }
            }
          }
        }

        // Agregar metadata de evidencias al JSON
        if (evidenciasMetadata.isNotEmpty) {
          necropsiaSinEvidencias['evidencias_metadata'] = evidenciasMetadata;
        }

        necropsiasSinEvidencias.add(necropsiaSinEvidencias);
      }

      // Agregar datos JSON al request
      final dataJson = jsonEncode({'necropcias': necropsiasSinEvidencias});
      request.fields['data'] = dataJson;

      debugPrint('📦 updateNecropsiasMovil - Número de archivos agregados al request: ${request.files.length}');

      // Log detallado de cada archivo agregado
      for (int i = 0; i < request.files.length; i++) {
        final file = request.files[i];
        debugPrint('   📎 Archivo #${i + 1}: field=${file.field}, filename=${file.filename}');
      }

      // Enviar request
      final streamedResponse = await request.send().timeout(const Duration(seconds: 180));
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('Response status (update): ${response.statusCode}');
      debugPrint('Response body (update): ${response.body}');

      if (response.body.trim().isEmpty) {
        return {
          'success': false,
          'message': 'Respuesta vacía del servidor',
        };
      }

      Map<String, dynamic> responseData;
      try {
        responseData = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Error decodificando JSON: $e');
        return {
          'success': false,
          'message': 'Error en la respuesta del servidor',
        };
      }

      if (response.statusCode == 200) {
        return {
          'success': responseData['success'] ?? false,
          'code': responseData['code'],
          'message': responseData['message'] ?? 'Sin mensaje',
          'detalle': responseData['detalle'] ?? {},
          'codigosNecropsia': responseData['codigosNecropsia'] ??
              (responseData['detalle'] is Map
                  ? (responseData['detalle'] as Map)['codigosNecropsia']
                  : null),
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Error al actualizar necropsias',
        };
      }
    } catch (e) {
      debugPrint('Error en updateNecropsiasMovil: $e');
      return {
        'success': false,
        'message': 'Error de conexión: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> buscarGriDisponibles({
    required String granja,
    required String campania,
    required String galpon,
    String modulo = 'NECROPSIA',
  }) async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}/buscar_gri_disponibles_movil.php',
      ).replace(
        queryParameters: {
          'granja': granja,
          'campania': campania,
          'galpon': galpon,
          'modulo': modulo,
        },
      );
      final response = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 30));
      final body = response.body.trim();
      if (response.statusCode == 200 && body.isNotEmpty) {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      }
      debugPrint(
        'buscarGriDisponibles HTTP ${response.statusCode}: ${body.length > 200 ? body.substring(0, 200) : body}',
      );
      return {
        'success': false,
        'items': <dynamic>[],
        'message': 'Error al cargar GRI (${response.statusCode})',
      };
    } catch (e) {
      debugPrint('buscarGriDisponibles: $e');
      return {'success': false, 'items': [], 'message': e.toString()};
    }
  }

  /// Previsualiza el siguiente código NEC-0YYnnnn (orientativo; el definitivo lo asigna el servidor al guardar).
  Future<Map<String, dynamic>> fetchCodigoNecropsia() async {
    try {
      final response = await http.get(
        Uri.parse(
          '${AppConstants.baseUrl}/necropcias/reserve_codigo_necropsia.php',
        ),
        headers: {
          'Authorization': 'Bearer ${AppConstants.apiToken}',
          'Content-Type': 'application/json',
        },
      );
      final body = response.body.trim();
      if (response.statusCode == 200 && body.isNotEmpty) {
        final dynamic decoded = jsonDecode(body);
        if (decoded is! Map<String, dynamic>) {
          return {
            'success': false,
            'message': 'Respuesta inválida del servidor',
          };
        }
        final data = decoded;
        if (data['codigoNecropsia'] != null &&
            data['codigoNecropsia'].toString().trim().isNotEmpty) {
          return {
            'success': true,
            'codigoNecropsia': data['codigoNecropsia'].toString().trim(),
          };
        }
        return {
          'success': false,
          'message': data['error']?.toString() ?? 'No se pudo obtener el código',
        };
      }
      return {'success': false, 'message': 'Error HTTP ${response.statusCode}'};
    } catch (e) {
      debugPrint('Error fetchCodigoNecropsia: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<List<Cenco>> getCencos() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/necropcias/get_cencos.php'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          return (data['data']['cencos'] as List)
              .map((e) => Cenco.fromJson(e))
              .toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error cargando cencos: $e');
      return [];
    }
  }

  Future<List<Galpon>> getGalpones(String cencoCode) async {

    try {
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/necropcias/get_galpones.php?tcencos=$cencoCode'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          return (data['data']['galpones'] as List)
              .map((e) => Galpon.fromJson(e))
              .toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error cargando galpones: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> downloadCencosGalpones() async {
    try {
      debugPrint('📥 Descargando CENCOS y galpones desde get_cencos_galpones.php...');
      final usuario = await _getUsuarioSesion();
      final baseUri = Uri.parse('${AppConstants.baseUrl}/necropcias/get_cencos_galpones.php');
      final uri = usuario.isNotEmpty
          ? baseUri.replace(queryParameters: {'usuario': usuario})
          : baseUri;
      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));
      debugPrint('Response body: ${response.body}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true && data['data'] != null) {
          final cencosData = data['data']['cencos'] as List<dynamic>;

          // Convertir CENCOS
          final List<Cenco> cencos = cencosData
              .map((e) => Cenco.fromJson(e as Map<String, dynamic>))
              .toList();

          // Convertir galpones agrupados por CENCO
          final Map<String, List<Galpon>> galponesPorCenco = {};

          for (var cencoData in cencosData) {
            final cencoMap = cencoData as Map<String, dynamic>;
            final codigoCenco = cencoMap['codigo'] as String;
            final galponesData = cencoMap['galpones'] as List<dynamic>? ?? [];

            galponesPorCenco[codigoCenco] = galponesData
                .map((g) => Galpon(
                      tcencos: codigoCenco,
                      tcodint: g['tcodint']?.toString() ?? '',
                      fecIngMin: g['fec_ing_min']?.toString(),
                    ))
                .toList();
          }

          debugPrint('✅ Descargados ${cencos.length} CENCOS con sus galpones');

          return {
            'success': true,
            'cencos': cencos,
            'galponesPorCenco': galponesPorCenco,
          };
        } else {
          debugPrint('⚠️ Respuesta del servidor sin datos válidos');
          return {
            'success': false,
            'message': data['message'] ?? 'No se encontraron datos',
          };
        }
      } else {
        debugPrint('❌ Error HTTP: ${response.statusCode}');
        return {
          'success': false,
          'message': 'Error HTTP ${response.statusCode}',
        };
      }
    } catch (e) {
      debugPrint('❌ Error descargando CENCOS y galpones: $e');
      return {
        'success': false,
        'message': 'Error de conexión: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> downloadPlanMatchCandidates({
    required DateTime desde,
    required DateTime hasta,
    String tipo = 'NC',
  }) async {
    try {
      final usuario = await _getUsuarioSesion();
      final desdeStr =
          '${desde.year}-${desde.month.toString().padLeft(2, '0')}-${desde.day.toString().padLeft(2, '0')}';
      final hastaStr =
          '${hasta.year}-${hasta.month.toString().padLeft(2, '0')}-${hasta.day.toString().padLeft(2, '0')}';
      final query = <String, String>{'desde': desdeStr, 'hasta': hastaStr, 'tipo': tipo};
      if (usuario.isNotEmpty) query['usuario'] = usuario;
      final uri = Uri.parse(
        '${AppConstants.baseUrl}/necropcias/get_plan_match_candidates_movil.php',
      ).replace(
        queryParameters: query,
      );

      final response = await http
          .get(uri, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return {'success': false, 'message': 'Error HTTP ${response.statusCode}'};
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['success'] == true && data['data'] is Map<String, dynamic>) {
        final payload = data['data'] as Map<String, dynamic>;
        return {
          'success': true,
          'desde': payload['desde']?.toString() ?? desdeStr,
          'hasta': payload['hasta']?.toString() ?? hastaStr,
          'total': payload['total'] ?? 0,
          'candidatos': payload['candidatos'] as List<dynamic>? ?? <dynamic>[],
        };
      }
      return {
        'success': false,
        'message': data['message']?.toString() ?? 'No se pudo descargar candidatos',
      };
    } catch (e) {
      return {'success': false, 'message': 'Error de conexión: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> savePlanificacionEventual(
    Map<String, dynamic> payload,
  ) async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}/necropcias/guardar_asignacion_eventual_movil.php',
      );
      final response = await http
          .post(url, headers: _headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return {
          'success': data['success'] ?? false,
          'message': data['message'] ?? '',
          'planId': data['planId']?.toString() ?? '',
        };
      }
      return {
        'success': false,
        'message': data['message']?.toString() ?? 'Error HTTP ${response.statusCode}',
      };
    } catch (e) {
      return {'success': false, 'message': 'Error de conexión: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> saveNecropsia(Map<String, dynamic> data) async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}/necropcias/guardar_necropsia.php',
      );

      final body = jsonEncode(data);

      final response = await http
          .post(url, headers: _headers, body: body)
          .timeout(const Duration(seconds: 60));

      final responseData = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return {
          'success': responseData['success'] ?? false,
          'message': responseData['message'] ?? 'Sin mensaje',
          'data': responseData['data'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Error al guardar necropsia',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error de conexión: ${e.toString()}',
      };
    }
  }

  // Obtener necropsias con paginación
  Future<Map<String, dynamic>> getNecropsias({
    required int page,
    required int pageSize,
  }) async {
    try {
      final url = Uri.parse(
        '${AppConstants.baseUrl}/necropcias/obtener_necropsias.php?page=$page&pageSize=$pageSize',
      );

      final response = await http.get(
        url,
        headers: _headers,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        return {
          'success': false,
          'message': 'Error HTTP ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error de conexión: ${e.toString()}',
      };
    }
  }
}
