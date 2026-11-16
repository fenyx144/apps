import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../services/app_version_service.dart';
import '../services/catalog_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/record_saver.dart';
import '../utils/theme_colors.dart';
import '../utils/toast_helper.dart';
import '../widgets/app_drawer.dart';
import '../widgets/bio_form_fields.dart';
import '../widgets/evidencia_select_field.dart';
import '../widgets/granja_campania_fields.dart';
import '../widgets/image_slot_row.dart';
import '../widgets/opcion_catalogo_dialog.dart';
import '../widgets/section_app_bar.dart';
import 'register_summary_screen.dart';

class RegisterGaritaScreen extends StatefulWidget {
  const RegisterGaritaScreen({
    super.key,
    this.bioseguridadInicial,
    this.tipoInicial,
  });

  /// Tipo de bioseguridad precargado («Bioseguridad quimica», etc.).
  /// Anomalías existe en los tres grupos del drawer: al entrar por química o
  /// biológica el formulario abre con ese tipo elegido.
  final String? bioseguridadInicial;

  /// Grupo de navegación ([BioTipos]) desde el que se abrió la pantalla; se usa
  /// cuando no llega [bioseguridadInicial].
  final String? tipoInicial;

  @override
  State<RegisterGaritaScreen> createState() => _RegisterGaritaScreenState();
}

class _RegisterGaritaScreenState extends State<RegisterGaritaScreen> {
  final _descripcionController = TextEditingController();
  final _agenteCausalController = TextEditingController();

  /// Fecha del registro (solo lectura, siempre el día de hoy).
  final DateTime _fecha = DateTime.now();
  String _granja = '';
  String _granjaNombre = '';
  String _campania = '';
  List<String> _campaniasDisponibles = const [];
  String _turno = 'Dia';
  String _instalacion = 'Garita';

  /// Código del catálogo de instalaciones elegido. La garita es el código `1`;
  /// con esto el filtro no depende del texto («Garita») y renombrarla en el
  /// servidor no lo rompe.
  String _instalacionCodigo = '1';
  late String _bioseguridad;
  int _filtro = 1;
  final List<String?> _imagenes = [null, null, null];

  /// Solo la garita tiene filtros numerados; tranquera y pozo séptico no.
  bool get _esGarita => _instalacionCodigo == '1';

  String get _fechaYmd => DateFormat('yyyy-MM-dd').format(_fecha);

  @override
  void initState() {
    super.initState();
    _bioseguridad = widget.bioseguridadInicial ??
        BioTipos.descripcion[widget.tipoInicial ?? BioTipos.fisica] ??
        BioTipos.descripcion[BioTipos.fisica]!;
    _aplicarGranjaDeTrabajo();
  }

  /// Premarca la granja de trabajo (menú Mi granja) con su campaña sugerida.
  void _aplicarGranjaDeTrabajo() {
    final sel = granjaDeTrabajoSeleccion(
      context.read<StorageService>(),
      fechaYmd: _fechaYmd,
    );
    if (sel == null) return;
    _granja = sel.granja;
    _granjaNombre = sel.granjaNombre;
    _campania = sel.campania;
    _campaniasDisponibles = sel.campanias;
  }

  @override
  void dispose() {
    _descripcionController.dispose();
    _agenteCausalController.dispose();
    super.dispose();
  }

  // La fecha es de solo lectura: el registro es del día en que se hace.

  /// Guarda la granja y/o campaña elegidas en [GranjaCampaniaFields].
  void _onGranjaCampania(GranjaCampaniaSeleccion sel) {
    setState(() {
      _granja = sel.granja;
      _granjaNombre = sel.granjaNombre;
      _campania = sel.campania;
      _campaniasDisponibles = sel.campanias;
    });
  }

  Future<void> _pickTurno() async {
    final opciones = context.read<CatalogService>().turnos;
    if (!bioHayCatalogo(context, opciones)) return;
    final sel = await showBioOptionsSheet<String>(
      context: context,
      title: 'Seleccionar turno',
      options: opciones,
      labelOf: (t) => t == 'Dia' ? 'Día' : 'Noche',
      selected: _turno,
    );
    if (sel != null) setState(() => _turno = sel);
  }

