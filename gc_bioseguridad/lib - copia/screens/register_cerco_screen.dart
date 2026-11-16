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
import '../widgets/bio_table.dart';
import '../widgets/evidencia_select_field.dart';
import '../widgets/granja_campania_fields.dart';
import '../widgets/image_slot_row.dart';
import '../widgets/section_app_bar.dart';
import 'register_summary_screen.dart';

/// Estado de una métrica por línea (si incumple/falló + observación).
/// `fallo` guarda siempre el mismo significado: true = no está correcto.
/// La pregunta de la tabla se muestra invertida (verde = está bien), pero el
/// dato guardado y subido es el mismo en los tres bloques.
class _LineaEstado {
  bool fallo = false;
}

/// Hora del día en `HH:mm`, que es como la guardan la base y el backend.
String _horaDelDia(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}';

class _MetricaFila {
  _MetricaFila({
    required this.nombre,
    required this.std,
    required this.permiteObs,
    required this.ok,
    required this.falla,
  });

  final String nombre;

  /// STD del catálogo. No es `final` porque al descargar catálogos desde el
  /// drawer puede corregirse en el servidor: el tablero abierto se actualiza
  /// sin perder lo que el usuario ya escribió.
  String std;

  /// Si la fila muestra el campo de observación. Lo indica el catálogo (son las
  /// métricas de valor medido: voltaje y nivel de batería).
  final bool permiteObs;

  /// Las dos respuestas de la fila, como se contestan en el formato físico:
  /// «CT» y «FALLA» en casi todo, «No» y «SI» en las tres alertas del tablero.
  /// Las manda el catálogo; ver [CercoMetrica.ok].
  final String ok;
  final String falla;

  final linea1 = _LineaEstado();
  final linea2 = _LineaEstado();

  final obs1 = TextEditingController();
  final obs2 = TextEditingController();

  void reiniciar() {
    linea1.fallo = false;
    linea2.fallo = false;
    obs1.clear();
    obs2.clear();
  }

  void dispose() {
    obs1.dispose();
    obs2.dispose();
  }
}

/// Bloque del reporte de cerco: su título (el `bloque` del catálogo) y sus
/// filas. La pantalla se arma con los bloques que envía el servidor, no con una
/// lista fija: si agregan o mueven una métrica, se ve sin publicar una app
/// nueva.
class _BloqueCerco {
  _BloqueCerco(this.titulo);

  final String titulo;
  List<_MetricaFila> filas = [];

  /// Firma de las métricas ya aplicadas (nombre + STD + observación). Evita
  /// reconstruir nada cuando el catálogo avisa pero no cambió.
  String firma = '';

  void dispose() {
    for (final f in filas) {
      f.dispose();
    }
  }
}

class RegisterCercoScreen extends StatefulWidget {
  const RegisterCercoScreen({super.key});

  @override
  State<RegisterCercoScreen> createState() => _RegisterCercoScreenState();
}

class _RegisterCercoScreenState extends State<RegisterCercoScreen> {
  final _responsableController = TextEditingController();
  final _observacionesGeneralesController = TextEditingController();

  DateTime _fecha = DateTime.now();
  String _granja = '';
  String _granjaNombre = '';
  String _campania = '';
  List<String> _campaniasDeGranja = [];
  String _turno = 'Dia';

  /// Momento en que arranca la inspección. Antes las dos horas eran 06:00 y
  /// 06:30 fijas, que es la hora a la que se acostumbra inspeccionar, pero en
  /// la noche había que corregirlas a mano. Ahora arrancan en la hora del
  /// equipo y el formato físico se completa tocando el campo.
  final DateTime _inicioInspeccion = DateTime.now();
  late String _horaInicio = _horaDelDia(_inicioInspeccion);
  late String _horaFinal =
      _horaDelDia(_inicioInspeccion.add(const Duration(minutes: 30)));
  final List<String?> _imagenes = [null, null, null];

  /// Bloques del reporte tal como los envía el catálogo (título + filas). Se
  /// reconstruyen al descargar y en el orden que manda el servidor.
  List<_BloqueCerco> _bloques = [];

  String get _fechaYmd => DateFormat('yyyy-MM-dd').format(_fecha);

