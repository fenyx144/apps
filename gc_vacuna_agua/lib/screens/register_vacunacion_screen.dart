import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../services/api_service.dart';
import '../services/app_version_service.dart';
import '../services/catalog_service.dart';
import '../services/proveedor_vacuna_catalog_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/galpones_resolver.dart';
import '../utils/record_saver.dart';
import '../utils/toast_helper.dart';
import '../utils/vacuna_payload.dart';
import '../widgets/app_drawer.dart';
import '../widgets/bio_form_fields.dart';
import '../widgets/bio_table.dart';
import '../widgets/evidencia_select_field.dart';
import '../widgets/granja_campania_fields.dart';
import '../widgets/granja_campania_picker.dart';
import '../widgets/image_slot_row.dart';
import '../widgets/section_app_bar.dart';
import '../widgets/laboratorio_picker.dart';
import '../widgets/proveedor_dialog.dart';
import '../widgets/vacuna_producto_field.dart';
import '../widgets/vacunacion_secciones.dart';
import 'register_summary_screen.dart';

/// Temperatura: admite signo y un decimal (p. ej. -2.5, 8.0).
class _Temperatura extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final t = newValue.text;
    if (t.isEmpty || RegExp(r'^-?\d{0,3}([.,]\d{0,1})?$').hasMatch(t)) {
      return newValue;
    }
    return oldValue;
  }
}

/// Un recurso del equipo de vacunación con estado operativo.
class _EquipoItem {
  _EquipoItem(this.nombre, {this.obsSiempre = false});

  final String nombre;
  final bool obsSiempre;
  /// Por defecto operativo (Sí en verde).
  bool operativo = true;
  final TextEditingController obs = TextEditingController();

  void dispose() => obs.dispose();
}

/// Fila fija de la tabla de cadena de frío.
class _FrioFila {
  _FrioFila(this.descripcion);

  final String descripcion;
  String hora = '';
  final TextEditingController temperatura = TextEditingController();

  void dispose() => temperatura.dispose();
}

/// Registro de Vacunación: información de la vacuna, galpones con su edad,
/// evidencias fotográficas, cadena de frío y equipo de vacunación.
class RegisterVacunacionScreen extends StatefulWidget {
  const RegisterVacunacionScreen({super.key});

  @override
  State<RegisterVacunacionScreen> createState() =>
      _RegisterVacunacionScreenState();
}

class _RegisterVacunacionScreenState extends State<RegisterVacunacionScreen> {
  DateTime _fecha = DateTime.now();

  String _granja3 = '';
  String _granjaNombre = '';
  String _campania3 = '';
  List<String> _campanias = const [];

  List<String> _galponesOpts = const [];
  List<Map<String, dynamic>> _galponesMeta = const [];
  List<String> _galponesSel = [];
  int? _edad;

  /// Nombre de la vacuna elegida del catálogo de productos (línea de vacunas).
  String _nombreVacuna = '';
  final _lote = TextEditingController();
  DateTime? _fechaExp;
  final _dosis = TextEditingController();
  ProveedorSeleccion _laboratorio = ProveedorSeleccion.vacia;

  final _imagenes = List<String?>.filled(3, null);

  late final List<_FrioFila> _frio = [
    _FrioFila('Salida de Almacen'),
    _FrioFila('Inicio de proceso'),
    _FrioFila('Vacuna preparada (antes de la aplicación)'),
  ];

  /// Equipo de vacunación. El listado sale del catálogo (`equipovacunacion`)
  /// para que agregar un recurso en la base no requiera publicar la app.
  List<_EquipoItem> _equipo = const [];

  /// Cambia al guardar para que las secciones 5 a 8 (que tienen su propio
  /// estado) se vuelvan a montar vacías junto con el resto del formulario.
  int _generacionForm = 0;

  /// Recolector del detalle de las secciones 5 a 8, para armar el payload.
  final VacunacionDetalleController _detalleSecciones =
      VacunacionDetalleController();

