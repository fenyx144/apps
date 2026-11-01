import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/theme_colors.dart';
import '../widgets/app_drawer.dart';
import '../widgets/granja_campania_picker.dart';
import '../widgets/section_app_bar.dart';
import '../widgets/evidencia_select_field.dart';
import 'register_summary_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTime? _desde;
  DateTime? _hasta;

  @override
  void initState() {
    super.initState();
    final year = DateTime.now().year;
    _desde = DateTime(year, 1, 1);
    _hasta = DateTime(year, 12, 31);
  }

  DateTime? _parseFechaRecord(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
    if (m != null) {
      return DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
      );
    }
    return DateTime.tryParse(s);
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> all) {
    return all.where((r) {
      final f = _parseFechaRecord(r['fecha']?.toString() ?? '');
      if (f == null) return false;
      if (_desde != null) {
        final d = DateTime(_desde!.year, _desde!.month, _desde!.day);
        if (f.isBefore(d)) return false;
      }
      if (_hasta != null) {
        final h = DateTime(_hasta!.year, _hasta!.month, _hasta!.day);
        if (f.isAfter(h)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) =>
          (b['fecha'] ?? '').toString().compareTo((a['fecha'] ?? '').toString()));
  }

  String _fmtDateDisplay(String iso) {
    final f = DateTime.tryParse(iso);
    if (f == null) return iso;
    return DateFormat('dd/MM/yyyy').format(f);
  }

  Widget _infoLine(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.textThemeMuted,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.textThemePrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate(bool isDesde) async {
    final d = await showDatePicker(
      context: context,
      initialDate: isDesde
          ? (_desde ?? DateTime.now())
          : (_hasta ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) {
      setState(() {
        if (isDesde) {
          _desde = d;
        } else {
          _hasta = d;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final records = _filtered(storage.getMyRecords());
    final tc = context;

    return Scaffold(
      backgroundColor: tc.scaffoldMuted,
      drawer: const AppDrawer(),
      appBar: const SectionAppBar(
        title: AppStrings.reportesTitle,
        sectionIcon: Icons.assessment_outlined,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: EvidenciaSelectField(
                    label: AppStrings.desde,
                    value: _desde != null
                        ? DateFormat('dd/MM/yyyy').format(_desde!)
                        : '',
                    placeholder: 'Seleccionar',
                    icon: Icons.calendar_today_outlined,
                    onTap: () => _pickDate(true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: EvidenciaSelectField(
                    label: AppStrings.hasta,
                    value: _hasta != null
                        ? DateFormat('dd/MM/yyyy').format(_hasta!)
                        : '',
                    placeholder: 'Seleccionar',
                    icon: Icons.calendar_today_outlined,
                    onTap: () => _pickDate(false),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: records.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inbox_outlined,
                            size: 48,
                            color: tc.textThemeMuted,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Sin registros',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: tc.textThemePrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Ajusta el rango de fechas o crea un nuevo seguimiento.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: tc.textThemeSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 48),
                    itemCount: records.length,
                    itemBuilder: (_, i) {
                      final r = records[i];
                      final synced = r['synced'] == true;
                      final imgs = (r['imagenes'] as List?) ?? [];
                      final validImgs =
                          imgs.map((p) => p.toString()).where((p) {
                        final f = File(p);
                        return p.isNotEmpty && f.existsSync();
                      }).toList();

                      final edad = r['edad'];
                      final tieneEdad = edad != null &&
                          edad.toString() != 'null' &&
                          edad.toString().isNotEmpty &&
                          int.tryParse(edad.toString()) != null &&
                          int.parse(edad.toString()) > 0;
                      final fecha = r['fecha']?.toString() ?? '';
                      final fechaFmt = fecha.isNotEmpty
                          ? _fmtDateDisplay(fecha)
                          : '—';

                      final granjaLabel = GranjaCampaniaPicker.formatGranjaLabel(
                        r['granja']?.toString() ?? '',
                        r['granjaNombre']?.toString() ?? '',
                      );
                      final camp = GranjaCampaniaPicker.padCampania(
                        r['campania']?.toString() ?? '',
                      );
                      final galpon =
                          GranjaCampaniaPicker.formatGalpones(r);
                      final agenteCausal =
                          (r['agente_causal']?.toString() ?? '').trim();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: tc.surfaceCard,
                          borderRadius:
                              BorderRadius.circular(AppColors.radiusLg),
                          border: Border.all(color: tc.borderSubtle),
                          boxShadow: tc.cardShadow(),
                        ),
                        child: InkWell(
                          borderRadius:
                              BorderRadius.circular(AppColors.radiusLg),
                          onTap: () => RegisterSummarySheet.show(
                            context,
                            record: r,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        fechaFmt,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                          color: tc.textThemePrimary,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: synced
                                            ? AppColors.success
                                                .withValues(alpha: 0.15)
                                            : AppColors.warning
                                                .withValues(alpha: 0.18),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        synced ? 'Subido' : 'Pendiente',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: synced
                                              ? (tc.isAppDark
                                                  ? AppColors.primaryLight
                                                  : AppColors.primaryDark)
                                              : (tc.isAppDark
                                                  ? AppColors.warning
                                                  : const Color(0xFFE65100)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                _infoLine(
                                  context,
                                  'Granja',
                                  granjaLabel.isEmpty
                                      ? '—'
                                      : granjaLabel,
                                ),
                                if (camp.isNotEmpty)
                                  _infoLine(context, 'Camp', camp),
                                if (galpon.isNotEmpty)
                                  _infoLine(context, 'Galpón', galpon),
                                if (agenteCausal.isNotEmpty)
                                  _infoLine(
                                    context,
                                    'Agente causal',
                                    agenteCausal,
                                  ),
                                if (tieneEdad)
                                  _infoLine(context, 'Edad', 'Día $edad'),
                                if (validImgs.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: validImgs.map((p) {
                                      return ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                          AppColors.radiusSm,
                                        ),
                                        child: Image.file(
                                          File(p),
                                          width: 56,
                                          height: 56,
                                          fit: BoxFit.cover,
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
