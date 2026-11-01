import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../widgets/app_drawer.dart';
import '../widgets/evidencia_select_field.dart';
import '../widgets/granja_campania_picker.dart';
import '../widgets/section_app_bar.dart';
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
    final now = DateTime.now();
    _desde = DateTime(now.year, now.month, 1);
    _hasta = DateTime(now.year, now.month + 1, 0);
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> all) {
    return all.where((r) {
      final f = DateTime.tryParse(r['fecha']?.toString() ?? '');
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

  Widget _infoLine(String label, String value) {
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
              color: AppColors.textMuted.withValues(alpha: 0.9),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSelectedValue,
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
    final records = _filtered(storage.getAllRecords());
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? null : AppColors.background,
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
                            color: AppColors.textMuted.withValues(alpha: 0.7),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Sin registros',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Ajusta el rango de fechas o crea una nueva evidencia.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textMuted,
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

                      final fecha = r['fecha']?.toString() ?? '';
                      final fechaFmt =
                          fecha.isNotEmpty ? _fmtDateDisplay(fecha) : '—';
                      final granjaLabel = GranjaCampaniaPicker.formatGranjaLabel(
                        r['granja']?.toString() ?? '',
                        r['granjaNombre']?.toString() ?? '',
                      );
                      final camp = GranjaCampaniaPicker.padCampania(
                        r['campania']?.toString() ?? '',
                      );
                      final galpon = r['galpon']?.toString() ?? '—';
                      final proceso = r['procesoNombre']?.toString() ?? '—';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.06),
                          ),
                          boxShadow: AppColors.lightShadow,
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
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
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                          color: AppColors.textPrimary,
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
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        synced ? 'Subido' : 'Pendiente',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: synced
                                              ? AppColors.primaryDark
                                              : const Color(0xFFE65100),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                _infoLine('Proceso', proceso),
                                _infoLine(
                                  'Granja',
                                  granjaLabel.isEmpty ? '—' : granjaLabel,
                                ),
                                if (camp.isNotEmpty) _infoLine('Camp', camp),
                                if (galpon.isNotEmpty && galpon != '—')
                                  _infoLine('Galpón', galpon),
                                if (validImgs.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: validImgs.map((p) {
                                      return ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
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
