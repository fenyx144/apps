import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html_to_pdf/html_to_pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:image/image.dart' as img;
import '../utils/constants.dart';
import 'package:intl/intl.dart';

class ReportService {
  // Cargar logo de la empresa como base64
  // Cache del logo para evitar cargarlo múltiples veces
  String? _logoCache;

  // Flag para saber si la librería PDF ya fue inicializada
  bool _pdfInitialized = false;
  bool _isInitializing = false;

  Future<String?> _loadLogoBase64() async {
    // Si ya está en cache, retornarlo inmediatamente
    if (_logoCache != null) {
      return _logoCache;
    }

    try {
      final ByteData data = await rootBundle.load('assets/icon/icon.png');
      final Uint8List bytes = data.buffer.asUint8List();
      _logoCache = base64Encode(bytes);
      return _logoCache;
    } catch (e) {
      debugPrint('Error cargando logo: $e');
      return null;
    }
  }

  // Convertir imagen a base64 (más grande para el segundo reporte)
  String? _imageToBase64(String? imagePath, {bool larger = false}) {
    if (imagePath == null || imagePath.isEmpty) return null;
    try {
      final imageFile = File(imagePath);
      if (imageFile.existsSync()) {
        final imageBytes = imageFile.readAsBytesSync();
        final image = img.decodeImage(imageBytes);
        if (image != null) {
          final resizedImage = img.copyResize(
            image,
            width: larger ? 320 : 240,
            height: larger ? 250 : 200,
            maintainAspect: true,
          );
          final resizedBytes = img.encodeJpg(resizedImage, quality: 85);
          return base64Encode(resizedBytes);
        }
      }
    } catch (e) {
      debugPrint('Error convirtiendo imagen a base64: $e');
    }
    return null;
  }