  Future<void> _pickInstalacion() async {
    final catalog = context.read<CatalogService>();
    final opciones = catalog.instalaciones;
    if (!bioHayCatalogo(context, opciones)) return;
    // El catálogo trae garita, tranquera y pozo séptico, pero el recorrido
    // encuentra otros puntos. «Otros» es una fila más (se agrega si el servidor
    // todavía no la envía) y al elegirla se escribe el nombre del punto; queda
    // sin código, así que no arrastra el filtro de la garita.
    final sel = await showOpcionCatalogoDialog(
      context: context,
      title: 'Seleccionar instalación',
      opciones: opciones,
      actual: OpcionCatalogo(valor: _instalacion, codigo: _instalacionCodigo),
      icon: Icons.location_on_rounded,
      otroLabel: 'Instalación',
      otroHint: 'Escriba el punto inspeccionado',
      // `rgarita.instalacion` es varchar(20): más largo no entra en la columna.
      otroMaxLength: 20,
    );
    if (sel != null) {
      setState(() {
        _instalacion = sel.valor;
        _instalacionCodigo = sel.codigo.isEmpty ? '0' : sel.codigo;
      });
    }
  }

  Future<void> _pickFiltro() async {
    final catalog = context.read<CatalogService>();
    final opciones = catalog.filtros;
    if (!bioHayCatalogo(context, opciones)) return;
    final sel = await showBioOptionsSheet<int>(
      context: context,
      title: 'Seleccionar filtro',
      options: opciones,
      labelOf: (n) => 'Filtro $n',
      selected: _filtro,
    );
    if (sel != null) setState(() => _filtro = sel);
  }

  Map<String, dynamic> _buildRecord(StorageService storage) {
    final imagenes = _imagenes
        .whereType<String>()
        .where((p) => p.trim().isNotEmpty)
        .map((p) => {'path': p})
        .toList();

    return {
      'id': const Uuid().v4(),
      'reporte': 'garita',
      'fecha': _fechaYmd,
      'granja': _granja,
      'granjaNombre': _granjaNombre,
      'campania': _campania,
      'turno': _turno,
      'usuario': storage.getUserCodeSync() ?? '',
      'nombre_usuario': storage.getUserName() ?? '',
      'registro': {
        'instalacion': _instalacion,
        'bioseguridad': _bioseguridad,
        // El backend legacy exige numfiltro entre 1 y 3, así que fuera de la
        // garita se envía 1 como relleno; el campo no se muestra al usuario.
        'numfiltro': _esGarita ? _filtro : 1,
        'hora': _hora24(),
        'descripcion': _descripcionController.text.trim(),
        'agentecausal': _agenteCausalController.text.trim(),
      },
      'imagenes': imagenes,
      'synced': false,
      'guardado_backend': false,
      'created_at': DateTime.now().toIso8601String(),
    };
  }