  @override
  void initState() {
    super.initState();
    _equipo = _equipoDesdeCatalogo();
    WidgetsBinding.instance.addPostFrameCallback((_) => _precargarGranja());
  }

  List<_EquipoItem> _equipoDesdeCatalogo() {
    final catalog = context.read<CatalogService>();
    return [
      for (final e in catalog.equiposVacunacion)
        _EquipoItem(
          CatalogService.esRecursoOtro(e['descripcion'] ?? '')
              ? 'Otro'
              : (e['descripcion'] ?? '').trim(),
          obsSiempre: CatalogService.esRecursoOtro(e['descripcion'] ?? ''),
        ),
    ];
  }

  @override
  void dispose() {
    _lote.dispose();
    _dosis.dispose();
    for (final f in _frio) {
      f.dispose();
    }
    for (final e in _equipo) {
      e.dispose();
    }
    super.dispose();
  }

  String get _fechaYmd => DateFormat('yyyy-MM-dd').format(_fecha);
  String get _fechaDisplay => DateFormat('dd/MM/yyyy').format(_fecha);

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
    _cargarGalpones();
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
    _cargarGalpones();
  }

  Future<void> _elegirLaboratorio() async {
    final storage = context.read<StorageService>();
    final catalogo = ProveedorVacunaCatalogService(storage);
    final api = ApiService();
    final sel = await showLaboratorioListaDialog(
      context: context,
      catalogo: catalogo,
      actual: _laboratorio,
      buscarEnLinea: (q) => api.buscarProveedorCcte(q, fallbackCcte: true),
    );
    if (sel == null) return;
    setState(() => _laboratorio = sel);
  }

  String get _laboratorioEtiqueta {
    final n = _laboratorio.nombre.trim();
    if (n.isNotEmpty) return n;
    return _laboratorio.ruc.trim();
  }

  Future<void> _elegirFechaExp() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _fechaExp ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      locale: const Locale('es', 'ES'),
    );
    if (d == null) return;
    setState(() => _fechaExp = d);
  }

  /// Galpones disponibles según la granja/campaña y el catálogo local.
  void _cargarGalpones() {
    if (!mounted || _granja3.isEmpty) {
      setState(() {
        _galponesOpts = const [];
        _galponesMeta = const [];
        _galponesSel = [];
        _edad = null;
      });
      return;
    }
    final storage = context.read<StorageService>();
    final lista = GalponesResolver.resolveOffline(
      granjaCodigo: _granja3,
      campania: _campania3,
      galponesPorGranja: storage.getGalponesPorGranjaMapLocal(),
      galponesPorCenco: storage.getGalponesPorCencoLocal(),
      cencosLista: storage.getCencosListaLocal(),
    );
    final codigos = <String>[];
    for (final g in lista) {
      final c = (g['tcodint'] ?? g['galpon'] ?? '').toString().trim();
      if (c.isNotEmpty && !codigos.contains(c)) codigos.add(c);
    }
    codigos.sort();
    setState(() {
      _galponesMeta = lista;
      _galponesOpts = codigos;
      _galponesSel = _galponesSel.where(codigos.contains).toList();
      _recalcularEdad();
    });
  }

  void _recalcularEdad() {
    _edad = GranjaCampaniaPicker.edadPromedioGalponesEnFecha(
      galponesMeta: _galponesMeta,
      galponesSel: _galponesSel,
      fechaYmd: _fechaYmd,
    );
  }

  double? _tempValida(TextEditingController c) {
    final raw = c.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
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
    if (_galponesSel.isEmpty) {
      showErrorToast(context, 'Seleccione al menos un galpón.');
      return;
    }
    if (_nombreVacuna.trim().isEmpty) {
      showErrorToast(context, 'Seleccione la vacuna aplicada.');
      return;
    }
    for (final f in _frio) {
      if (f.hora.isEmpty || _tempValida(f.temperatura) == null) {
        showErrorToast(
          context,
          'Complete hora y temperatura en «${f.descripcion}».',
        );
        return;
      }
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
      'reporte': 'vacunacion',
      'fecha': _fechaYmd,
      'granja': _granja3,
      'granjaNombre': _granjaNombre,
      'campania': _campania3,
      'nombre_usuario': storage.getUserName() ?? '',
      'turno': '',
      'synced': false,
      'imagenes': [
        for (final p in _imagenes)
          if (p != null && p.isNotEmpty) {'path': p},
      ],
      'registro': vacunacionRegistro(
        galpones: _galponesSel,
        edad: _edad,
        vacuna: _nombreVacuna,
        lote: _lote.text.trim(),
        expiracion: _fechaExp,
        dosisFrasco: _dosis.text.trim(),
        laboratorio: _laboratorioEtiqueta,
        responsable: storage.getUserName() ?? '',
        detalle: [
          ...detalleCadenaFrio([
            for (final f in _frio)
              (
                descripcion: f.descripcion,
                hora: f.hora,
                temperatura: _tempValida(f.temperatura)!,
              ),
          ]),
          ...detalleEquipo([
            for (final e in _equipo)
              (
                recurso: e.nombre,
                operativo: e.operativo,
                descripcion: e.obs.text.trim(),
              ),
          ]),
          // Secciones 5 a 8: cada bloque entrega sus filas al guardar.
          ..._detalleSecciones.filas(),
        ],
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
      _galponesSel = [];
      _galponesOpts = const [];
      _galponesMeta = const [];
      _edad = null;
      _nombreVacuna = '';
      _lote.clear();
      _fechaExp = null;
      _dosis.clear();
      _laboratorio = ProveedorSeleccion.vacia;
      for (final f in _frio) {
        f.hora = '';
        f.temperatura.clear();
      }
      for (final e in _equipo) {
        e.operativo = true;
        e.obs.clear();
      }
      _generacionForm++;
      for (var i = 0; i < _imagenes.length; i++) {
        _imagenes[i] = null;
      }
    });
    if (trabajo != null) {
      _cargarGalpones();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: SectionAppBar(
        title: AppStrings.menuVacunacion,
        sectionIcon: Icons.vaccines_outlined,
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
                  onSeleccion: (sel) {
                    setState(() {
                      _granja3 = sel.granja;
                      _granjaNombre = sel.granjaNombre;
                      _campania3 = sel.campania;
                      _campanias = sel.campanias;
                    });
                    _cargarGalpones();
                  },
                ),
              ],
            ),
            const SizedBox(height: 22),
            BioFormSection(
              title: 'Información de vacuna',
              icon: Icons.vaccines_outlined,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: EvidenciaGalponField(
                        label: 'Galpones',
                        value: _galponesSel,
                        options: _galponesOpts,
                        onSelected: (sel) => setState(() {
                          _galponesSel = sel;
                          _recalcularEdad();
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: EvidenciaSelectField(
                        label: 'Edad',
                        value: _edad == null ? '' : '$_edad días',
                        placeholder: '—',
                        icon: Icons.cake_outlined,
                        showIcon: false,
                        enabled: false,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                VacunaProductoField(
                  value: _nombreVacuna,
                  options: context.watch<CatalogService>().vacunas,
                  onSelected: (v) => setState(() => _nombreVacuna = v),
                ),
                const SizedBox(height: 12),
                EvidenciaSelectField(
                  label: 'Fecha de expiración',
                  value: _fechaExp == null
                      ? ''
                      : DateFormat('dd/MM/yyyy').format(_fechaExp!),
                  placeholder: 'Seleccione',
                  icon: Icons.event_busy_rounded,
                  onTap: _elegirFechaExp,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _lote,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Lote de vacuna',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _dosis,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Dosis de frasco',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                EvidenciaSelectField(
                  label: 'Laboratorio de vacuna',
                  value: _laboratorioEtiqueta,
                  placeholder: 'Seleccionar laboratorio',
                  icon: Icons.biotech_outlined,
                  onTap: _elegirLaboratorio,
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
            const SizedBox(height: 22),
            BioSectionTitle(
              title: 'Cadena de frío',
              icon: Icons.ac_unit_rounded,
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
                  BioColumn('Descripción', width: 170, align: TextAlign.left),
                  BioColumn('Hora', width: 92),
                  BioColumn('Temperatura', width: 100),
                ],
                rowCount: _frio.length,
                rowBuilder: (context, index) {
                  final fila = _frio[index];
                  return [
                    BioText(
                      fila.descripcion,
                      align: TextAlign.left,
                      bold: true,
                      fontSize: 11.5,
                    ),
                    _celdaHora(fila),
                    BioTextField(
                      controller: fila.temperatura,
                      hint: '0.0',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      textAlign: TextAlign.center,
                      inputFormatters: [_Temperatura()],
                      bold: true,
                    ),
                  ];
                },
              ),
            ),
            const SizedBox(height: 22),
            BioSectionTitle(
              title: 'Equipo de vacunación',
              icon: Icons.handyman_outlined,
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
                  BioColumn('Recurso', width: 150, align: TextAlign.left),
                  BioColumn('¿Operativa?', width: 96),
                  BioColumn('Observación', width: 150, flex: 1),
                ],
                rowCount: _equipo.length,
                rowBuilder: (context, index) {
                  final item = _equipo[index];
                  return [
                    BioText(
                      item.nombre,
                      align: TextAlign.left,
                      bold: true,
                      fontSize: 11.5,
                    ),
                    BioSwitchCumple(
                      value: item.operativo,
                      onChanged: (v) => setState(() => item.operativo = v),
                    ),
                    BioTextField(
                      controller: item.obs,
                      enabled: item.obsSiempre || !item.operativo,
                      hint: item.obsSiempre
                          ? 'Describa'
                          : (item.operativo ? '—' : 'Detalle'),
                      maxLength: 80,
                    ),
                  ];
                },
              ),
            ),
            const SizedBox(height: 22),
            BioSectionTitle(
              title: 'Tiempo de Sedeo (horas)',
              icon: Icons.timer_outlined,
            ),
            const SizedBox(height: 8),
            TiempoSedeoSection(
              key: ValueKey('sedeo$_generacionForm'),
              galpones: _galponesSel,
              detalle: _detalleSecciones,
            ),
            const SizedBox(height: 22),
            BioSectionTitle(
              title: 'Verificación del sistema de bebederos',
              icon: Icons.water_outlined,
            ),
            const SizedBox(height: 8),
            VerificacionBebederosSection(
              key: ValueKey('bebederos$_generacionForm'),
              detalle: _detalleSecciones,
            ),
            const SizedBox(height: 22),
            BioSectionTitle(
              title: 'Preparación de solución vacunal',
              icon: Icons.science_outlined,
            ),
            const SizedBox(height: 8),
            PreparacionSolucionSection(
              key: ValueKey('solucion$_generacionForm'),
              galpones: _galponesSel,
              edad: _edad,
              detalle: _detalleSecciones,
            ),
            const SizedBox(height: 22),
            BioSectionTitle(
              title: 'Evaluación de eficiencia de vacunación',
              icon: Icons.fact_check_outlined,
            ),
            const SizedBox(height: 8),
            EvaluacionEficienciaSection(
              key: ValueKey('eficiencia$_generacionForm'),
              galpones: _galponesSel,
              detalle: _detalleSecciones,
            ),
          ],
        ),
      ),
    );
  }

  Widget _celdaHora(_FrioFila fila) {
    return InkWell(
      onTap: () async {
        final h = await showBioHoraDialog(context, valorActual: fila.hora);
        if (h == null) return;
        setState(() => fila.hora = h);
      },
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          fila.hora.isEmpty ? '--:--' : fila.hora,
          style: TextStyle(
            fontSize: 12,
            fontWeight: fila.hora.isEmpty ? FontWeight.w500 : FontWeight.w700,
            color: fila.hora.isEmpty
                ? AppColors.textMuted
                : AppColors.horaText,
          ),
        ),
      ),
    );
  }
}
