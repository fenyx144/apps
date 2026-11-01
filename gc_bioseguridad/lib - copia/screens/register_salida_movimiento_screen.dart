import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../services/ingreso_presencia_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/record_saver.dart';
import '../utils/theme_colors.dart';
import '../utils/toast_helper.dart';
import '../widgets/bio_form_fields.dart';
import '../widgets/section_app_bar.dart';
import 'register_summary_screen.dart';

String _horaDelDia(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}';

String _fmtFechaIngreso(String ymd) {
  final s = ymd.trim();
  if (s.isEmpty) return '—';
  final d = DateTime.tryParse(s);
  if (d == null) return s;
  return DateFormat('dd/MM/yyyy').format(d);
}

/// Solo salida (temporal o definitiva).
class RegisterSalidaMovimientoScreen extends StatefulWidget {
  const RegisterSalidaMovimientoScreen({
    super.key,
    required this.grupo,
    required this.fechaYmd,
    required this.granjaFallback,
    required this.granjaNombreFallback,
  });

  final GrupoPresencia grupo;
  final String fechaYmd;
  final String granjaFallback;
  final String granjaNombreFallback;

  @override
  State<RegisterSalidaMovimientoScreen> createState() =>
      _RegisterSalidaMovimientoScreenState();
}

class _RegisterSalidaMovimientoScreenState
    extends State<RegisterSalidaMovimientoScreen> {
  late String _hora;
  bool _salidaTemporal = false;
  late Map<String, bool> _selPersonas;
  late Map<String, bool> _selVehiculos;

  bool _todosPersonasMarcados(GrupoPresencia g) =>
      g.dentro.isNotEmpty &&
      g.dentro.every((p) => _selPersonas[p.dni] == true);

  bool _todosVehiculosMarcados(GrupoPresencia g) =>
      g.vehiculosDentro.isNotEmpty &&
      g.vehiculosDentro.every((v) => _selVehiculos[v.clave] == true);

  Widget _filaCheck(BuildContext context, CheckboxListTile tile) {
    return Material(
      color: context.surfaceCard,
      child: tile,
    );
  }

  void _marcarTodosPersonas(GrupoPresencia g, bool marcar) {
    for (final p in g.dentro) {
      _selPersonas[p.dni] = marcar;
    }
  }

  void _marcarTodosVehiculos(GrupoPresencia g, bool marcar) {
    for (final v in g.vehiculosDentro) {
      _selVehiculos[v.clave] = marcar;
    }
  }

  @override
  void initState() {
    super.initState();
    _hora = _horaDelDia(DateTime.now());
    _selPersonas = {for (final p in widget.grupo.dentro) p.dni: false};
    _selVehiculos = {
      for (final v in widget.grupo.vehiculosDentro) v.clave: false,
    };
  }

  Future<void> _guardar() async {
    final personas = widget.grupo.dentro
        .where((p) => _selPersonas[p.dni] == true)
        .toList();
    final vehiculos = widget.grupo.vehiculosDentro
        .where((v) => _selVehiculos[v.clave] == true)
        .toList();
    if (personas.isEmpty && vehiculos.isEmpty) {
      showErrorToast(
        context,
        'Marque al menos una persona o un vehículo.',
      );
      return;
    }
    if (_hora.trim().isEmpty) {
      showErrorToast(context, 'Indique la hora.');
      return;
    }

    final grupo = widget.grupo;
    final storage = context.read<StorageService>();
    final record = {
      'id': const Uuid().v4(),
      'reporte': 'salida',
      'fecha': widget.fechaYmd,
      'granja': grupo.granja.isNotEmpty ? grupo.granja : widget.granjaFallback,
      'granjaNombre': grupo.granjaNombre.isNotEmpty
          ? grupo.granjaNombre
          : widget.granjaNombreFallback,
      'campania': grupo.campania,
      'turno': grupo.turno.isNotEmpty ? grupo.turno : 'Dia',
      'usuario': storage.getUserCodeSync() ?? '',
      'nombre_usuario': storage.getUserName() ?? '',
      'registro': {
        'hora': _hora.trim(),
        'movimiento': 'salida',
        'tipo_salida': _salidaTemporal
            ? IngresoPresenciaService.tipoSalidaTemporal
            : IngresoPresenciaService.tipoSalidaDefinitiva,
        'grupo_id': grupo.grupoId,
        'proveedor': grupo.proveedor,
        'motivo': grupo.motivo,
        'dnis': personas
            .map((p) => {'dni': p.dni, 'nombre': p.nombre})
            .toList(),
        if (vehiculos.isNotEmpty)
          'vehiculos': vehiculos
              .map((v) => {'placa': v.etiqueta})
              .toList(),
      },
      'imagenes': const [],
      'synced': false,
      'guardado_backend': false,
      'created_at': DateTime.now().toIso8601String(),
    };

    final saved = await RegisterSummarySheet.show(
      context,
      record: record,
      onConfirm: () async {
        final ok = await BioRecordSaver.save(context, record);
        if (!mounted) return;
        if (ok) {
          showSuccessToast(context, AppStrings.salidaGuardadoEnviado);
        } else {
          showInfoToast(context, AppStrings.salidaGuardadoLocalSync);
        }
      },
    );
    if (saved && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = 20 + MediaQuery.viewPaddingOf(context).bottom;
    final g = widget.grupo;

    return Scaffold(
      backgroundColor: context.scaffoldMuted,
      appBar: SectionAppBar(
        title: 'Registrar salida',
        sectionIcon: Icons.logout_rounded,
        showDrawerButton: false,
        actions: [AppBarSaveButton(onPressed: _guardar)],
      ),
      body: SafeArea(
        bottom: true,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad),
          children: [
            BioFormSection(
              title: 'Datos del ingreso',
              icon: Icons.fact_check_outlined,
              children: [
                BioReadOnlyField(
                  label: 'Fecha de ingreso',
                  value: _fmtFechaIngreso(g.fechaIngreso),
                  icon: Icons.calendar_today_rounded,
                ),
                const SizedBox(height: 10),
                BioReadOnlyField(
                  label: 'Proveedor',
                  value: g.proveedor,
                  icon: Icons.storefront_rounded,
                ),
                const SizedBox(height: 10),
                BioReadOnlyField(
                  label: 'Proceso / motivo',
                  value: g.motivo,
                  icon: Icons.account_tree_rounded,
                ),
                const SizedBox(height: 10),
                BioReadOnlyField(
                  label: 'Hora de ingreso',
                  value: g.horaIngreso,
                  icon: Icons.schedule_rounded,
                ),
              ],
            ),
            const SizedBox(height: 14),
            BioTimeField(
              label: 'Hora de salida',
              value: _hora,
              onPicked: (h) => setState(() => _hora = h),
            ),
            const SizedBox(height: 18),
            Text(
              'Tipo de salida',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: context.textThemeSecondary,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Definitiva'),
                  icon: Icon(Icons.done_all_rounded, size: 18),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Temporal'),
                  icon: Icon(Icons.schedule_rounded, size: 18),
                ),
              ],
              selected: {_salidaTemporal},
              onSelectionChanged: (s) =>
                  setState(() => _salidaTemporal = s.first),
            ),
            const SizedBox(height: 14),
            BioCheckListCard(
              title: 'Marque quién sale',
              icon: Icons.logout_rounded,
              emptyText: 'No hay personas dentro.',
              children: [
                if (g.dentro.isNotEmpty)
                  _filaCheck(
                    context,
                    CheckboxListTile(
                      value: _todosPersonasMarcados(g),
                      onChanged: (v) => setState(
                        () => _marcarTodosPersonas(g, v ?? false),
                      ),
                      title: Text(
                        'Todo el personal',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: context.textThemeSecondary,
                        ),
                      ),
                      controlAffinity: ListTileControlAffinity.trailing,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                for (final p in g.dentro)
                  _filaCheck(
                    context,
                    CheckboxListTile(
                      value: _selPersonas[p.dni] ?? false,
                      onChanged: (v) =>
                          setState(() => _selPersonas[p.dni] = v ?? false),
                      title: Text(
                        p.etiqueta,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: context.textThemePrimary,
                        ),
                      ),
                      subtitle: null,
                      controlAffinity: ListTileControlAffinity.trailing,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
              ],
            ),
            if (g.vehiculosDentro.isNotEmpty) ...[
              const SizedBox(height: 16),
              BioCheckListCard(
                title: 'Vehículos que salen',
                icon: Icons.directions_car_filled_rounded,
                children: [
                  _filaCheck(
                    context,
                    CheckboxListTile(
                      value: _todosVehiculosMarcados(g),
                      onChanged: (v) => setState(
                        () => _marcarTodosVehiculos(g, v ?? false),
                      ),
                      title: Text(
                        'Todos los vehículos',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: context.textThemeSecondary,
                        ),
                      ),
                      controlAffinity: ListTileControlAffinity.trailing,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                  for (final v in g.vehiculosDentro)
                    _filaCheck(
                      context,
                      CheckboxListTile(
                        value: _selVehiculos[v.clave] ?? false,
                        onChanged: (val) => setState(
                          () => _selVehiculos[v.clave] = val ?? false,
                        ),
                        title: Text(
                          v.etiqueta,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        controlAffinity: ListTileControlAffinity.trailing,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