  String _hora24() {
    final now = TimeOfDay.now();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _guardar() async {
    if (_granja.isEmpty) {
      showErrorToast(context, 'Seleccione la granja.');
      return;
    }
    if (_campania.isEmpty) {
      showErrorToast(context, 'Seleccione la campaña.');
      return;
    }
    if (_bioseguridad.trim().isEmpty) {
      showErrorToast(context, 'Seleccione el tipo de bioseguridad.');
      return;
    }
    if (_descripcionController.text.trim().isEmpty &&
        _agenteCausalController.text.trim().isEmpty) {
      showErrorToast(context, 'Ingrese la descripción o el agente causal.');
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;

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
    if (!mounted) return;
    await AppVersionService.notifyIfNeeded(context, storage);
    if (!mounted) return;

    final record = _buildRecord(storage);

    final saved = await RegisterSummarySheet.show(
      context,
      record: record,
      onConfirm: () async {
        final ok = await BioRecordSaver.save(context, record);
        if (!mounted) return;
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

    if (saved && mounted) {
      setState(() {
        _descripcionController.clear();
        _agenteCausalController.clear();
        _imagenes
          ..clear()
          ..addAll([null, null, null]);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: SectionAppBar(
        title: AppStrings.menuInstalaciones,
        sectionIcon: kIconoAnomalias,
        actions: [AppBarSaveButton(onPressed: _guardar)],
      ),
      // El espacio inferior suma la barra de navegación del sistema: sin eso el
      // bloque de evidencias quedaba tapado por ella en pantalla completa.
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          32 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BioCatalogoAviso(),
            BioFormSection(
              title: 'DATOS DEL REGISTRO',
              icon: Icons.event_rounded,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: EvidenciaSelectField(
                        label: 'Fecha',
                        value: DateFormat('dd/MM/yyyy').format(_fecha),
                        placeholder: 'Hoy',
                        // Solo lectura: es la fecha de hoy (ver [_fecha]).
                        icon: Icons.calendar_month_rounded,
                        iconColor: context.textThemeMuted,
                        enabled: false,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: EvidenciaSelectField(
                        label: 'Turno',
                        value: _turno == 'Dia' ? 'Día' : 'Noche',
                        placeholder: 'Seleccione',
                        icon: Icons.wb_twilight_rounded,
                        onTap: _pickTurno,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                GranjaCampaniaFields(
                  fechaYmd: _fechaYmd,
                  granja: _granja,
                  granjaNombre: _granjaNombre,
                  campania: _campania,
                  campanias: _campaniasDisponibles,
                  onSeleccion: _onGranjaCampania,
                ),
                // El tipo de bioseguridad va antes de la instalación y es de
                // solo lectura: lo decide el grupo del menú por el que se entró
                // (Física, Química o Biológica), que es también el que elige la
                // pestaña del reporte web donde cae el registro. Antes era un
                // selector editable acá, y se podía grabar una anomalía química
                // desde la sección de física.
                const SizedBox(height: 12),
                EvidenciaSelectField(
                  label: 'Tipo de bioseguridad',
                  value: _bioseguridad,
                  placeholder: '—',
                  icon: iconoTipoBioseguridad(widget.tipoInicial),
                  iconColor: context.textThemeMuted,
                  enabled: false,
                  maxLines: 1,
                 /* hint: 'Lo define la sección del menú (Física, Química o '
                      'Biológica); no se cambia acá.',*/
                ),
                const SizedBox(height: 12),
                EvidenciaSelectField(
                  label: 'Instalación',
                  value: _instalacion,
                  placeholder: 'Seleccione',
                  icon: Icons.location_on_rounded,
                  onTap: _pickInstalacion,
                ),
                // El filtro solo se pide en la garita: tranquera y pozo
                // séptico no tienen filtros numerados.
                if (_esGarita) ...[
                  const SizedBox(height: 12),
                  EvidenciaSelectField(
                    label: 'Filtro',
                    value: 'Filtro $_filtro',
                    placeholder: 'Seleccione',
                    icon: Icons.filter_alt_rounded,
                    onTap: _pickFiltro,
                  ),
                ],
                /*if (_campaniasDisponibles.length > 1) ...[
                  const SizedBox(height: 10),
                  BioInfoBanner(
                    icon: Icons.info_outline_rounded,
                    text: 'Campaña seleccionada: '
                        '${GranjaCampaniaPicker.padCampania(_campania)}. '
                        'Toca «Campaña» para cambiarla.',
                  ),
                ],*/
              ],
            ),
            const SizedBox(height: 20),
            BioFormSection(
              // «Detalle de anomalía» repetía el nombre del campo de adentro y
              // dejaba afuera el agente causal, que es el otro dato del bloque.
              title: 'DESCRIPCIÓN DE LA ANOMALÍA',
              icon: Icons.edit_note_rounded,
              children: [
                BioTextArea(
                  label: 'Detalle de anomalía',
                  controller: _descripcionController,
                  hint: 'Detalle de lo observado',
                  icon: Icons.edit_rounded,
                  maxLength: 200,
                ),
                const SizedBox(height: 12),
                BioTextArea(
                  label: 'Agente causal',
                  controller: _agenteCausalController,
                  hint: 'Agente causal identificado',
                  icon: Icons.edit_rounded,
                  maxLength: 200,
                  textCapitalization: TextCapitalization.none,
                ),
              ],
            ),
            const SizedBox(height: 20),
            BioFormSection(
              title: 'EVIDENCIAS (MÁX. 3)',
              icon: Icons.photo_camera_rounded,
              children: [
                ImageSlotRow(
                  paths: _imagenes,
                  onChanged: (i, path) => setState(() => _imagenes[i] = path),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
