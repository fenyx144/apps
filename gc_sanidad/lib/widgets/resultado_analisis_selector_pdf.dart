// widgets/resultado_analisis_selector.dart
import 'package:flutter/material.dart';
import '../utils/constants.dart';
import 'pdf_viewer.dart';

class ResultadoAnalisisSelector extends StatefulWidget {
  final String analisisDisplayName;
  final String? initialResultado;
  final ValueChanged<String> onResultSelected;
  final ValueChanged<String> onObsChanged;
  final String? initialObs;
  final String codEnvio;
  final int posSolicitud;
  final String codAnalisis;

  const ResultadoAnalisisSelector({
    super.key,
    required this.analisisDisplayName,
    this.initialResultado,
    required this.onResultSelected,
    required this.onObsChanged,
    this.initialObs,
    required this.codEnvio,
    required this.posSolicitud,
    required this.codAnalisis,
  });

  @override
  State<ResultadoAnalisisSelector> createState() =>
      _ResultadoAnalisisSelectorState();
}

class _ResultadoAnalisisSelectorState extends State<ResultadoAnalisisSelector> {
  String? _selectedResultado;
  late TextEditingController _obsController;

  @override
  void initState() {
    super.initState();
    _selectedResultado = widget.initialResultado;
    _obsController = TextEditingController(text: widget.initialObs ?? '');
  }

  @override
  void dispose() {
    _obsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.analisisDisplayName,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          /*DropdownButtonFormField<String>(
            value: _selectedResultado,
            decoration: InputDecoration(
              labelText: 'Seleccionar resultado',
              labelStyle: const TextStyle(fontSize: 12, color: Colors.grey),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('Seleccionar...'),
              ),
              ...['Negativo', 'Positivo'].map(
                (e) => DropdownMenuItem(value: e, child: Text(e)),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _selectedResultado = value;
              });
              widget.onResultSelected(value ?? '');
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _obsController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Observaciones...',
              labelStyle: const TextStyle(fontSize: 12, color: Colors.grey),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: widget.onObsChanged,
          ),
          const SizedBox(height: 12),*/
          // 👇 PDF Viewer integrado
          PdfViewer(
            codEnvio: widget.codEnvio,
            posSolicitud: widget.posSolicitud,
            codAnalisis: widget.codAnalisis,
          ),
        ],
      ),
    );
  }
}