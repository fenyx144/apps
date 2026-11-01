import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/dialog_helper.dart';
import '../utils/record_id.dart';
import '../utils/record_saver.dart';
import '../utils/theme_colors.dart';
import '../utils/toast_helper.dart';
import '../widgets/app_card.dart';
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
  /// Filtros por sección, en el mismo orden en que el drawer agrupa bioseguridad
  /// física (control de personal, cerco, fómites y anomalías).
  static const _filtrosSeccion = <String, String>{
    'todos': 'Todas',
    'decloracion': AppStrings.menuDecloracion,
    'vacunacion': AppStrings.menuVacunacion,
  };

  static const _filtrosEstado = <String, String>{
    'todos': 'Todos',
    'pendientes': 'Pendientes',
    'subidos': 'Subidos',
  };

  DateTime? _desde;
  DateTime? _hasta;
  String _seccion = 'todos';
  String _estado = 'todos';

  @override
  void initState() {
    super.initState();
    final year = DateTime.now().year;
    _desde = DateTime(year, 1, 1);
    _hasta = DateTime(year, 12, 31);
  }

  DateTime? _parseFecha(String raw) {
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

  bool _esSubido(Map<String, dynamic> r) =>
      r['synced'] == true || r['synced'] == 'true';

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> all) {
    return all.where((r) {
      final f = _parseFecha(r['fecha']?.toString() ?? '');
      if (f == null) return false;
      if (_desde != null) {
        final d = DateTime(_desde!.year, _desde!.month, _desde!.day);
        if (f.isBefore(d)) return false;
      }
      if (_hasta != null) {
        final h = DateTime(_hasta!.year, _hasta!.month, _hasta!.day);
        if (f.isAfter(h)) return false;
      }
      if (_seccion != 'todos' && (r['reporte']?.toString() ?? '') != _seccion) {
        return false;
      }
      if (_estado == 'pendientes' && _esSubido(r)) return false;
      if (_estado == 'subidos' && !_esSubido(r)) return false;
      return true;
    }).toList()
      ..sort((a, b) => (b['fecha'] ?? '')
          .toString()
          .compareTo((a['fecha'] ?? '').toString()));
  }

  Future<void> _pickDate(bool isDesde) async {
    final d = await showDatePicker(
      context: context,
      initialDate: isDesde ? (_desde ?? DateTime.now()) : (_hasta ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('es', 'ES'),
    );
    if (d == null) return;
    setState(() {
      if (isDesde) {
        _desde = d;
      } else {
        _hasta = d;
      }
    });
  }

  Future<void> _subirRegistro(Map<String, dynamic> record) async {
    if (!await BioRecordSaver.hasServerReachable()) {
      if (!mounted) return;
      showErrorToast(context, AppStrings.sinConexion);
      return;
    }
    if (!mounted) return;

    final close = showChickenLoadingDialog(context, 'Enviando registro…');
    final storage = context.read<StorageService>();
    var ok = false;
    try {
      final result = await ApiService().uploadBioseguridad(
        record,
        timeout: const Duration(seconds: 45),
      );
      if (ApiService.subidaCompleta(result)) {
        await storage.markRecordAsSynced({
          ...record,
          'id': EvidenciaRecordId.of(record),
          'guardado_backend': true,
        });
        await storage.setLastSyncDate();
        ok = true;
      } else if (result['success'] == true) {
        await storage.markRecordPending(record);
      }
    } catch (_) {
      ok = false;
    } finally {
      close();
    }
    if (!mounted) return;
    if (ok) {
      showSuccessToast(context, 'Registro subido.');
    } else {
      showErrorToast(context, 'No se pudo subir el registro.');
    }
  }

  Widget _chip(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary
                : AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AppColors.primaryDark
                  : AppColors.primary.withValues(alpha: 0.25),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.primaryDark,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final records = _filtered(storage.getMyRecords());

    return Scaffold(
      backgroundColor: context.scaffoldMuted,
      drawer: const AppDrawer(),
      appBar: const SectionAppBar(
        title: AppStrings.reportesTitle,
        sectionIcon: Icons.assessment_outlined,
      ),
      body: Column(
        children: [
          _buildFiltros(context, records.length),
          Expanded(
            child: records.isEmpty
                ? _buildVacio(context)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: records.length,
                    itemBuilder: (_, i) => _buildItem(context, records[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltros(BuildContext context, int total) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      color: context.surfaceCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: EvidenciaSelectField(
                  label: AppStrings.desde,
                  value: _desde == null
                      ? ''
                      : DateFormat('dd/MM/yyyy').format(_desde!),
                  placeholder: 'Seleccione',
                  icon: Icons.calendar_today_rounded,
                  onTap: () => _pickDate(true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: EvidenciaSelectField(
                  label: AppStrings.hasta,
                  value: _hasta == null
                      ? ''
                      : DateFormat('dd/MM/yyyy').format(_hasta!),
                  placeholder: 'Seleccione',
                  icon: Icons.event_available_rounded,
                  onTap: () => _pickDate(false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            children: [
              for (final e in _filtrosSeccion.entries)
                _chip(
                  context,
                  e.value,
                  _seccion == e.key,
                  () => setState(() => _seccion = e.key),
                ),
            ],
          ),
          Wrap(
            children: [
              for (final e in _filtrosEstado.entries)
                _chip(
                  context,
                  e.value,
                  _estado == e.key,
                  () => setState(() => _estado = e.key),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '$total registro(s) encontrado(s)',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: context.textThemeMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVacio(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_rounded,
              size: 56,
              color: AppColors.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'No hay registros con los filtros seleccionados.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.textThemeMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, Map<String, dynamic> record) {
    final reporte = record['reporte']?.toString() ?? '';
    final subido = _esSubido(record);
    final fecha = _parseFecha(record['fecha']?.toString() ?? '');
    final granja = GranjaCampaniaPicker.formatGranjaLabel(
      record['granja']?.toString() ?? '',
      record['granjaNombre']?.toString() ?? '',
    );
    final campania = GranjaCampaniaPicker.padCampania(
      record['campania']?.toString() ?? '',
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    iconoReporte(reporte),
                    size: 20,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombreReporte(reporte),
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: context.textThemePrimary,
                        ),
                      ),
                      Text(
                        fecha == null
                            ? '—'
                            : DateFormat('dd/MM/yyyy').format(fecha),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.textThemeSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: subido
                        ? AppColors.success.withValues(alpha: 0.15)
                        : AppColors.warning.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        subido
                            ? Icons.cloud_done_rounded
                            : Icons.cloud_off_rounded,
                        size: 13,
                        color: subido
                            ? AppColors.success
                            : const Color(0xFFE65100),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        subido ? 'Subido' : 'Pendiente',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: subido
                              ? AppColors.success
                              : const Color(0xFFE65100),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _infoLine(
              context,
              'Granja',
              '$granja  ·  $campania',
            ),
            _infoLine(context, 'Turno', record['turno']?.toString() ?? '—'),
            _infoResumen(context, record),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!subido)
                  TextButton.icon(
                    onPressed: () => _subirRegistro(record),
                    icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                    label: const Text('Subir'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primaryDark,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => RegisterSummarySheet.show(
                    context,
                    record: record,
                  ),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Detalle'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryDark,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoResumen(BuildContext context, Map<String, dynamic> record) {
    final registro = Map<String, dynamic>.from(
      (record['registro'] as Map?) ?? const {},
    );
    final reporte = record['reporte']?.toString() ?? '';

    if (reporte == 'decloracion') {
      final hora = registro['hora_inicio']?.toString() ?? '--:--';
      final cloro = registro['cloro_inicio']?.toString() ?? '—';
      return _infoLine(
        context,
        'Decloración',
        'Inicio $hora · Cloro residual $cloro ppm',
      );
    }
    if (reporte == 'vacunacion') {
      final vacuna = registro['vacuna']?.toString().trim() ?? '';
      final galpones = ((registro['galpones'] as List?) ?? []).length;
      final filas = (registro['cadena_frio'] as List?) ?? [];
      return _infoLine(
        context,
        'Vacunación',
        '${vacuna.isEmpty ? 'Vacuna sin nombre' : vacuna}'
            ' · $galpones galpón(es)'
            ' · ${filas.length} registro(s) de frío',
      );
    }
    return const SizedBox.shrink();
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
}