  List<_MetricaFila> get _filasTodas => [
    for (final b in _bloques) ...b.filas,
  ];

  @override
  void initState() {
    super.initState();
    _aplicarMetricas(context.read<CatalogService>().metricasCerco);
    // El responsable arranca con el usuario que tiene la sesión abierta; se
    // puede cambiar si la inspección la hizo otra persona.
    _responsableController.text = context.read<StorageService>().getUserName() ?? '';
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
    _campaniasDeGranja = sel.campanias;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `watch`: al descargar catálogos desde el drawer, CatalogService avisa y
    // este método vuelve a entrar con el STD ya actualizado. Sin esto el
    // tablero seguiría mostrando lo que traía el equipo al abrir la pantalla.
    _aplicarMetricas(context.watch<CatalogService>().metricasCerco);
  }

  /// Filas de un bloque a partir de sus métricas del catálogo.
  List<_MetricaFila> _filasDeseadas(List<CercoMetrica> metricas) => [
    for (final m in metricas)
      _MetricaFila(
        nombre: m.nombre,
        std: m.std,
        permiteObs: m.permiteObs,
        ok: m.ok,
        falla: m.falla,
      ),
  ];

  /// Aplica a un bloque las métricas del catálogo.
  /// Si solo cambió el STD de métricas que ya estaban, se actualiza en sitio
  /// para no borrar lo que el usuario haya escrito. Si cambió la lista (otra
  /// cantidad, otro orden, qué filas piden observación o con qué se contestan),
  /// se reconstruye.
  void _aplicarBloque(_BloqueCerco bloque, List<CercoMetrica> metricas) {
    final firma = metricas
        .map((m) => '${m.nombre}|${m.std}|${m.permiteObs}|${m.ok}|${m.falla}')
        .join('~');
    if (firma == bloque.firma) return;

    final deseadas = _filasDeseadas(metricas);
    final mismasFilas = deseadas.length == bloque.filas.length &&
        List<int>.generate(deseadas.length, (i) => i).every(
              (i) =>
                  deseadas[i].nombre == bloque.filas[i].nombre &&
                  deseadas[i].permiteObs == bloque.filas[i].permiteObs &&
                  deseadas[i].ok == bloque.filas[i].ok &&
                  deseadas[i].falla == bloque.filas[i].falla,
            );
    if (mismasFilas) {
      // Se conservan las filas actuales (con lo ya escrito) y solo se copia el
      // STD nuevo; las temporales se descartan liberando sus controladores.
      for (var i = 0; i < deseadas.length; i++) {
        bloque.filas[i].std = deseadas[i].std;
      }
      for (final f in deseadas) {
        f.dispose();
      }
    } else {
      for (final f in bloque.filas) {
        f.dispose();
      }
      bloque.filas = deseadas;
    }
    bloque.firma = firma;
  }

  /// Aplica al reporte las métricas del catálogo: agrupa por `bloque` y arma
  /// una tabla por bloque, en el orden en que las envía el servidor.
  void _aplicarMetricas(List<CercoMetrica> metricas) {
    if (metricas.isEmpty) return;

    final orden = <String>[];
    final porBloque = <String, List<CercoMetrica>>{};
    for (final m in metricas) {
      final titulo = m.bloque.trim();
      if (titulo.isEmpty) continue;
      porBloque.putIfAbsent(titulo, () {
        orden.add(titulo);
        return <CercoMetrica>[];
      }).add(m);
    }

    // Se reutilizan los bloques que ya estaban (conservando lo escrito) y se
    // descartan los que el servidor ya no envía.
    final actuales = {for (final b in _bloques) b.titulo: b};
    final nuevos = <_BloqueCerco>[];
    for (final titulo in orden) {
      final bloque = actuales.remove(titulo) ?? _BloqueCerco(titulo);
      _aplicarBloque(bloque, porBloque[titulo]!);
      nuevos.add(bloque);
    }
    for (final viejo in actuales.values) {
      viejo.dispose();
    }
    _bloques = nuevos;
  }

  @override
  void dispose() {
    for (final b in _bloques) {
      b.dispose();
    }
    _responsableController.dispose();
    _observacionesGeneralesController.dispose();
    super.dispose();
  }

