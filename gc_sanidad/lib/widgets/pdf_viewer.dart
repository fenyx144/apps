// widgets/pdf_viewer.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

import '../utils/constants.dart';

class PdfViewer extends StatefulWidget {
  final String codEnvio;
  final int posSolicitud;
  final String codAnalisis;

  const PdfViewer({
    super.key,
    required this.codEnvio,
    required this.posSolicitud,
    required this.codAnalisis,
  });

  @override
  State<PdfViewer> createState() => _PdfViewerState();
}

class _PdfViewerState extends State<PdfViewer> {
  String? _pdfUrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchPdfUrl();
  }

  Future<void> _fetchPdfUrl() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse(
        '${AppConstants.baseUrlSanidad}/api/get_pdf_url.php?'
        'cod_envio=${widget.codEnvio}&'
        'pos_solicitud=${widget.posSolicitud}&'
        'cod_analisis=${widget.codAnalisis}',
      ));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['url'] != null) {
          setState(() => _pdfUrl = data['url']);
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar PDF: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadAndOpenPdf() async {
    if (_pdfUrl == null) return;

    try {
      final response = await http.get(Uri.parse(_pdfUrl!));
      if (response.statusCode == 200) {
        final dir = await getApplicationDocumentsDirectory();
        final filePath = '${dir.path}/${widget.codAnalisis}.pdf';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        // Abrir con app externa
        await OpenFilex.open(file.path);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al abrir PDF: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_pdfUrl == null) {
      return const Text('No hay resultado PDF para este análisis');
    }

    return Column(
      children: [
        TextButton.icon(
          onPressed: _downloadAndOpenPdf,
          icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
          label: const Text('Ver Resultado PDF'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.red,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Colors.red),
            ),
          ),
        ),
        // Opcional: vista integrada (solo Android)
        // FlutterCachedPdfView(
        //   pdfPath: _pdfUrl!,
        //   placeholder: (double progress) => Center(
        //     child: CircularProgressIndicator(value: progress),
        //   ),
        // ),
      ],
    );
  }
}