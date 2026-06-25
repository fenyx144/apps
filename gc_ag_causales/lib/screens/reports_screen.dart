import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../widgets/app_drawer.dart';
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

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: const SectionAppBar(
        title: AppStrings.reportesTitle,
        sectionIcon: Icons.assessment_outlined,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
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
                ? const Center(child: Text('Sin registros'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: records.length,
                    itemBuilder: (_, i) {
                      final r = records[i];
                      final synced = r['synced'] == true;
                      final imgs = (r['imagenes'] as List?) ?? [];
                      final thumb = imgs.isNotEmpty ? imgs.first.toString() : null;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  RegisterSummaryScreen(record: r),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (thumb != null && File(thumb).existsSync())
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      File(thumb),
                                      width: 72,
                                      height: 72,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                else
                                  Container(
                                    width: 72,
                                    height: 72,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.image, color: Colors.grey),
                                  ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        r['procesoNombre']?.toString() ?? '—',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        '${r['granjaNombre'] ?? r['granja']} — ${r['campania']}',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                      Text(
                                        'Galpón: ${r['galpon'] ?? '—'} · ${r['fecha']}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                Chip(
                                  label: Text(
                                    synced ? 'Subido' : 'Pendiente',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  backgroundColor: synced
                                      ? Colors.green.shade100
                                      : Colors.orange.shade100,
                                  padding: EdgeInsets.zero,
                                ),
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
