import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../services/app_version_service.dart';
import '../services/catalog_service.dart';
import '../services/deep_link_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/record_id.dart';
import '../utils/record_saver.dart';
import '../utils/theme_colors.dart';
import '../utils/toast_helper.dart';
import '../widgets/app_drawer.dart';
import '../widgets/bio_form_fields.dart';
import '../widgets/bio_table.dart';
import '../widgets/evidencia_select_field.dart';
import '../widgets/granja_campania_fields.dart';
import '../widgets/image_slot_row.dart';
import '../widgets/opcion_catalogo_dialog.dart';
import '../widgets/section_app_bar.dart';
import 'register_summary_screen.dart';

/// Fila editable de la tabla de fómites.
class _DepredadorFila {
  _DepredadorFila({
    required this.depredador,
    this.esPersonalizado = false,
  });

  final String depredador;
  final bool esPersonalizado;

  String tipo = '';
  // Sin valor por defecto: la cantidad la escribe el operador. En vacío se
  // guarda como 0, igual que los registros históricos sin conteo.
  final cantidadCtrl = TextEditingController();
  String hora = '';
  bool dentroCerco = false;

  void dispose() {
    cantidadCtrl.dispose();
  }
}

class RegisterFomitesScreen extends StatefulWidget {
  const RegisterFomitesScreen({super.key, this.enlace});

  /// Parámetros del enlace gcbioseguridad://abrir (ver DeepLinkService).
  final Map<String, String>? enlace;

  @override
  State<RegisterFomitesScreen> createState() => _RegisterFomitesScreenState();
}

class _RegisterFomitesScreenState extends State<RegisterFomitesScreen> {
  final _nombreOtroController = TextEditingController();
  final _observacionController = TextEditingController();

  /// Fecha del registro (solo lectura, siempre el día de hoy).
  final DateTime _fecha = DateTime.now();
  String _granja = '';
  String _granjaNombre = '';
  String _campania = '';
  List<String> _campaniasDeGranja = [];
  String _turno = 'Dia';
  String _referencia = '';

  /// Complemento de la referencia elegida cuando esta lo pide (ver
  /// [_referenciaPideDetalle]). Vacío para el resto.
  String _referenciaDetalle = '';
  String _proceso = '';
  final List<String?> _imagenes = [null, null, null];

  final List<_DepredadorFila> _filas = [];
  final List<String> _personalizados = [];

  String get _fechaYmd => DateFormat('yyyy-MM-dd').format(_fecha);

  /// Referencias que piden un dato aparte además de la etiqueta del catálogo.
  /// Hoy solo «A la altura del galpón»: el operador indica a qué galpón o
  /// altura corresponde. Se compara sin tildes ni mayúsculas para que el
  /// catálogo pueda escribirlo de cualquiera de las dos formas.
  static const Set<String> _referenciasConDetalle = {
    'a la altura del galpon',
  };

  static bool _referenciaPideDetalle(String descripcion) =>
      _referenciasConDetalle.contains(_sinTildes(descripcion));

  /// Minúsculas y sin tildes, para comparar etiquetas de catálogo.
  static String _sinTildes(String texto) => texto
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[áàäâã]'), 'a')
      .replaceAll(RegExp('[éèëê]'), 'e')
      .replaceAll(RegExp('[íìïî]'), 'i')
      .replaceAll(RegExp('[óòöôõ]'), 'o')
      .replaceAll(RegExp('[úùüû]'), 'u');

  /// Texto del campo Referencia: la etiqueta del catálogo y, si la opción pide
  /// complemento, el dato escrito («A la altura del galpón · Galpón 3»).
  String get _referenciaEtiqueta =>
      _referenciaDetalle.isEmpty
          ? _referencia
          : '$_referencia · $_referenciaDetalle';

  /// Firma del catálogo ya aplicado (depredadores, referencias y procesos).
  String _firmaCatalogo = '';

