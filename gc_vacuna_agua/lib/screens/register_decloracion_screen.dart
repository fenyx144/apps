import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../services/app_version_service.dart';
import '../services/storage_service.dart';
import '../utils/app_theme.dart';
import '../utils/constants.dart';
import '../utils/record_saver.dart';
import '../utils/toast_helper.dart';
import '../utils/vacuna_payload.dart';
import '../widgets/app_drawer.dart';
import '../widgets/bio_form_fields.dart';
import '../widgets/bio_table.dart';
import '../widgets/evidencia_select_field.dart';
import '../widgets/granja_campania_fields.dart';
import '../widgets/image_slot_row.dart';
import '../widgets/section_app_bar.dart';
import 'register_summary_screen.dart';

/// Formato que admite solo números con hasta dos decimales (cloro residual).
class _DosDecimales extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final t = newValue.text;
    if (t.isEmpty || RegExp(r'^\d{0,3}([.]\d{0,2})?$').hasMatch(t)) {
      return newValue;
    }
    return oldValue;
  }
}

/// Registro de Decloración: fecha, granja/campaña, tabla Inicio/Final con
/// hora y cloro residual (2 decimales), responsable y observaciones.
class RegisterDecloracionScreen extends StatefulWidget {
  const RegisterDecloracionScreen({super.key});

  @override
  State<RegisterDecloracionScreen> createState() =>
      _RegisterDecloracionScreenState();
}