  // La fecha es de solo lectura: el registro es del día en que se hace, y
  // retroceder a otro día dejaba el tablero del cerco con fecha de otro turno.

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

  Map<String, dynamic> _filaCercoJson(_MetricaFila f) => {
        'componente': f.nombre,
        'std': f.std,
        'linea1': {
          'fallo': f.linea1.fallo ? 'Si' : 'No',
          'obs': f.obs1.text.trim(),
        },
        'linea2': {
          'fallo': f.linea2.fallo ? 'Si' : 'No',
          'obs': f.obs2.text.trim(),
        },
      };

  Map<String, dynamic> _buildRecord(StorageService storage) {
    final filas = <Map<String, dynamic>>[];
    final bloques = <Map<String, dynamic>>[];
    for (final bloque in _bloques) {
      final filasBloque = <Map<String, dynamic>>[
        for (final f in bloque.filas) _filaCercoJson(f),
      ];
      bloques.add({'titulo': bloque.titulo, 'filas': filasBloque});
      filas.addAll(filasBloque);
    }

    final imagenes = _imagenes
        .whereType<String>()
        .where((p) => p.trim().isNotEmpty)
        .map((p) => {'path': p})
        .toList();

    return {
      'id': const Uuid().v4(),
      'reporte': 'cerco',
      'fecha': _fechaYmd,
      'granja': _granja,
      'granjaNombre': _granjaNombre,
      'campania': _campania,
      'turno': _turno,
      'usuario': storage.getUserCodeSync() ?? '',
      'nombre_usuario': storage.getUserName() ?? '',
      'registro': {
        'horainicio': _horaInicio,
        'horafinal': _horaFinal,
        'evaluador': _responsableController.text.trim(),
        'observacion': _observacionesGeneralesController.text.trim(),
        'filas': filas,
        'bloques': bloques,
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
    if (_filasTodas.isEmpty) {
      showErrorToast(context, 'No hay métricas configuradas para el tablero.');
      return;
    }
    if (_responsableController.text.trim().isEmpty) {
      showErrorToast(context, 'Ingrese el responsable de inspección.');
      return;
    }
    for (final f in _filasTodas) {
      // Solo voltaje y nivel de batería piden observación; el resto de los
      // bloques se responde únicamente con el switch.
      if (!f.permiteObs) continue;
      if (f.linea1.fallo && f.obs1.text.trim().isEmpty) {
        showErrorToast(
          context,
          'Ingrese la observación de «${f.nombre}» (Línea 1).',
        );
        return;
      }
      if (f.linea2.fallo && f.obs2.text.trim().isEmpty) {
        showErrorToast(
          context,
          'Ingrese la observación de «${f.nombre}» (Línea 2).',
        );
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
        for (final f in _filasTodas) {
          f.reiniciar();
        }
        _imagenes
          ..clear()
          ..addAll([null, null, null]);
        _observacionesGeneralesController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: SectionAppBar(
        title: AppStrings.menuCerco,
        sectionIcon: Icons.bolt_rounded,
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
                      child: BioTimeField(
                        label: 'Hora inicio',
                        value: _horaInicio,
                        onPicked: (v) => setState(() => _horaInicio = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: BioTimeField(
                        label: 'Hora fin',
                        value: _horaFinal,
                        onPicked: (v) => setState(() => _horaFinal = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                BioTextArea(
                  label: 'Responsable de inspección',
                  controller: _responsableController,
                  hint: 'Nombre de quien inspecciona',
                  icon: Icons.badge_rounded,
                  maxLength: 30,
                  minLines: 1,
                  maxLines: 1,
                  textCapitalization: TextCapitalization.words,
                ),
              ],
            ),
            const SizedBox(height: 20),
            for (final bloque in _bloques) ...[
              _buildBloque(titulo: bloque.titulo, filas: bloque.filas),
              const SizedBox(height: 20),
            ],
            BioFormSection(
              title: 'OBSERVACIONES GENERALES',
              icon: Icons.edit_note_rounded,
              children: [
                BioTextArea(
                  label: 'Observaciones generales',
                  controller: _observacionesGeneralesController,
                  hint: 'Comentarios adicionales de la inspección',
                  icon: Icons.edit_rounded,
                  maxLength: 200,
                  minLines: 2,
                  maxLines: 4,
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

  /// Bloque del reporte: título y filas.
  /// Todos los bloques usan el mismo interruptor (verde = está bien), que
  /// funciona igual en las filas que tienen STD y en las que no. Lo que cambia
  /// es con qué se contesta cada fila: en el formato físico casi todo se
  /// contesta «CT» o «FALLA», y las tres alertas del tablero «No» o «SI». Por
  /// eso el par de respuestas lo trae cada fila y no el encabezado.
  Widget _buildBloque({
    required String titulo,
    required List<_MetricaFila> filas,
  }) {
    // El encabezado dice «Estado» y no el par de respuestas («CT / FALLA»):
    // con las dos líneas y tres bloques, repetir el par en cada columna era
    // ruido, y en el tablero —donde se mezcla con «No / SI»— ya no coincidía.
    // El par concreto se lee en la propia celda, que es donde se contesta.
    // Tres columnas y no cuatro: el STD va dentro de la primera, debajo del
    // nombre, como está escrito en el formato físico. Con la columna aparte la
    // tabla no entraba en la pantalla y L2 quedaba fuera de la vista.
    // La primera columna se queda el ancho sobrante, para que L1 y L2 (y por
    // tanto los interruptores) queden siempre en la misma vertical.
    return BioTable(
      caption: titulo,
      rowHeight: 44,
      columns: [
        // 118 + 100 + 100 = 318: es el ancho al que las tres columnas entran en
        // un teléfono de 360 con el margen del formulario, así que L2 deja de
        // quedar fuera de la pantalla.
        const BioColumn(
          'Componente',
          width: 118,
          align: TextAlign.left,
          flex: 1,
        ),
        const BioColumn('L1\nEstado', width: 100, align: TextAlign.left),
        const BioColumn('L2\nEstado', width: 100, align: TextAlign.left),
      ],
      rowCount: filas.length,
      rowBuilder: (context, index) {
        final fila = filas[index];
        return [
          _buildComponente(fila),
          _buildCelda(fila: fila, linea1: true),
          _buildCelda(fila: fila, linea1: false),
        ];
      },
    );
  }

  /// Primera columna: el componente y, debajo, su STD.
  /// Las dos líneas juntas porque así están en la hoja: primero qué se revisa y
  /// después contra qué. Las métricas que no tienen STD (las alertas del
  /// tablero) muestran solo el nombre.
  Widget _buildComponente(_MetricaFila fila) {
    final std = fila.std.trim();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BioText(fila.nombre, align: TextAlign.left, fontSize: 12.5, bold: true),
        if (std.isNotEmpty) ...[
          const SizedBox(height: 2),
          // El STD va en negrita: es contra lo que se compara lo medido y en la
          // celda tiene que leerse sin buscarlo.
          BioText(
            'STD: $std',
            align: TextAlign.left,
            fontSize: 11,
            bold: true,
            color: context.textThemeSecondary,
          ),
        ],
      ],
    );
  }

  Widget _buildCelda({required _MetricaFila fila, required bool linea1}) {
    final linea = linea1 ? fila.linea1 : fila.linea2;

    // Verde = está bien. El dato guardado sigue siendo la falla, así que se
    // invierte al leer y al escribir. La etiqueta es la del formato físico:
    // «CT»/«FALLA», o «No»/«SI» en las alertas del tablero.
    // Solo voltaje y nivel de batería llevan además el campo de observación
    // (son valores medidos); el resto de filas se responde solo con el switch.
    // En esas dos la observación va debajo del interruptor (`apilado`), que es
    // la única forma de que entre en la celda sin correr el switch.
    if (fila.permiteObs) {
      return BioSwitchObs(
        value: linea.fallo,
        onChanged: (v) => setState(() => linea.fallo = v),
        controller: linea1 ? fila.obs1 : fila.obs2,
        obsSiempreActiva: true,
        verdeAlEncender: true,
        onLabel: fila.ok,
        offLabel: fila.falla,
        apilado: true,
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: BioSwitchCumple(
        value: !linea.fallo,
        onChanged: (v) => setState(() => linea.fallo = !v),
        onLabel: fila.ok,
        offLabel: fila.falla,
      ),
    );
  }
}