  @override
  void initState() {
    super.initState();
    _aplicarCatalogo(context.read<CatalogService>());
    _aplicarGranjaDeTrabajo();
    _aplicarEnlace();
  }

/// Datos del enlace de otra app (granja, dni, nombre, hora, lat/lng, ref).
/// La granja se premarca; el resto viaja en `registro.origen`.
  void _aplicarEnlace() {
    final e = widget.enlace;
    if (e == null) return;
    final id = DeepLinkService.uuidDe(e);
    final storage = context.read<StorageService>();
    if (id != null &&
        storage.getAllRecords().any((r) => EvidenciaRecordId.of(r) == id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showWarningToast(context,
              'Esta ronda ya tiene un registro. Al guardar se reemplazará.');
        }
      });
    }
    final sel = granjaSeleccionDe(
      context.read<StorageService>(),
      e['granja'] ?? '',
      fechaYmd: _fechaYmd,
    );
    if (sel != null) {
      _granja = sel.granja;
      _granjaNombre = sel.granjaNombre;
      _campania = sel.campania;
      _campaniasDeGranja = sel.campanias;
    }
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
    _campaniasDeGranja = sel.campanias;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Igual que el STD del cerco: `watch` hace que, al descargar catálogos
    // desde el drawer, la pantalla tome los valores nuevos sin reabrirse.
    _aplicarCatalogo(context.watch<CatalogService>());
  }

  /// Sincroniza la pantalla con el catálogo: agrega los depredadores nuevos,
  /// quita los retirados que no tienen datos escritos y limpia la referencia
  /// o el proceso elegidos si el catálogo ya no los ofrece.
  void _aplicarCatalogo(CatalogService catalog) {
    final depredadores = catalog.depredadores;
    final referencias = catalog.referencias.map((e) => e['descripcion']).toSet();
    final procesos = catalog.procesosFomites.map((e) => e['descripcion']).toSet();
    final firma = [
      depredadores.join('|'),
      referencias.join('|'),
      procesos.join('|'),
    ].join('~');
    if (firma == _firmaCatalogo) return;
    _firmaCatalogo = firma;

    final nombres = depredadores.map((d) => d.toLowerCase()).toSet();
    _filas.removeWhere((f) {
      final retirar = !f.esPersonalizado &&
          !nombres.contains(f.depredador.toLowerCase()) &&
          f.tipo.isEmpty &&
          f.hora.isEmpty &&
          f.cantidadCtrl.text.trim().isEmpty &&
          !f.dentroCerco;
      if (retirar) f.dispose();
      return retirar;
    });
    final existentes = _filas.map((f) => f.depredador.toLowerCase()).toSet();
    var pos = 0;
    for (final d in depredadores) {
      if (!existentes.contains(d.toLowerCase())) {
        _filas.insert(pos.clamp(0, _filas.length), _DepredadorFila(depredador: d));
      }
      pos++;
    }
    if (_referencia.isNotEmpty && !referencias.contains(_referencia)) {
      _referencia = '';
      _referenciaDetalle = '';
    }
    if (_proceso.isNotEmpty && !procesos.contains(_proceso)) {
      _proceso = '';
    }
  }

  @override
  void dispose() {
    for (final f in _filas) {
      f.dispose();
    }
    _nombreOtroController.dispose();
    _observacionController.dispose();
    super.dispose();
  }

  // La fecha es de solo lectura: el registro es del día en que se hace.

  /// Guarda la granja y/o campaña elegidas en [GranjaCampaniaFields].
  void _onGranjaCampania(GranjaCampaniaSeleccion sel) {
    setState(() {
      _granja = sel.granja;
      _granjaNombre = sel.granjaNombre;
      _campania = sel.campania;
      _campaniasDeGranja = sel.campanias;
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

  Future<void> _pickReferencia() async {
    final opciones = context.read<CatalogService>().referencias;
    if (!bioHayCatalogo(context, opciones)) return;
    // «Otros» se escribe a mano, y las referencias de [_referenciasConDetalle]
    // piden además el dato que las completa («A la altura del galpón»).
    final sel = await showOpcionCatalogoDialog(
      context: context,
      title: 'Seleccionar referencia',
      opciones: opciones,
      actual: OpcionCatalogo(valor: _referencia, detalle: _referenciaDetalle),
      icon: Icons.place_rounded,
      otroLabel: 'Referencia',
      otroHint: 'Escriba la referencia',
      pideDetalle: _referenciaPideDetalle,
      detalleLabel: 'A la altura de',
      detalleHint: 'Ej. Galpón 3',
    );
    if (sel == null) return;
    setState(() {
      _referencia = sel.valor;
      _referenciaDetalle = sel.detalle;
    });
  }

  Future<void> _pickProceso() async {
    final opciones = context.read<CatalogService>().procesosFomites;
    if (!bioHayCatalogo(context, opciones)) return;
    final sel = await showBioOptionsSheet<Map<String, String>>(
      context: context,
      title: 'Seleccionar proceso',
      options: opciones,
      labelOf: (o) => o['descripcion'] ?? '',
      selected: opciones.firstWhere(
        (o) => o['descripcion'] == _proceso,
        orElse: () => const {'codigo': '', 'descripcion': ''},
      ),
    );
    if (sel != null) setState(() => _proceso = sel['descripcion'] ?? '');
  }

  Future<void> _agregarOtro() async {
    _nombreOtroController.clear();
    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Agregar fómite'),
        content: TextField(
          controller: _nombreOtroController,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 20,
          decoration: const InputDecoration(
            labelText: 'Nombre del fómite',
            hintText: 'Ej. Vaca',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final v = _nombreOtroController.text.trim();
              Navigator.pop(ctx, v.isEmpty ? null : v);
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
    if (nombre == null || nombre.isEmpty) return;
    if (_personalizados.any(
          (d) => d.toLowerCase() == nombre.toLowerCase(),
        ) ||
        _filas.any((f) => f.depredador.toLowerCase() == nombre.toLowerCase())) {
      if (mounted) {
        showWarningToast(context, 'Ese fómite ya está en la tabla.');
      }
      return;
    }
    setState(() {
      _personalizados.add(nombre);
      _filas.add(_DepredadorFila(depredador: nombre, esPersonalizado: true));
    });
  }

  Future<void> _pickTipo(_DepredadorFila fila) async {
    final opciones = context.read<CatalogService>().tiposFomites;
    if (!bioHayCatalogo(context, opciones)) return;
    final actual = opciones.firstWhere(
      (o) => o['descripcion'] == fila.tipo,
      orElse: () => const {'codigo': '', 'descripcion': ''},
    );
    final sel = await showBioOptionsSheet<Map<String, String>>(
      context: context,
      title: 'Tipo de evidencia · ${fila.depredador}',
      options: opciones,
      labelOf: (o) => o['descripcion'] ?? '',
      selected: actual['descripcion']!.isEmpty ? null : actual,
    );
    if (sel != null) {
      setState(() => fila.tipo = sel['descripcion'] ?? '');
    }
  }

  Future<void> _pickHora(_DepredadorFila fila) async {
    final elegida = await showBioHoraDialog(context, valorActual: fila.hora);
    if (elegida == null) return;
    setState(() => fila.hora = elegida);
  }

  Map<String, dynamic> _buildRecord(StorageService storage) {
    final filas = <Map<String, dynamic>>[];
    for (final f in _filas) {
      if (f.tipo.trim().isEmpty) continue;
      filas.add({
        'depredador': f.depredador,
        'tipo': f.tipo,
        'cantidad': int.tryParse(f.cantidadCtrl.text.trim()) ?? 0,
        'hora': f.hora,
        'dentrocerco': f.dentroCerco ? 'Si' : 'No',
      });
    }

    final imagenes = _imagenes
        .whereType<String>()
        .where((p) => p.trim().isNotEmpty)
        .map((p) => {'path': p})
        .toList();

    return {
      // uuid del enlace (otra app) o uno nuevo.
      'id': DeepLinkService.uuidDe(widget.enlace) ?? const Uuid().v4(),
      'reporte': 'fomites',
      'fecha': _fechaYmd,
      'granja': _granja,
      'granjaNombre': _granjaNombre,
      'campania': _campania,
      'turno': _turno,
      'usuario': storage.getUserCodeSync() ?? '',
      'nombre_usuario': storage.getUserName() ?? '',
      'registro': {
        // La referencia viaja compuesta («A la altura del galpón · Galpón 3»)
        // para que el reporte web muestre el detalle sin migrar la columna.
        'referencia': _referenciaEtiqueta,
        'proceso': _proceso,
        'observacion': _observacionController.text.trim(),
        'filas': filas,
        if (widget.enlace != null) 'origen': widget.enlace,
      },
      'imagenes': imagenes,
      'synced': false,
      'guardado_backend': false,
      'created_at': DateTime.now().toIso8601String(),
    };
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
    if (_referencia.isEmpty || _proceso.isEmpty) {
      showErrorToast(context, 'Seleccione la referencia y el proceso.');
      return;
    }
    final conTipo = _filas.where((f) => f.tipo.trim().isNotEmpty).toList();
    if (conTipo.isEmpty) {
      showErrorToast(
        context,
        'Indique el tipo en al menos un fómite avistado.',
      );
      return;
    }
    for (final f in conTipo) {
      if (f.depredador.trim().isEmpty) {
        showErrorToast(context, 'Hay una fila sin fómite.');
        return;
      }
    }

    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 80));

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

    final record = _buildRecord(storage);

    var enviado = false;
    final saved = await RegisterSummarySheet.show(
      context,
      record: record,
      onConfirm: () async {
        final ok = await BioRecordSaver.save(context, record);
        enviado = ok;
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

    // Abierta por enlace (rondas): tras guardar vuelve a esa app con el
    // resultado. Si no se puede abrir, se queda aquí como siempre.
    final enlace = widget.enlace;
    if (saved && mounted && enlace != null) {
      final volvio = await DeepLinkService.volverAlOrigen(
        enlace,
        modulo: 'fomites',
        uuid: record['id']?.toString() ?? '',
        enviado: enviado,
        fecha: record['fecha']?.toString() ?? '',
      );
      if (volvio) return;
    }
    if (saved && mounted) {
      setState(() {
        for (final f in _filas) {
          f.tipo = '';
          f.hora = '';
          f.dentroCerco = false;
          f.cantidadCtrl.clear();
        }
        _observacionController.clear();
        _imagenes
          ..clear()
          ..addAll([null, null, null]);
      });
    }
  }

  @override
  Widget build(BuildContext context) => DeepLinkService.conRetorno(
        widget.enlace,
        modulo: 'fomites',
        child: _contenido(context),
      );

  Widget _contenido(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: SectionAppBar(
        title: AppStrings.menuFomites,
        sectionIcon: Icons.pets,
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
                  campanias: _campaniasDeGranja,
                  onSeleccion: _onGranjaCampania,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: EvidenciaSelectField(
                        label: 'Referencia',
                        value: _referenciaEtiqueta,
                        placeholder: 'Seleccione',
                        icon: Icons.place_rounded,
                        onTap: _pickReferencia,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: EvidenciaSelectField(
                        label: 'Proceso',
                        value: _proceso,
                        placeholder: 'Seleccione',
                        icon: Icons.settings_rounded,
                        onTap: _pickProceso,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            BioTable(
              caption: 'Registro de fómites',
              rowHeight: 56,
              columns: const [
                // Fómite, Tipo y Cantidad iban anchas para lo que muestran
                // (un nombre, una palabra y hasta cuatro dígitos), y empujaban
                // «Hora» y «D. del cerco» fuera de la pantalla del teléfono.
                BioColumn('Fómite', width: 96, align: TextAlign.left),
                BioColumn('Tipo', width: 104),
                BioColumn('Cant.', width: 64),
                BioColumn('Hora', width: 76),
                BioColumn('¿D. del cerco?', width: 106),
              ],
              rowCount: _filas.length,
              rowBuilder: (context, index) {
                final fila = _filas[index];
                return [
                  Row(
                    children: [
                      Expanded(
                        child: BioText(
                          fila.depredador,
                          align: TextAlign.left,
                          fontSize: 13,
                          bold: true,
                        ),
                      ),
                      if (fila.esPersonalizado)
                        InkWell(
                          onTap: () => setState(() {
                            fila.dispose();
                            _filas.removeAt(index);
                            _personalizados.remove(fila.depredador);
                          }),
                          child: const Icon(
                            Icons.remove_circle_outline,
                            size: 15,
                            color: AppColors.errorDark,
                          ),
                        ),
                    ],
                  ),
                  InkWell(
                    onTap: () => _pickTipo(fila),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      width: double.infinity,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              fila.tipo.isEmpty ? 'Seleccione' : fila.tipo,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: fila.tipo.isEmpty
                                    ? FontWeight.w400
                                    : FontWeight.w700,
                                color: fila.tipo.isEmpty
                                    ? context.textThemeMuted
                                    : context.textThemePrimary,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.expand_more,
                            size: 14,
                            color: AppColors.iconAccent,
                          ),
                        ],
                      ),
                    ),
                  ),
                  BioTextField(
                    controller: fila.cantidadCtrl,
                    keyboardType: TextInputType.number,
                    hint: '0',
                    textAlign: TextAlign.center,
                    maxLength: 4,
                  ),
                  InkWell(
                    onTap: () => _pickHora(fila),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      alignment: Alignment.center,
                      child: Text(
                        fila.hora.isEmpty ? '--:--' : fila.hora,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: fila.hora.isEmpty
                              ? FontWeight.w400
                              : FontWeight.w800,
                          color: fila.hora.isEmpty
                              ? context.textThemeMuted
                              : context.horaTexto,
                        ),
                      ),
                    ),
                  ),
                  BioSwitchFallo(
                    value: fila.dentroCerco,
                    onChanged: (v) => setState(() => fila.dentroCerco = v),
                  ),
                ];
              },
            ),
            const SizedBox(height: 6),
            BioAddRowButton(
              label: 'Agregar otro fómite',
              onPressed: _agregarOtro,
            ),
            const SizedBox(height: 12),
            BioTextArea(
              label: 'Observación general',
              controller: _observacionController,
              hint: 'Comentarios adicionales del recorrido',
              icon: Icons.edit_rounded,
              maxLength: 100,
              minLines: 2,
              maxLines: 3,
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