class _RegisterDecloracionScreenState
    extends State<RegisterDecloracionScreen> {
  DateTime _fecha = DateTime.now();

  String _granja3 = '';
  String _granjaNombre = '';
  String _campania3 = '';
  List<String> _campanias = const [];

  String _horaInicio = '';
  String _horaFinal = '';
  final _cloroInicio = TextEditingController();
  final _cloroFinal = TextEditingController();
  final _responsable = TextEditingController();
  final _observaciones = TextEditingController();

  /// Evidencias fotográficas: los tres recuadros del formato de campo.
  final _imagenes = List<String?>.filled(3, null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _precargar());
  }

  @override
  void dispose() {
    _cloroInicio.dispose();
    _cloroFinal.dispose();
    _responsable.dispose();
    _observaciones.dispose();
    super.dispose();
  }

  String get _fechaYmd => DateFormat('yyyy-MM-dd').format(_fecha);
  String get _fechaDisplay => DateFormat('dd/MM/yyyy').format(_fecha);

  void _precargar() {
    if (!mounted) return;
    final storage = context.read<StorageService>();
    // El responsable se premarca con el nombre del usuario que inició sesión
    // (no su código): es el mismo nombre que el listado muestra por defecto, y
    // el campo queda editable para cuando firma otra persona.
    final nombre = (storage.getUserName() ?? '').trim();
    if (nombre.isNotEmpty) {
      _responsable.text = nombre;
    }
    _precargarGranja();
  }

  void _precargarGranja() {
    if (!mounted) return;
    final sel = granjaDeTrabajoSeleccion(
      context.read<StorageService>(),
      fechaYmd: _fechaYmd,
    );
    if (sel == null) return;
    setState(() {
      _granja3 = sel.granja;
      _granjaNombre = sel.granjaNombre;
      _campania3 = sel.campania;
      _campanias = sel.campanias;
    });
  }

  Future<void> _elegirFecha() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('es', 'ES'),
    );
    if (d == null) return;
    setState(() => _fecha = d);
  }

  Widget _celdaHora(bool esInicio) {
    final valor = esInicio ? _horaInicio : _horaFinal;
    return InkWell(
      onTap: () async {
        final h = await showBioHoraDialog(context, valorActual: valor);
        if (h == null) return;
        setState(() {
          if (esInicio) {
            _horaInicio = h;
          } else {
            _horaFinal = h;
          }
        });
      },
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          valor.isEmpty ? '--:--' : valor,
          style: TextStyle(
            fontSize: 12,
            fontWeight: valor.isEmpty ? FontWeight.w500 : FontWeight.w700,
            color: valor.isEmpty
                ? AppColors.textMuted
                : AppColors.horaText,
          ),
        ),
      ),
    );
  }

  double? _cloroValido(TextEditingController c) {
    final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
    if (v == null || v < 0 || v > 10) return null;
    return v;
  }

  Future<void> _guardar() async {
    if (_granja3.isEmpty) {
      showErrorToast(context, 'Seleccione la granja.');
      return;
    }
    if (_campania3.isEmpty) {
      showErrorToast(context, 'Seleccione la campaña.');
      return;
    }
    if (_horaInicio.isEmpty || _horaFinal.isEmpty) {
      showErrorToast(context, 'Ingrese la hora de inicio y final.');
      return;
    }
    final ci = _cloroValido(_cloroInicio);
    final cf = _cloroValido(_cloroFinal);
    if (ci == null || cf == null) {
      showErrorToast(
        context,
        'Ingrese el cloro residual con hasta 2 decimales (0.00 - 10.00).',
      );
      return;
    }
    if (_responsable.text.trim().isEmpty) {
      showErrorToast(context, 'Ingrese el responsable de decloración.');
      return;
    }

    final storage = context.read<StorageService>();
    final verSt = AppVersionService.fromStorage(storage);
    if (verSt.mustUpdate) {
      await AppVersionService.showStatusDialog(
        context,
        verSt,
        barrierDismissible: false,
      );
      return;
    }
    await AppVersionService.notifyIfNeeded(context, storage);
    final record = <String, dynamic>{
      'id': const Uuid().v4(),
      'created_at': DateTime.now().toIso8601String(),
      'reporte': 'decloracion',
      'fecha': _fechaYmd,
      'granja': _granja3,
      'granjaNombre': _granjaNombre,
      'campania': _campania3,
      'nombre_usuario': storage.getUserName() ?? '',
      'turno': '',
      'synced': false,
      // Se guarda sólo lo que se cargó: un recuadro vacío no viaja al servidor.
      'imagenes': [
        for (final p in _imagenes)
          if (p != null && p.isNotEmpty) {'path': p},
      ],
      'registro': decloracionRegistro(
        horaInicio: _horaInicio,
        horaFinal: _horaFinal,
        cloroInicio: ci,
        cloroFinal: cf,
        responsable: _responsable.text.trim(),
        observacion: _observaciones.text.trim(),
      ),
    };

    final confirmado = await RegisterSummarySheet.show(
      context,
      record: record,
      onConfirm: () async {
        final ok = await BioRecordSaver.save(context, record);
        if (!context.mounted) return;
        if (ok) {
          showSuccessToast(context, 'Registro guardado y enviado.');
        } else {
          showInfoToast(
            context,
            'Registro guardado en el dispositivo. Podrá subirlo desde el menú.',
          );
        }
      },
    );
    if (!mounted || !confirmado) return;

    _limpiarTrasGuardar();
  }

  void _limpiarTrasGuardar() {
    FocusManager.instance.primaryFocus?.unfocus();
    final storage = context.read<StorageService>();
    final trabajo = granjaCamposTrasGuardar(storage, fechaYmd: _fechaYmd);
    setState(() {
      _horaInicio = '';
      _horaFinal = '';
      _cloroInicio.clear();
      _cloroFinal.clear();
      _observaciones.clear();
      if (trabajo != null) {
        _granja3 = trabajo.granja;
        _granjaNombre = trabajo.granjaNombre;
        _campania3 = trabajo.campania;
        _campanias = trabajo.campanias;
      } else {
        _granja3 = '';
        _granjaNombre = '';
        _campania3 = '';
        _campanias = const [];
      }
      for (var i = 0; i < _imagenes.length; i++) {
        _imagenes[i] = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: SectionAppBar(
        title: AppStrings.menuDecloracion,
        sectionIcon: Icons.water_drop_outlined,
        actions: [AppBarSaveButton(onPressed: _guardar)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BioFormSection(
              title: 'Datos generales',
              icon: Icons.event_note_outlined,
              children: [
                EvidenciaSelectField(
                  label: 'Fecha',
                  value: _fechaDisplay,
                  placeholder: 'Seleccione',
                  icon: Icons.calendar_today_rounded,
                  onTap: _elegirFecha,
                ),
                const SizedBox(height: 12),
                GranjaCampaniaFields(
                  fechaYmd: _fechaYmd,
                  granja: _granja3,
                  granjaNombre: _granjaNombre,
                  campania: _campania3,
                  campanias: _campanias,
                  onSeleccion: (sel) => setState(() {
                    _granja3 = sel.granja;
                    _granjaNombre = sel.granjaNombre;
                    _campania3 = sel.campania;
                    _campanias = sel.campanias;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 22),
            BioSectionTitle(
              title: 'Cloro residual',
              icon: Icons.science_outlined,
            ),
            const SizedBox(height: 8),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppColors.radiusSm),
              ),
              child: BioTable(
                rowHeight: 48,
                columns: const [
                  BioColumn('Momento', width: 96, align: TextAlign.left),
                  BioColumn('Hora', width: 96, flex: 1),
                  BioColumn('Cloro residual', width: 130, flex: 1),
                ],
                rowCount: 2,
                rowBuilder: (context, index) {
                  final esInicio = index == 0;
                  return [
                    BioText(
                      esInicio ? 'Inicio' : 'Final',
                      align: TextAlign.left,
                      bold: true,
                      fontSize: 12,
                    ),
                    _celdaHora(esInicio),
                    BioTextField(
                      controller: esInicio ? _cloroInicio : _cloroFinal,
                      hint: '0.00',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign: TextAlign.center,
                      inputFormatters: [_DosDecimales()],
                      bold: true,
                    ),
                  ];
                },
              ),
            ),
            const SizedBox(height: 22),
            BioFormSection(
              title: 'Responsable y observaciones',
              icon: Icons.person_outline_rounded,
              children: [
                TextField(
                  controller: _responsable,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Nombre de responsable de decloración',
                    prefixIcon: Icon(
                      Icons.badge_outlined,
                      color: context.formColors.iconAccent,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                BioTextArea(
                  label: 'Observaciones',
                  controller: _observaciones,
                  maxLength: 300,
                  icon: Icons.notes_rounded,
                ),
              ],
            ),
            const SizedBox(height: 22),
            BioSectionTitle(
              title: 'Evidencias',
              icon: Icons.photo_camera_outlined,
            ),
            const SizedBox(height: 6),
            ImageSlotRow(
              paths: _imagenes,
              onChanged: (i, p) => setState(() => _imagenes[i] = p),
            ),
          ],
        ),
      ),
    );
  }
}
