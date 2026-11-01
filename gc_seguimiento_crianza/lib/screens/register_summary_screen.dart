import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/constants.dart';
import '../utils/theme_colors.dart';
import '../widgets/app_drawer.dart';
import '../widgets/granja_campania_picker.dart';
import '../widgets/screen_status_bar.dart';
import '../widgets/section_app_bar.dart';

/// Convierte fechas guardadas (yyyy-MM-dd o ISO completo) a dd/MM/yyyy.
/// Si el valor ya viene en dd/MM/yyyy, lo devuelve tal cual.
String _fmtFecha(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return s;
  if (s.contains('/')) return s;
  final f = DateTime.tryParse(s);
  if (f == null) return s;
  return DateFormat('dd/MM/yyyy').format(f);
}

/// Contenido reutilizable del resumen de evidencia.
class RegisterSummaryContent extends StatelessWidget {
  const RegisterSummaryContent({
    super.key,
    required this.record,
    this.title = 'Resumen del registro',
  });

  final Map<String, dynamic> record;
  final String title;

  @override
  Widget build(BuildContext context) {
    final imagenes = (record['imagenes'] as List?) ?? [];
    final granjaLabel = GranjaCampaniaPicker.formatGranjaLabel(
      record['granja']?.toString() ?? '',
      record['granjaNombre']?.toString() ?? '',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) ...[
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: context.textThemePrimary,
            ),
          ),
          const SizedBox(height: 16),
        ],
        _row(context, 'Fecha', _fmtFecha(record['fecha']?.toString() ?? '')),
        if (record['campaniaActiva'] == true &&
            record['edad'] != null &&
            record['edad'].toString().isNotEmpty &&
            record['edad'].toString() != 'null')
          _row(context, 'Edad', 'Día ${record['edad']}'),
        _row(context, 'Granja', granjaLabel),
        _row(
          context,
          'Campaña',
          GranjaCampaniaPicker.padCampania(
            record['campania']?.toString() ?? '',
          ),
        ),
        _row(context, 'Galpón', GranjaCampaniaPicker.formatGalpones(record)),
        _textFieldRow(context, 'Seguimiento', record['obs']?.toString()),
        _textFieldRow(context, 'Agente causal', record['agente_causal']?.toString()),
        const SizedBox(height: 12),
        Text(
          'Imágenes',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: context.textThemeSecondary,
          ),
        ),
        const SizedBox(height: 8),
        imagenes.where((p) => File(p.toString()).existsSync()).isEmpty
            ? Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Sin imágenes adjuntas',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontSize: 13,
                    color: context.textThemeMuted,
                  ),
                ),
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: imagenes.map((p) {
                  final path = p.toString();
                  if (!File(path).existsSync()) return const SizedBox.shrink();
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(AppColors.radiusSm),
                    child: Image.file(
                      File(path),
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                    ),
                  );
                }).toList(),
              ),
      ],
    );
  }

  Widget _textFieldRow(BuildContext context, String label, String? raw) {
    final value = raw?.trim() ?? '';
    final empty = value.isEmpty;
    return _row(
      context,
      label,
      empty ? 'No ingresado' : value,
      placeholder: empty,
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value, {
    bool placeholder = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(
                '$label:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: context.textThemeSecondary,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  color: placeholder
                      ? context.textThemeMuted
                      : context.textThemePrimary,
                  fontStyle:
                      placeholder ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
          ],
        ),
      );
}

/// Modal de resumen a pantalla completa antes de guardar (como gc_necropsia).
/// Si [onConfirm] es null, el modal es de solo lectura (sin botones de guardar).
class RegisterSummarySheet {
  static Future<bool> show(
    BuildContext context, {
    required Map<String, dynamic> record,
    Future<void> Function()? onConfirm,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 1.0,
        minChildSize: 0.5,
        maxChildSize: 1.0,
        builder: (context, scrollController) => ScreenStatusBar(
          color: sheetContext.scaffoldMuted,
          child: Container(
          decoration: BoxDecoration(
            color: sheetContext.scaffoldMuted,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: sheetContext.surfaceCard,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                  boxShadow: sheetContext.cardShadow(blur: 10, dy: -2),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: sheetContext.textThemeMuted.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.fact_check_outlined,
                            color: AppColors.primary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Resumen del registro',
                            style: TextStyle(
                              color: sheetContext.textThemePrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            color: sheetContext.textThemeSecondary,
                          ),
                          onPressed: () => Navigator.pop(sheetContext, false),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: sheetContext.surfaceCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: RegisterSummaryContent(record: record, title: ''),
                  ),
                ),
              ),
              if (onConfirm != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: sheetContext.surfaceCard,
                    boxShadow: sheetContext.cardShadow(blur: 10, dy: -2),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(sheetContext, false),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                          child: const Text(
                            'Cancelar',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () async {
                            await onConfirm();
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext, true);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Confirmar y Guardar',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      ),
    );
    return result ?? false;
  }
}

/// Vista de solo lectura para reportes.
class RegisterSummaryScreen extends StatelessWidget {
  const RegisterSummaryScreen({super.key, required this.record});

  final Map<String, dynamic> record;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: const SectionAppBar(
        title: 'Resumen',
        sectionIcon: Icons.fact_check_outlined,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: RegisterSummaryContent(
              record: record,
              title: 'Registro guardado',
            ),
          ),
        ),
      ),
    );
  }
}
