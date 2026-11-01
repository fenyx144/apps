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

class RegisterRegresoMovimientoScreen extends StatefulWidget {
  const RegisterRegresoMovimientoScreen({
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
  State<RegisterRegresoMovimientoScreen> createState() =>
      _RegisterRegresoMovimientoScreenState();
}

class _RegisterRegresoMovimientoScreenState
    extends State<RegisterRegresoMovimientoScreen> {
  late String _hora;
  late Map<String, bool> _selPersonas;
  late Map<String, bool> _selVehiculos;

  @override
  void initState() {
    super.initState();
    _hora = _horaDelDia(DateTime.now());
    _selPersonas = {
      for (final p in widget.grupo.fueraTemporal) p.dni: false,
    };
    _selVehiculos = {
      for (final v in widget.grupo.vehiculosFueraTemporal) v.clave: false,
    };
  }

  Future<void> _guardar() async {
    final personas = widget.grupo.fueraTemporal
        .where((p) => _selPersonas[p.dni] == true)
        .toList();
    final vehiculos = widget.grupo.vehiculosFueraTemporal
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
        'movimiento': 'regreso',
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
          showSuccessToast(context, AppStrings.regresoGuardadoEnviado);
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
        title: 'Registrar regreso',
        sectionIcon: Icons.login_rounded,
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
              ],
            ),
            const SizedBox(height: 14),
            BioTimeField(
              label: 'Hora de regreso',
              value: _hora,
              onPicked: (h) => setState(() => _hora = h),
            ),
            const SizedBox(height: 18),
            BioCheckListCard(
              title: 'Marque quién regresa',
              icon: Icons.badge_outlined,
              emptyText: 'Nadie en salida temporal en este ingreso.',
              children: [
                for (final p in g.fueraTemporal)
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
              ],
            ),
            if (g.vehiculosFueraTemporal.isNotEmpty) ...[
              const SizedBox(height: 16),
              BioCheckListCard(
                title: 'Vehículos que regresan',
                icon: Icons.directions_car_filled_rounded,
                children: [
                  for (final v in g.vehiculosFueraTemporal)
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
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