  /// Pre-inicializa la librería PDF para evitar demoras en la primera generación
  /// Este método puede ser llamado en background cuando se carga la pantalla de reportes
  Future<void> initializePdfLibrary() async {
    if (_pdfInitialized || _isInitializing) return;

    _isInitializing = true;
    try {
      debugPrint('🔄 Pre-inicializando librería PDF...');
      final targetPath = await getTemporaryDirectory();

      final dummyHtml = '<html><body><p>Test</p></body></html>';
      await HtmlToPdf.convertFromHtmlContent(
        htmlContent: dummyHtml,
        printPdfConfiguration: PrintPdfConfiguration(
          targetDirectory: targetPath.path,
          targetName: 'dummy_init_${DateTime.now().millisecondsSinceEpoch}.pdf',
          printSize: PrintSize.A4,
          printOrientation: PrintOrientation.Portrait,
        ),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('⚠️ Timeout en pre-inicialización, continuando...');
          return Future.value(File(''));
        },
      );

      _pdfInitialized = true;
      debugPrint('✅ Librería PDF pre-inicializada correctamente');
    } catch (e) {
      debugPrint('⚠️ Error en pre-inicialización PDF (no crítico): $e');
      // No es crítico, la librería se inicializará en la primera generación real
    } finally {
      _isInitializing = false;
    }
  }

  /// Genera el Reporte 1 (similar a generar_reporte.php tipo 1)
  /// Formato: Tabla con sistemas, niveles, parámetros, porcentajes y observaciones
  Future<void> generateReport1({
    required Map<String, dynamic> cabecera,
    required List<Map<String, dynamic>> registros,
    required BuildContext context,
  }) async {
    try {
      // Pre-inicializar la librería PDF si no está inicializada (en background)
      if (!_pdfInitialized && !_isInitializing) {
        initializePdfLibrary();
      }

      // Cargar logo de forma asíncrona (con cache para evitar cargas repetidas)
      String? logoBase64;
      try {
        logoBase64 = await _loadLogoBase64().timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            debugPrint('Timeout cargando logo, continuando sin logo');
            return null;
          },
        );
      } catch (e) {
        debugPrint('Error cargando logo: $e, continuando sin logo');
        logoBase64 = null;
      }

      // Generar HTML de forma síncrona (es rápido)
      final html = _generateReport1HTML(cabecera, registros, logoBase64);
      debugPrint('HTML generado, longitud: ${html.length} caracteres');

      // Obtener directorio temporal
      final targetPath = await getTemporaryDirectory();
      debugPrint('Directorio temporal: ${targetPath.path}');

      // Esperar a que la pre-inicialización termine si está en proceso
      if (_isInitializing) {
        debugPrint('⏳ Esperando pre-inicialización de PDF...');
        int waitCount = 0;
        while (_isInitializing && waitCount < 30) {
          await Future.delayed(const Duration(milliseconds: 100));
          waitCount++;
        }
      }

      // Generar PDF desde HTML
      debugPrint('Iniciando conversión HTML a PDF...');
      final startTime = DateTime.now();

      final generatedPdfFile =
          await HtmlToPdf.convertFromHtmlContent(
            htmlContent: html,
            printPdfConfiguration: PrintPdfConfiguration(
              targetDirectory: targetPath.path,
              targetName:
                  'reporte_necropsia_${DateTime.now().millisecondsSinceEpoch}.pdf',
              printSize: PrintSize.A4,
              printOrientation: PrintOrientation.Portrait,
            ),
          ).timeout(
            const Duration(
              seconds: 60,
            ), // Timeout más largo para la primera vez
            onTimeout: () {
              final elapsed = DateTime.now().difference(startTime);
              debugPrint('Timeout después de ${elapsed.inSeconds} segundos');
              throw TimeoutException(
                'La generación del PDF tardó demasiado (${elapsed.inSeconds}s). Intente nuevamente.',
                const Duration(seconds: 60),
              );
            },
          );

      final elapsed = DateTime.now().difference(startTime);
      debugPrint('PDF generado exitosamente en ${elapsed.inMilliseconds}ms');

      // Leer el PDF generado
      final pdfBytes = await generatedPdfFile.readAsBytes().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException(
            'Error leyendo el PDF generado',
            const Duration(seconds: 5),
          );
        },
      );
      debugPrint('PDF leído, tamaño: ${pdfBytes.length} bytes');

      if (!context.mounted) {
        debugPrint('Context no está montado, cancelando navegación');
        return;
      }

      await _showPdfWithBackButton(context, pdfBytes, 'Reporte Tabla');
    } on TimeoutException catch (e) {
      debugPrint('Timeout generando Reporte 1: $e');
      if (context.mounted) {
        throw Exception(
          'La generación del PDF tardó demasiado. Por favor, intente nuevamente.',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Error generando Reporte 1: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  String _generateReport1HTML(
    Map<String, dynamic> cabecera,
    List<Map<String, dynamic>> registros,
    String? logoBase64,
  ) {
    // Agrupar registros por sistema
    final Map<String, List<Map<String, dynamic>>> porSistema = {};
    for (var reg in registros) {
      final sistema = reg['tsistema']?.toString() ?? '';
      if (sistema.isNotEmpty) {
        porSistema.putIfAbsent(sistema, () => []).add(reg);
      }
    }

    // Asegurar que todos los sistemas estén presentes
    final sistemasEsperados = [
      'SISTEMA INMUNOLOGICO',
      'SISTEMA DIGESTIVO',
      'SISTEMA RESPIRATORIO',
      'EVALUACION FISICA',
    ];
    for (var sistema in sistemasEsperados) {
      if (!porSistema.containsKey(sistema)) {
        porSistema[sistema] = [];
      }
    }

    final buffer = StringBuffer();

    buffer.write('<!DOCTYPE html>');
    buffer.write('<html>');
    buffer.write('<head>');
    buffer.write('<meta charset="UTF-8">');
    buffer.write('<style>');
    buffer.write(
      '@page { margin-top: 30mm; margin-bottom: 25mm; margin-left: 15mm; margin-right: 15mm; @bottom-center { content: "Página " counter(page) " de " counter(pages); font-size: 9pt; } }',
    );
    buffer.write(
      'body { font-family: Arial, sans-serif; font-size: 9pt; color: #000; margin: 0; padding: 20px 20px 0 20px; position: relative; }',
    );
    buffer.write(
      '.date-time-header { position: absolute; top: 0; right: 0; font-size: 9pt; padding: 5px; }',
    );
    buffer.write(
      '.header-title { width: 100%; border-collapse: collapse; border: 1px solid #cbd5e1; margin-top: 20px; page-break-after: avoid; }',
    );
    buffer.write('.header-title td { padding: 5px; }');
    buffer.write(
      '.info-table { width: 100%; border-collapse: collapse; margin: 10px 0; page-break-after: avoid; }',
    );
    buffer.write(
      '.info-table th { background-color: #e6f2ff; padding: 5px; text-align: center; border: 1px solid #cbd5e1; font-weight: bold; page-break-inside: avoid; }',
    );
    buffer.write(
      '.info-table td { padding: 5px; text-align: center; border: 1px solid #cbd5e1; page-break-inside: avoid; }',
    );
    buffer.write(
      'table { width: 100%; border-collapse: collapse; margin: 10px 0; font-size: 9pt; border-top: 1px solid #cbd5e1; page-break-inside: auto; }',
    );
    buffer.write('tr { page-break-inside: avoid; page-break-after: auto; }');
    buffer.write(
      'th { background-color: #e6f2ff; padding: 5px; text-align: center; border: 1px solid #cbd5e1; font-weight: bold; page-break-inside: avoid; }',
    );
    buffer.write(
      'td { padding: 5px; border: 1px solid #cbd5e1; vertical-align: top; page-break-inside: avoid; }',
    );
    buffer.write(
      '.nivel-cell { background-color: #e6f2ff; font-weight: bold; text-align: center; width: 20%; }',
    );
    buffer.write('.param-cell { width: 35%; }');
    buffer.write('.porc-cell { text-align: center; width: 15%; }');
    buffer.write('.obs-cell { width: 30%; }');
    buffer.write('.diagnostico-section { margin-top: 20px; page-break-inside: avoid; }');
    buffer.write('.diagnostico-title { background-color: #e6f2ff; font-weight: bold; text-align: center; padding: 5px; border: 1px solid #cbd5e1; page-break-inside: avoid; }');
    buffer.write('.diagnostico-content { padding: 8px; border: 1px solid #cbd5e1; border-top: none; text-align: left; page-break-inside: avoid; }');
    buffer.write('</style>');
    buffer.write('</head>');
    buffer.write('<body>');

    // === Fecha y hora en la parte superior derecha ===
    final now = DateTime.now();
    final fechaHora = DateFormat('dd/MM/yyyy HH:mm').format(now);
    buffer.write('<div class="date-time-header">$fechaHora</div>');

    // === Cabecera conjunta ===
    buffer.write(
      '<table width="100%" style="border-collapse: collapse; border: 1px solid #cbd5e1; margin-top: 20px; page-break-after: avoid;">',
    );
    buffer.write('<tr>');
    if (logoBase64 != null) {
      buffer.write(
        '<td style="width: 20%; text-align: left; padding: 5px; background-color: #fff; font-size: 8pt; white-space: nowrap;">',
      );
      buffer.write('<img src="data:image/png;base64,');
      buffer.write(logoBase64);
      buffer.write('" style="height: 20px; vertical-align: top;" />');
      buffer.write(' GRANJA RINCONADA DEL SUR S.A.');
      buffer.write('</td>');
    } else {
      buffer.write(
        '<td style="width: 20%; text-align: left; padding: 5px; background-color: #fff;"></td>',
      );
    }
    buffer.write(
      '<td style="width: 60%; text-align: center; padding: 5px; background-color: #e6f2ff; color: #000; font-weight: bold; font-size: 14px;">',
    );
    buffer.write('REPORTE DE NECROPSIA');
    buffer.write('</td>');
    buffer.write(
      '<td style="width: 20%; text-align: center; padding: 5px; background-color: #fff; font-weight: bold;">',
    );
    final codigoNec =
        cabecera['codigoNecropsia']?.toString() ??
        cabecera['tcodnecropsia']?.toString() ??
        '';
    if (codigoNec.trim().isNotEmpty) {
      buffer.write(
        'Cód: ${_escapeHtml(codigoNec)} &nbsp; N°Reg: ${_escapeHtml(cabecera['numreg']?.toString() ?? '?')}',
      );
    } else {
      buffer.write('N°Reg: ${_escapeHtml(cabecera['numreg']?.toString() ?? '?')}');
    }
    buffer.write('</td>');
    buffer.write('</tr>');
    buffer.write('</table>');

    buffer.write('<table class="info-table">');
    buffer.write('<tr>');
    buffer.write(
      '<th style="background-color: #e6f2ff; font-weight: bold; text-align: center; padding: 5px; border: 1px solid #cbd5e1; page-break-inside: avoid;">Fecha</th>',
    );
    buffer.write(
      '<th style="background-color: #e6f2ff; font-weight: bold; text-align: center; padding: 5px; border: 1px solid #cbd5e1; page-break-inside: avoid;">Granja</th>',
    );
    buffer.write(
      '<th style="background-color: #e6f2ff; font-weight: bold; text-align: center; padding: 5px; border: 1px solid #cbd5e1; page-break-inside: avoid;">Campaña</th>',
    );
    buffer.write(
      '<th style="background-color: #e6f2ff; font-weight: bold; text-align: center; padding: 5px; border: 1px solid #cbd5e1; page-break-inside: avoid;">Galpón</th>',
    );
    buffer.write(
      '<th style="background-color: #e6f2ff; font-weight: bold; text-align: center; padding: 5px; border: 1px solid #cbd5e1; page-break-inside: avoid;">Edad</th>',
    );
    buffer.write('</tr>');
    buffer.write('<tr>');
    buffer.write(
      '<td style="padding: 5px; text-align: center; border: 1px solid #cbd5e1; page-break-inside: avoid;">',
    );
    buffer.write(_formatDate(cabecera['fectra']?.toString()));
    buffer.write('</td>');
    buffer.write(
      '<td style="padding: 5px; text-align: center; border: 1px solid #cbd5e1; page-break-inside: avoid;">',
    );
    buffer.write(_escapeHtml(cabecera['tgranja']?.toString() ?? ''));
    buffer.write('</td>');
    buffer.write(
      '<td style="padding: 5px; text-align: center; border: 1px solid #cbd5e1; page-break-inside: avoid;">',
    );
    buffer.write(_escapeHtml(cabecera['tcampania']?.toString() ?? ''));
    buffer.write('</td>');
    buffer.write(
      '<td style="padding: 5px; text-align: center; border: 1px solid #cbd5e1; page-break-inside: avoid;">',
    );
    buffer.write(_escapeHtml(cabecera['tgalpon']?.toString() ?? ''));
    buffer.write('</td>');
    buffer.write(
      '<td style="padding: 5px; text-align: center; border: 1px solid #cbd5e1; page-break-inside: avoid;">',
    );
    buffer.write(_escapeHtml(cabecera['tedad']?.toString() ?? ''));
    buffer.write(' días</td>');
    buffer.write('</tr>');
    
    // Fila de Inicio y Fin de Registro (ambos en la misma fila)
    buffer.write('<tr>');
    buffer.write(
      '<td style="padding: 5px; text-align: center; border: 1px solid #cbd5e1; page-break-inside: avoid; background-color: #e6f2ff; font-weight: bold;">',
    );
    buffer.write('Inicio de Registro');
    buffer.write('</td>');
    buffer.write(
      '<td style="padding: 5px; text-align: center; border: 1px solid #cbd5e1; page-break-inside: avoid;">',
    );
    buffer.write(_formatDateTime(cabecera['tfecreghorainicio']?.toString()));
    buffer.write('</td>');
    buffer.write(
      '<td style="padding: 5px; text-align: center; border: 1px solid #cbd5e1; page-break-inside: avoid; background-color: #e6f2ff; font-weight: bold;">',
    );
    buffer.write('Fin de Registro');
    buffer.write('</td>');
    buffer.write(
      '<td style="padding: 5px; text-align: center; border: 1px solid #cbd5e1; page-break-inside: avoid;">',
    );
    buffer.write(_formatDateTime(cabecera['tfecreghorafin']?.toString()));
    buffer.write('</td>');
    buffer.write(
      '<td style="padding: 5px; text-align: center; border: 1px solid #cbd5e1; page-break-inside: avoid;"></td>',
    );
    buffer.write('</tr>');
    buffer.write('</table>');

    // Tablas por sistema
    for (var sistemaEntry in porSistema.entries) {
      final sistema = sistemaEntry.key;
      final regs = sistemaEntry.value;

      // Agrupar por nivel
      final Map<String, List<Map<String, dynamic>>> porNivel = {};
      for (var r in regs) {
        final nivel = r['tnivel']?.toString() ?? '';
        if (nivel.isNotEmpty) {
          porNivel.putIfAbsent(nivel, () => []).add(r);
        }
      }

      buffer.write('<table>');
      // Encabezado del sistema (una fila que abarca las 4 columnas)
      buffer.write('<tr>');
      buffer.write(
        '<th colspan="4" style="background-color: #e6f2ff; font-weight: bold; text-align: left; padding: 5px 8px; border: 1px solid #cbd5e1; page-break-inside: avoid;">',
      );
      buffer.write(_escapeHtml(sistema.toUpperCase()));
      buffer.write('</th>');
      buffer.write('</tr>');
      // Encabezados de columnas
      buffer.write('<tr>');
      buffer.write(
        '<th style="background-color: #e6f2ff; font-weight: bold; text-align: center; padding: 5px; border: 1px solid #cbd5e1; page-break-inside: avoid;">Nivel</th>',
      );
      buffer.write(
        '<th style="background-color: #e6f2ff; font-weight: bold; text-align: center; padding: 5px; border: 1px solid #cbd5e1; page-break-inside: avoid;">Parámetro</th>',
      );
      buffer.write(
        '<th style="background-color: #e6f2ff; font-weight: bold; text-align: center; padding: 5px; border: 1px solid #cbd5e1; page-break-inside: avoid;">%</th>',
      );
      buffer.write(
        '<th style="background-color: #e6f2ff; font-weight: bold; text-align: center; padding: 5px; border: 1px solid #cbd5e1; page-break-inside: avoid;">Observaciones</th>',
      );
      buffer.write('</tr>');

      for (var nivelEntry in porNivel.entries) {
        final nivel = nivelEntry.key;
        final items = nivelEntry.value;
        final rowspan = items.length;

        // Obtener la observación del nivel (asumimos que es la misma para todos)
        // Puedes tomar la primera o concatenar si varían
        String observacionNivel = '';
        if (items.isNotEmpty) {
      
          observacionNivel = items[0]['tobservacion']?.toString() ?? '';

         
        }

        for (int i = 0; i < items.length; i++) {
          final item = items[i];
          buffer.write('<tr>');

       
          if (i == 0) {
            // Nivel
            buffer.write(
              '<td class="nivel-cell" rowspan="$rowspan" style="background-color: #e6f2ff; font-weight: bold; text-align: center; padding: 5px; border: 1px solid #cbd5e1; vertical-align: middle;">',
            );
            buffer.write(_escapeHtml(nivel.toUpperCase()));
            buffer.write('</td>');

            // Parámetro
            buffer.write(
              '<td class="param-cell" style="padding: 5px; border: 1px solid #cbd5e1;">',
            );
            buffer.write(_escapeHtml(item['tparametro']?.toString() ?? ''));
            buffer.write('</td>');

            // Porcentaje
            buffer.write(
              '<td class="porc-cell" style="text-align: center; padding: 5px; border: 1px solid #cbd5e1;">',
            );
            buffer.write(
              _escapeHtml(item['tporcentajetotal']?.toString() ?? '0'),
            );
            buffer.write('%</td>');

            // Observaciones (solo en la primera fila, con rowspan)
            buffer.write(
              '<td class="obs-cell" rowspan="$rowspan" style="padding: 5px; border: 1px solid #cbd5e1; vertical-align: top;">',
            );
            buffer.write(
              _escapeHtml(observacionNivel).replaceAll('\n', '<br>'),
            );
            buffer.write('</td>');
          } else {
            // Filas siguientes: solo parámetro y porcentaje
            buffer.write(
              '<td class="param-cell" style="padding: 5px; border: 1px solid #cbd5e1;">',
            );
            buffer.write(_escapeHtml(item['tparametro']?.toString() ?? ''));
            buffer.write('</td>');

            buffer.write(
              '<td class="porc-cell" style="text-align: center; padding: 5px; border: 1px solid #cbd5e1;">',
            );
            buffer.write(
              _escapeHtml(item['tporcentajetotal']?.toString() ?? '0'),
            );
            buffer.write('%</td>');
            // ¡NO se escribe la celda de observaciones aquí!
          }

          buffer.write('</tr>');
        }
      }

      buffer.write('</table>');
    }

    // Sección de Diagnóstico Presuntivo al final
    final diagnosticoPresuntivo = cabecera['diagnostico_presuntivo']?.toString() ?? '';
    
    buffer.write('<table class="diagnostico-section" style="width: 100%; border-collapse: collapse; margin-top: 20px; page-break-inside: avoid;">');
    buffer.write('<tr>');
    buffer.write('<td class="diagnostico-title" style="background-color: #e6f2ff; font-weight: bold; text-align: center; padding: 5px; border: 1px solid #cbd5e1; page-break-inside: avoid;">');
    buffer.write('DIAGNÓSTICO PRESUNTIVO');
    buffer.write('</td>');
    buffer.write('</tr>');
    buffer.write('<tr>');
    buffer.write('<td class="diagnostico-content" style="padding: 8px; border: 1px solid #cbd5e1; border-top: none; text-align: left; page-break-inside: avoid;">');
    if (diagnosticoPresuntivo.trim().isEmpty) {
      buffer.write('<em>No se registró diagnóstico</em>');
    } else {
      buffer.write(_escapeHtml(diagnosticoPresuntivo).replaceAll('\n', '<br>'));
    }
    buffer.write('</td>');
    buffer.write('</tr>');
    buffer.write('</table>');

    buffer.write('</body></html>');
    return buffer.toString();
  }


  Future<void> generateReportPDF({
    required Map<String, dynamic> cabecera,
    required List<Map<String, dynamic>> registros,
    required Map<String, dynamic> evidenciasCompletas,
    required BuildContext context,
  }) async {
    try {
      final logoBase64 = await _loadLogoBase64();
      final html = _generateReportPDFHTML(
        cabecera,
        registros,
        evidenciasCompletas,
        logoBase64,
      );

      // Generar PDF desde HTML
      final targetPath = await getTemporaryDirectory();
      final generatedPdfFile = await HtmlToPdf.convertFromHtmlContent(
        htmlContent: html,
        printPdfConfiguration: PrintPdfConfiguration(
          targetDirectory: targetPath.path,
          targetName:
              'reporte_necropsia_visual_${DateTime.now().millisecondsSinceEpoch}.pdf',
          printSize: PrintSize.A4,
          printOrientation: PrintOrientation.Landscape,
        ),
      );

      // Leer el PDF generado y abrirlo directamente con flecha de atrás
      final pdfBytes = await generatedPdfFile.readAsBytes();
      await _showPdfWithBackButton(context, pdfBytes, 'Reporte Imágenes');
    } catch (e) {
      debugPrint('Error generando Reporte PDF: $e');
      rethrow;
    }
  }

  String _generateReportPDFHTML(
    Map<String, dynamic> cabecera,
    List<Map<String, dynamic>> registros,
    Map<String, dynamic> evidenciasCompletas,
    String?
    logoBase64,
  ) {
    final granjaRaw = cabecera['tcencos']?.toString() ?? '';
    final granjaTxt = granjaRaw.contains('C=')
        ? granjaRaw.split('C=')[0].trim()
        : granjaRaw;
    final Map<String, Map<String, double>> porcentajes = {};
    for (var r in registros) {
      final nivel = r['tnivel']?.toString() ?? '';
      final parametro = r['tparametro']?.toString() ?? '';
      final porcentaje = (r['tporcentajetotal'] as num?)?.toDouble() ?? 0.0;
      if (nivel.isNotEmpty && parametro.isNotEmpty) {
        porcentajes.putIfAbsent(nivel, () => {})[parametro] = porcentaje;
      }
    }

    final Map<String, List<Map<String, dynamic>>> porSistema = {};
    for (var reg in registros) {
      final sistema = reg['tsistema']?.toString() ?? '';
      if (sistema.isNotEmpty) {
        porSistema.putIfAbsent(sistema, () => []).add(reg);
      }
    }

    final buffer = StringBuffer();
    
   
    final now = DateTime.now();
    final fechaHora = DateFormat('dd/MM/yyyy HH:mm').format(now);

    buffer.write('<!DOCTYPE html>');
    buffer.write('<html>');
    buffer.write('<head>');
    buffer.write('<meta charset="UTF-8">');
    buffer.write('<style>');
    buffer.write('''
    @page {
        size: A4 landscape;
        margin: 10mm;
        margin-top: 15mm;
        margin-bottom: 20mm;
        @top-right {
            content: "$fechaHora";
            font-size: 9pt;
            color: #000;
        }
        @bottom-center {
            content: "Página " counter(page) " de " counter(pages);
            font-size: 9pt;
            color: #000;
        }
    }
    body {
        font-family: Arial;
        font-size: 11pt;
        color: #000;
        margin: 0;
        padding: 0;
    }

    .header-page {
    margin-top: 60px;
    text-align: center;
    margin-left: auto;
    margin-right: auto;
    width: 100%;
    margin-bottom: 30px;
}

    h1 {
        text-align: center;
        color: #002060;
        font-size: 26pt;
        margin: 0 0 20px 0;
    }

    .granja {
        font-size: 22pt;
        font-weight: bold;
        color: #002060;
    }
    .detalles {
        font-size: 15pt;
        color: #002060;
        font-weight: 500;
    }

    h2 {
        text-align: center;
        color: #002060;
        font-size: 22pt;
        border-bottom: 4px solid #002060;
        margin: 0 0 20px 0;
        padding-bottom: 6px;
        page-break-before: always;
    }

    .nivel {
        font-size: 14pt;
        font-weight: bold;
        color: #002060;
        margin-bottom: 6px;
        text-align: center;
    }

    .img-box {
        width: 100%;
        margin: 0 auto;
        border-collapse: collapse;
    }
    .img-box td {
        text-align: center;
        vertical-align: middle;
        padding: 4px 2px;
        width: 100%;
    }
    .img-box img {
        max-width: 100%;
        max-height: 150px;
        width: auto;
        height: auto;
        margin: 0 auto;
        display: block;
        object-fit: contain;
        overflow: hidden;
    }

    .porc-box {
        width: 100%;
        margin: 6px auto 0 auto;
        font-size: 10pt;
        background: #D5D5D5;
    }
    .porc-box td {
        padding: 2px 4px;
        text-align: center;
    }

    .obs-box {
        width: 100%;
        margin: 6px auto 0 auto;
        font-size: 9pt;
        background: #f3f3f3;
        border: 1px solid #ddd;
        border-radius: 6px;
        padding: 6px 8px;
        text-align: left;
        line-height: 1.25;
        word-wrap: break-word;
        white-space: normal;
    }
    .obs-title {
        font-weight: bold;
        color: #002060;
        margin-bottom: 3px;
        font-size: 9pt;
    }

    .continuation-table {
        margin-top: 60px;
    }

    .diagnostico-section {
        margin-top: 40px;
        margin-bottom: 20px;
        page-break-inside: avoid;
    }

    .diagnostico-title {
        font-size: 18pt;
        font-weight: bold;
        color: #002060;
        text-align: center;
        margin-bottom: 12px;
        border-bottom: 3px solid #002060;
        padding-bottom: 8px;
    }

    .diagnostico-content {
        font-size: 12pt;
        color: #000;
        text-align: left;
        padding: 15px;
        background-color: #f9f9f9;
        border: 1px solid #ddd;
        border-radius: 8px;
        line-height: 1.6;
        white-space: pre-wrap;
        word-wrap: break-word;
    }
''');
    buffer.write('</style>');
    buffer.write('</head>');
    buffer.write('<body>');

    buffer.write('<div class="header-page">');
    buffer.write('<h1>REPORTE DE NECROPSIA</h1>');
    buffer.write('<div class="granja">GRANJA ${_escapeHtml(granjaTxt)}</div>');
    buffer.write('<div class="detalles">');
    buffer.write(
      'Campaña ${_escapeHtml(cabecera['tcampania']?.toString() ?? '')} &nbsp;&nbsp;',
    );
    buffer.write(
      'GALPÓN ${_escapeHtml(cabecera['tgalpon']?.toString() ?? '')} &nbsp;&nbsp;',
    );
    buffer.write(
      'EDAD ${_escapeHtml(cabecera['tedad']?.toString() ?? '')} DÍAS',
    );
    buffer.write('</div>');
    // Nueva fila con N° Reg y Fecha
    buffer.write('<div class="detalles" style="margin-top: 10px;">');
    final numreg = cabecera['numreg']?.toString() ?? cabecera['tnumreg']?.toString() ?? '';
    final codigoNec =
        cabecera['codigoNecropsia']?.toString() ??
        cabecera['tcodnecropsia']?.toString() ??
        '';
    final fecha = _formatDate(cabecera['fectra']?.toString() ?? cabecera['tdate']?.toString() ?? '');
    if (codigoNec.trim().isNotEmpty) {
      buffer.write(
        'Código: ${_escapeHtml(codigoNec)} &nbsp;&nbsp; N° Reg: ${_escapeHtml(numreg)} &nbsp;&nbsp; Fecha: ${_escapeHtml(fecha)}',
      );
    } else {
      buffer.write(
        'N° Reg: ${_escapeHtml(numreg)} &nbsp;&nbsp; Fecha: ${_escapeHtml(fecha)}',
      );
    }
    buffer.write('</div>');
    buffer.write('</div>');

    String sistemaActual = '';
    int col = 0;
    List<String> nivelesProcesados = [];

    for (var reg in registros) {
      final sistema = reg['tsistema']?.toString() ?? '';

      if (sistema != sistemaActual) {
        if (sistemaActual != '') {
          buffer.write('</tr></table>');
        }

        buffer.write('<h2>${_escapeHtml(sistema)}</h2>');
        buffer.write('<table width="100%" cellpadding="5"><tr>');

        sistemaActual = sistema;
        nivelesProcesados.clear();
        col = 0;
      }

      final nivel = reg['tnivel']?.toString() ?? '';
      if (nivelesProcesados.contains(nivel)) continue;
      nivelesProcesados.add(nivel);
      if (col == 3) {
        buffer.write(
          '</tr></table><div style="page-break-before: always;"></div><table width="100%" cellpadding="5"><tr>',
        );
        col = 0;
      }

      List<String> imagePaths = [];

      // Clave debe coincidir con register_necropcia_screen: INMUNOLOGICO, DIGESTIVO, RESPIRATORIO, FISICA (para EVALUACION FISICA)
      String sistemaKey = sistema.toUpperCase();
      if (sistemaKey.startsWith('SISTEMA ')) {
        sistemaKey = sistemaKey.substring(8);
      }
      if (sistemaKey == 'EVALUACION FISICA') {
        sistemaKey = 'FISICA';
      } else {
        sistemaKey = sistemaKey.replaceAll(' ', '_');
      }
      final nivelKey = '${sistemaKey}_$nivel';

     

      final imagenesNivel =
          evidenciasCompletas[nivelKey] as List<dynamic>? ?? [];
     

      if (imagenesNivel.isNotEmpty) {    
        for (var imagenItem in imagenesNivel) {
          if (imagenItem is Map<String, dynamic>) {
            final path = imagenItem['path']?.toString() ?? '';
            if (path.isNotEmpty) {
              final file = File(path);
              if (file.existsSync()) {
                imagePaths.add(path);
                
              } else {
              
              }
            }
          } else if (imagenItem is String) {
       
            final file = File(imagenItem);
            if (file.existsSync()) {
              imagePaths.add(imagenItem);
         
            }
          }
        }
      }

     
      if (imagePaths.isEmpty &&
          reg['evidencia'] != null &&
          reg['evidencia'] is String) {
        final paths = (reg['evidencia'] as String).split(',');
        for (var pathStr in paths) {
          final trimmedPath = pathStr.trim();
          if (trimmedPath.isNotEmpty) {
       
            if (!trimmedPath.contains('uploads/') &&
                !trimmedPath.startsWith('http')) {
              final file = File(trimmedPath);
              if (file.existsSync()) {
                imagePaths.add(trimmedPath);
               
              } 
            } 
          }
        }
      }

     
      String imgHtml = 'Sin evidencia';
      if (imagePaths.isNotEmpty) {
        final imgRows = <String>[];
        for (var imagePath in imagePaths) {
          final base64 = _imageToBase64(imagePath, larger: false);
          if (base64 != null) {
            // Cada imagen en su propia fila (columna vertical)
            imgRows.add('<tr><td><img src="data:image/jpeg;base64,$base64"></td></tr>');
          } 
        }
        if (imgRows.isNotEmpty) {
          // Tabla con cada imagen en una fila separada
          imgHtml = '<table class="img-box">${imgRows.join('')}</table>';
        }
      } 

          String porcHtml = '';
      final porcentajesNivel = porcentajes[nivel] ?? {};
      if (porcentajesNivel.isNotEmpty) {
        for (var entry in porcentajesNivel.entries) {
          porcHtml +=
              '<tr><td>${_escapeHtml(entry.key)}</td><td><strong>${entry.value.toStringAsFixed(2)}%</strong></td></tr>';
        }
      }

      // Observación por nivel (tomar la primera no vacía para este sistema + nivel)
      String observacionNivel = '';
      for (final r in registros) {
        final s = r['tsistema']?.toString() ?? '';
        final n = r['tnivel']?.toString() ?? '';
        if (s == sistema && n == nivel) {
          final obs = r['tobservacion']?.toString() ?? '';
          if (obs.trim().isNotEmpty) {
            observacionNivel = obs.trim();
            break;
          }
        }
      }
      final obsHtml = observacionNivel.isEmpty
          ? '<div class="obs-box"><div class="obs-title">Observación</div><em>Sin observación</em></div>'
          : '<div class="obs-box"><div class="obs-title">Observación</div>${_escapeHtml(observacionNivel).replaceAll('\n', '<br>')}</div>';

      buffer.write('''
    <td width="33%" align="center" valign="top">
        <div class="nivel">${_escapeHtml(nivel)}</div>
        $imgHtml
        <table class="porc-box">$porcHtml</table>
        $obsHtml
    </td>
    ''');

      col++;
    }

    if (sistemaActual != '') {
      buffer.write('</tr></table>');
    }

    // Sección de Diagnóstico Presuntivo en nueva página
    final diagnosticoPresuntivo = cabecera['diagnostico_presuntivo']?.toString() ?? '';
    
    // Salto de página antes de la sección de diagnóstico
    buffer.write('<div style="page-break-before: always;"></div>');
    
    // Siempre mostrar la sección, con "No se registró diagnóstico" si está vacío
    buffer.write('<div class="diagnostico-section">');
    buffer.write('<div class="diagnostico-title">DIAGNÓSTICO PRESUNTIVO</div>');
    buffer.write('<div class="diagnostico-content">');
    if (diagnosticoPresuntivo.trim().isEmpty) {
      buffer.write('<em>No se registró diagnóstico</em>');
    } else {
      buffer.write(_escapeHtml(diagnosticoPresuntivo).replaceAll('\n', '<br>'));
    }
    buffer.write('</div>');
    buffer.write('</div>');

    buffer.write('</body></html>');
    return buffer.toString();
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return '--/--/--';
    try {
      final date = DateTime.parse(dateString);
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final year = date.year.toString();
      return '$day/$month/$year';
    } catch (e) {
      return dateString;
    }
  }

  String _formatDateTime(String? dateTimeString) {
    if (dateTimeString == null || dateTimeString.isEmpty) return '--/--/-- --:--:--';
    try {
      // Formato esperado: YYYY-MM-DD HH:MM:SS o HH:MM:SS (para compatibilidad)
      String dateTimeStr = dateTimeString.trim();
      
      // Si solo tiene hora (HH:MM:SS), usar la fecha actual
      if (dateTimeStr.contains(':') && !dateTimeStr.contains('-')) {
        final now = DateTime.now();
        dateTimeStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} $dateTimeStr';
      }
      
      final dateTime = DateTime.parse(dateTimeStr);
      final day = dateTime.day.toString().padLeft(2, '0');
      final month = dateTime.month.toString().padLeft(2, '0');
      final year = dateTime.year.toString();
      final hour = dateTime.hour.toString().padLeft(2, '0');
      final minute = dateTime.minute.toString().padLeft(2, '0');
      final second = dateTime.second.toString().padLeft(2, '0');
      return '$day/$month/$year $hour:$minute:$second';
    } catch (e) {
      return dateTimeString;
    }
  }

  Future<void> _showPdfWithBackButton(
    BuildContext context,
    Uint8List pdfBytes,
    String title,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(title, style: TextStyle(color: AppColors.primary)),
            backgroundColor: Colors.white,
            foregroundColor: AppColors.primary,
            actions: [
              IconButton(
                icon: const Icon(Icons.download, color: AppColors.primary),
                onPressed: () async {
                  await Printing.sharePdf(
                    bytes: pdfBytes,
                    filename:
                        '${title.toLowerCase().replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.pdf',
                  );
                },
                tooltip: 'Descargar PDF',
              ),
            ],
          ),
          body: PdfPreview(
            build: (PdfPageFormat format) async => pdfBytes,
            allowPrinting: false,
            allowSharing: false,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
          ),
        ),
      ),
    );
  }
}
