import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../services/api_service.dart';
import '../services/app_version_service.dart';
import '../services/catalog_service.dart';
import '../services/estatus_sanitario_service.dart';
import '../services/ingreso_presencia_service.dart';
import '../services/plan_visitas_service.dart';
import '../services/proveedor_historial_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/dni_utils.dart';
import '../utils/galpones_resolver.dart';
import '../utils/record_saver.dart';
import '../utils/theme_colors.dart';
import '../utils/toast_helper.dart';
import '../widgets/app_drawer.dart';
import '../widgets/bio_form_fields.dart';
import '../widgets/bio_table.dart';
import '../widgets/evidencia_select_field.dart';
import '../widgets/granja_campania_fields.dart';
import '../widgets/granja_campania_picker.dart';
import '../widgets/image_slot_row.dart';
import '../widgets/proceso_dialog.dart';
import '../widgets/proveedor_dialog.dart';
import '../widgets/ingreso_regreso_tab.dart';
import '../widgets/section_app_bar.dart';
import '../widgets/situacion_dialog.dart';
import 'dni_scanner_screen.dart';
import 'register_summary_screen.dart';

/// Control de ingreso: cuántas personas entran a la granja, en qué vehículo,
/// de qué proveedor y con qué proceso vienen. Los DNIs son opcionales porque en
/// campañas entran grupos grandes y no siempre se pide el documento a todos.
class RegisterControlIngresoScreen extends StatefulWidget {
  const RegisterControlIngresoScreen({super.key});

  @override
  State<RegisterControlIngresoScreen> createState() =>
      _RegisterControlIngresoScreenState();
}

/// Estado de la consulta del nombre para un DNI.
///
/// No hay estado de error a propósito: si la consulta en línea falla y el
/// documento tampoco está en el catálogo local, el nombre queda pendiente y el
/// operador puede escribirlo a mano. Un aviso rojo solo molesta al guardia que
/// está registrando.
enum _DniEstado { vacio, consultando, ok, sinNombre }

/// Resultado informativo de la «Planificación de visitas» del portal web para
/// la placa o para un DNI.
///
/// Solo informa: el registro se guarda igual esté o no planificado. Cuando no
/// se pudo saber (sin datos descargados para esa fecha y sin red, o la
/// planificación aún no instalada en el servidor) no hay objeto y la pantalla
/// no muestra nada (estado neutro).
class _PlanInfo {
  const _PlanInfo({required this.planificado, this.visita, this.otraGranja});

  final bool planificado;

  /// Visita que coincide en esta granja (con sus personas).
  final PlanVisita? visita;

  /// Si no está planificado aquí pero sí en otra granja ese mismo día.
  final PlanVisita? otraGranja;

  /// Mensaje completo para el aviso al tocar el indicador.
  String get mensaje {
    if (planificado) {
      final d = visita?.detalle ?? '';
      return d.isEmpty ? 'Visita planificada.' : 'Visita planificada: $d';
    }
    final otra = otraGranja?.detalle ?? '';
    return otra.isEmpty
        ? 'No figura en la planificación de visitas de esta granja para la fecha.'
        : 'No planificado en esta granja; figura planificado en $otra.';
  }

  /// Desde lo descargado en el equipo.
  factory _PlanInfo.deLocal(PlanCoincidencia c) => _PlanInfo(
    planificado: c.planificado,
    visita: c.visita,
    otraGranja: c.otraGranja,
  );

  /// Lee un elemento de la respuesta en línea (`data.placa` o
  /// `data.dnis[dni]`). Devuelve `null` (neutro) si no viene o no se entiende.
  static _PlanInfo? desde(dynamic item) {
    if (item is! Map || item['planificado'] is! bool) return null;
    final visita = item['visita'];
    final otra = item['otraGranja'];
    return _PlanInfo(
      planificado: item['planificado'] == true,
      visita: visita is Map ? PlanVisita.fromJson(visita) : null,
      otraGranja: otra is Map ? PlanVisita.fromJson(otra) : null,
    );
  }
}

/// Persona de la visita planificada de la placa.
///
/// Nace sin marcar: el vigilante confirma la lista real al escanear o teclear
/// cada DNI —ahí la casilla se marca sola— o tocando la casilla a mano. Las
/// marcadas viajan como DNIs del registro; las que nadie confirma quedan fuera
/// y así la planificación se contrasta contra quien realmente llegó.
///
/// Marcar a mano no es solo tildar: la persona ingresa, así que se le pone su
/// renglón en la tabla de los DNIs que ingresan (con el DNI y el nombre que
/// programó la web). Desmarcarla borra ese renglón. Las dos listas siempre
/// dicen lo mismo y ninguna necesita explicación escrita.
class _PersonaPlan {
  _PersonaPlan({required this.dni, required this.nombre});

  final String dni;
  final String nombre;

  /// Confirmada a mano por el vigilante.
  bool marcado = false;

  /// Fila de la tabla cuyo DNI confirmó a esta persona al escanearlo o
  /// escribirlo completo. `null` si todavía nadie la confirmó.
  _DniFila? confirmadaPor;

  /// Ya viajó en un ingreso guardado de esta visita (ingreso parcial).
  bool yaRegistrado = false;

  /// Ingresa en este registro: confirmada ahora y aún no registrada antes.
  bool get efectivo =>
      !yaRegistrado && (marcado || confirmadaPor != null);

  /// Casilla marcada (incluye las ya registradas, solo lectura).
  bool get casillaMarcada =>
      yaRegistrado || marcado || confirmadaPor != null;
}

/// Fila editable de la tabla de DNIs (un renglón por documento).
///
/// Guarda el nombre que devuelve la consulta del documento, que puede llegar
/// por escaneo o por haber escrito los 8 dígitos a mano. Si la consulta no lo
/// resuelve (sin conexión y el documento tampoco está en el catálogo local), el
/// operador puede escribirlo en [nombreCtrl].
class _DniFila {
  final ctrl = TextEditingController();

  /// Nombre escrito a mano por el operador. Solo se usa cuando la consulta no
  /// lo resolvió; en cuanto hay nombre resuelto, ese manda.
  final nombreCtrl = TextEditingController();

  String nombre = '';
  _DniEstado estado = _DniEstado.vacio;

  /// Último documento consultado con éxito, para no repetir la llamada.
  String consultado = '';

  /// Resultado informativo de la planificación (`null` = neutro).
  _PlanInfo? plan;

  /// Estatus sanitario de la persona: `null` = neutro (sin red o sin novedad).
  /// Solo se dibuja cuando [EstatusDni.enRiesgo] es `true`.
  EstatusDni? estatus;

  Timer? debounce;

  String get dni => ctrl.text.trim();

  /// Nombre que viaja en el registro: el que resolvió la consulta o, si no
  /// hubo, el que escribió el operador.
  String get nombreEfectivo =>
      nombreDniEfectivo(resuelto: nombre, manual: nombreCtrl.text);

  bool get completo => dni.length == 8;

  void dispose() {
    debounce?.cancel();
    ctrl.dispose();
    nombreCtrl.dispose();
  }
}

/// Fila editable en «Vehículos que ingresan»: placa a mano o bajada al marcar
/// la planificación. Cada una consulta si está planificada y su situación
/// especial, igual que un DNI en la tabla de personas.
class _VehiculoFila {
  final ctrl = TextEditingController();

  /// Placa que traía la planificación cuando esta fila se cargó de una visita.
  String planificada = '';

  /// ¿La planificación dice que este vehículo ingresa a la granja? `null`
  /// cuando la placa no está programada (o no se sabe).
  bool? ingresaPlan;

  /// Resultado informativo de la planificación (`null` = neutro).
  _PlanInfo? plan;

  /// Estatus sanitario del vehículo: `null` = neutro o sin novedad.
  EstatusDni? estatus;

  Timer? debounce;

  String get placa => ctrl.text.trim();

  String get placaNorm => PlanDescarga.normPlaca(ctrl.text);

  bool get escrita => placaNorm.length >= _RegisterControlIngresoScreenState._minPlaca;

  /// ¿Esta fila es la que representa a la placa [otra] (normalizada)?
  bool esLaPlaca(String otra) =>
      placaNorm.isNotEmpty && placaNorm == PlanDescarga.normPlaca(otra);

  void dispose() {
    debounce?.cancel();
    ctrl.dispose();
  }
}

/// Vehículo de la visita planificada de la web.
///
/// La web programa los vehículos con un interruptor «ingresa / no ingresa a la
/// granja»; los dos llegan acá y el vigilante confirma cuáles entraron de
/// verdad. Marcar un vehículo es «ingresó»: su placa baja al bloque de
/// vehículos del formulario, donde se consulta su planificación y su historial
/// de situación especial —igual que con las personas planificadas—. Los que la
/// web marcó «no ingresa» llegan destildados, pero se pueden tildar si igual
/// entraron: el switch es de la planificación, no del hecho.
class _VehiculoPlan {
  _VehiculoPlan({required this.placa, required this.ingresa});

  /// Placa como la escribió la web (se muestra tal cual).
  final String placa;

  /// El switch de la web: `false` = «no ingresa a la granja».
  final bool ingresa;

  /// Confirmado a mano por el vigilante.
  bool marcado = false;

  /// Renglón en «Vehículos que ingresan» que trae esta placa (`null` si no está).
  _VehiculoFila? fila;

  /// Situación especial de la placa (consultada por `_placasEscritas`).
  EstatusDni? estatus;

  /// Clave para conservar lo confirmado entre descargas de la planificación.
  String get clave => PlanDescarga.normPlaca(placa);

  /// La placa ya está en «Vehículos que ingresan» (marcada o escrita a mano).
  bool get efectivo => marcado || fila != null;
}

class _RegisterControlIngresoScreenState
    extends State<RegisterControlIngresoScreen> {
  static const int _largoDni = 8;

  /// Separación vertical entre campos de un mismo bloque del formulario.
  static const double _sepCampo = 6;

  /// Separación vertical entre bloques del formulario.
  static const double _sepBloque = 10;

  /// Separación horizontal entre dos campos que comparten fila.
  static const double _sepFila = 10;

  final _personasController = TextEditingController();
  final _observacionController = TextEditingController();

  /// Fecha del registro (solo lectura, siempre el día de hoy).
  final DateTime _fecha = DateTime.now();
  String _granja = '';
  String _granjaNombre = '';
  String _campania = '';
  List<String> _campaniasDeGranja = [];
  List<String> _galponOpciones = [];
  List<String> _galponesSel = [];
  bool _galponOtro = false;
  final _galponOtroController = TextEditingController();
  String _turno = 'Dia';

  /// 0 = formulario de ingreso; 1 = regresos tras salida temporal.
  int _vistaIngreso = 0;
  String _hora = '';

  /// Proveedor que llega: su RUC (con la razón social consultada) o su nombre
  /// escrito a mano. La web ya no distingue áreas: el registro es de un
  /// proveedor y su proceso.
  ProveedorSeleccion _proveedor = ProveedorSeleccion.vacia;

  /// Proceso del proveedor: una fila de la lista de proveedores del catálogo o
  /// el texto de «Otro». Es el motivo del ingreso que ve el reporte web.
  String _proceso = '';

  final List<String?> _imagenes = [null, null, null];

  final List<_DniFila> _dnis = [];

  /// Placas en «Vehículos que ingresan»: escritas a mano o bajadas al marcar
  /// la planificación.
  final List<_VehiculoFila> _vehiculos = [];

  /// Vehículos de la visita elegida en planificación (todos, ingresen o no).
  final List<_VehiculoPlan> _vehiculosPlan = [];

  /// Visita planificada cargada (desde la hoja o al refrescar). No depende de
  /// escribir una placa: personas y vehículos van aparte.
  _PlanInfo? _planVisita;

  /// Largo mínimo de placa para consultar la planificación (ABC123 = 6).
  static const int _minPlaca = 5;

  /// Planificación descargada en el equipo (nube del menú lateral) y la hora
  /// de su descarga. Vacía si nunca se descargó: la pantalla funciona como
  /// antes, consultando en línea si hay red.
  PlanDescarga _planLocal = PlanDescarga.vacia;
  DateTime? _planDescargadoEn;

  /// Claves de las planificaciones que ya se registraron: la hoja «Planificadas
  /// de hoy» no las vuelve a ofrecer.
  Set<String> _planesUsados = {};
  StorageService? _storage;
  bool _actualizandoPlan = false;

  /// Estatus sanitario vigente de la granja del registro (`null` = sin novedad).
  EstatusGranja? _estatusGranja;
  Timer? _estatusDebounce;

  /// Personas de la visita planificada elegida.
  final List<_PersonaPlan> _planificadas = [];
  int? _visitaPlanId;

  bool get _hayBloquePlanificacion =>
      _planificadas.isNotEmpty || _vehiculosPlan.isNotEmpty;

  /// Planificados que ya ingresaron: los confirmados a mano o por su DNI.
  int get _planConfirmadas => _planificadas.where((p) => p.efectivo).length;

  /// Último valor que la app escribió sola en «Personas». Mientras el campo
  /// conserve ese valor se mantiene al día con el conteo; si el vigilante lo
  /// cambia, se respeta lo que escribió.
  String _personasAuto = '';

  String get _fechaYmd => DateFormat('yyyy-MM-dd').format(_fecha);

  @override
  void initState() {
    super.initState();
    final now = TimeOfDay.now();
    _hora = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
    _storage = context.read<StorageService>();
    _storage!.addListener(_alCambiarStorage);
    ProveedorHistorialService(_storage!).ensureBootstrapped();
    _cargarPlanLocal();
    _aplicarGranjaDeTrabajo();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _cargarGalpones();
    });
  }

  /// Premarca la granja de trabajo (menú → Mi granja) con su campaña sugerida.
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
  void dispose() {
    for (final d in _dnis) {
      d.dispose();
    }
    for (final v in _vehiculos) {
      v.dispose();
    }
    _estatusDebounce?.cancel();
    _storage?.removeListener(_alCambiarStorage);
    _personasController.dispose();
    _observacionController.dispose();
    _galponOtroController.dispose();
    super.dispose();
  }

  /// Galpones que viajan al JSON (códigos del catálogo y/o texto de «Otro»).
  List<String> get _galponPartes {
    final out = List<String>.from(_galponesSel);
    if (_galponOtro || _galponOpciones.isEmpty) {
      final t = _galponOtroController.text.trim();
      if (t.isNotEmpty) out.add(t);
    }
    return out;
  }

  String get _galponEfectivo => _galponPartes.join(', ');

  bool get _galponPideTextoOtro => _galponOtro || _galponOpciones.isEmpty;

  void _cargarGalpones() {
    if (_granja.isEmpty || _campania.isEmpty) {
      setState(() {
        _galponOpciones = [];
        _galponesSel = [];
        _galponOtro = false;
        _galponOtroController.clear();
      });
      return;
    }
    final storage = context.read<StorageService>();
    final cencos = storage.getCencosGalpones();
    final lista = GalponesResolver.resolveOffline(
      granjaCodigo: _granja,
      campania: _campania,
      galponesPorGranja: storage.getGalponesPorGranjaMapLocal(),
      galponesPorCenco: storage.getGalponesPorCencoLocal(),
      cencosLista: (cencos?['cencos'] as List?)
          ?.whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
    );
    final codigos = lista
        .map((g) => (g['tcodint'] ?? g['galpon'] ?? '').toString().trim())
        .where((c) => c.isNotEmpty)
        .toList();
    setState(() {
      _galponOpciones = codigos;
      _galponesSel =
          _galponesSel.where((g) => codigos.contains(g)).toList();
      if (codigos.isEmpty) {
        _galponOtro = true;
        _galponesSel = [];
      } else if (_galponesSel.isEmpty && codigos.length == 1) {
        _galponesSel = [codigos.first];
        _galponOtro = false;
      }
    });
  }

  // La fecha es de solo lectura: el registro es del día en que se hace, y la
  // planificación de visitas también es la de hoy. Antes se podía retroceder a
  // otro día y el formulario quedaba contando un ingreso de una fecha que no
  // era la del trabajo del vigilante.

  /// Guarda la granja y/o campaña elegidas en [GranjaCampaniaFields].
  void _onGranjaCampania(GranjaCampaniaSeleccion sel) {
    setState(() {
      _granja = sel.granja;
      _granjaNombre = sel.granjaNombre;
      _campania = sel.campania;
      _campaniasDeGranja = sel.campanias;
      _galponesSel = [];
      _galponOtro = false;
      _galponOtroController.clear();
    });
    _cargarGalpones();
    // La planificación depende de la granja y de la fecha: se vuelve a
    // consultar y, si hay red, se actualiza en silencio lo descargado.
    _refrescarPlanificacion();
    if (sel.desdeGranja) _actualizarPlanSilencioso();
  }

  // ---------------------------------------------------------------------------
  // Planificación de visitas (solo informativo)
  //
  // Criterio: visitas activas del portal web con la misma fecha del registro y
  // la misma granja (sin granja elegida se busca en todas). La placa se compara
  // sin guiones ni espacios y el DNI por sus 8 dígitos. Nada de esto valida ni
  // bloquea: si la consulta falla, simplemente no se muestra ningún indicador.
  // ---------------------------------------------------------------------------

  /// Lee la planificación descargada en el equipo.
  void _cargarPlanLocal() {
    final storage = _storage;
    if (storage == null) return;
    _planLocal = PlanVisitasService.local(storage);
    _planDescargadoEn = storage.getPlanVisitasFecha();
    _planesUsados = storage.getPlanesUsados().toSet();
  }

  /// Si se descargó una planificación nueva (nube del menú lateral o
  /// actualización silenciosa) mientras la pantalla está abierta, se vuelve a
  /// evaluar la placa y los DNIs con lo nuevo.
  void _alCambiarStorage() {
    final fecha = _storage?.getPlanVisitasFecha();
    if (!mounted || fecha == null || fecha == _planDescargadoEn) return;
    setState(_cargarPlanLocal);
    _refrescarPlanificacion();
  }

  /// Actualización silenciosa al elegir la granja: solo si lo descargado tiene
  /// más de 10 minutos. Sin red no pasa nada y no se muestra ningún aviso.
  Future<void> _actualizarPlanSilencioso() async {
    final storage = _storage;
    if (storage == null || _actualizandoPlan) return;
    final ultima = _planDescargadoEn;
    if (ultima != null &&
        DateTime.now().difference(ultima) < const Duration(minutes: 10)) {
      return;
    }
    _actualizandoPlan = true;
    try {
      // Si descarga, el listener de StorageService refresca la pantalla.
      await PlanVisitasService().descargar(storage);
    } catch (_) {
    } finally {
      _actualizandoPlan = false;
    }
  }

  /// Tirar hacia abajo: vuelve a bajar la planificación y rehace la pantalla con
  /// lo nuevo, sin salir del formulario.
  ///
  /// Es el mismo dato que trae la nube del menú lateral, pero a pedido: sirve
  /// cuando alguien programa una visita en la web y el de la garita quiere verla
  /// ya. A diferencia de [_actualizarPlanSilencioso] no respeta la ventana de 10
  /// minutos —un tirón es una orden explícita— y tampoco borra nada de lo que el
  /// vigilante ya escribió: solo se refresca lo que depende de la planificación
  /// (el atajo de hoy, el aviso de la placa y la lista de personas).
  Future<void> _refrescar() async {
    final storage = _storage;
    if (storage == null) return;

    var ok = false;
    try {
      ok = await PlanVisitasService().descargar(storage);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;

    setState(_cargarPlanLocal);
    // `forzar`: aunque la visita sea la misma de antes, la lista de personas se
    // rehace con lo recién bajado (la web pudo cambiar quiénes van).
    _refrescarPlanificacion(forzar: true);

    if (ok) {
      showSuccessToast(context, 'Planificación actualizada.');
    } else {
      // Sin red queda lo descargado antes; la pantalla igual se rehace, así que
      // el aviso explica por qué no cambió.
      showWarningToast(
        context,
        'No se pudo actualizar la planificación. Revise la conexión: se '
        'muestran los datos guardados.',
      );
    }
  }

  /// ¿Lo descargado en el equipo incluye la fecha del registro? Cuando no, la
  /// lista del día está vacía porque no hay datos, no porque no haya visitas.
  bool get _planCubreFecha => _planLocal.cubre(_fechaYmd);

  /// Visitas planificadas de hoy para la granja elegida (todas si todavía no se
  /// eligió granja). Sale de lo descargado en el equipo, así que sirve sin
  /// señal; si no hay descarga que cubra la fecha, queda vacía y el atajo lo
  /// explica en vez de ofrecer una lista en blanco.
  List<PlanVisita> get _planDelDia {
    final fecha = _fechaYmd;
    if (!_planCubreFecha) return const [];
    return _planLocal.delDia(
      fechaYmd: fecha,
      granja: _granja,
      excluir: _planesUsados,
    );
  }

  /// «dd/MM/yyyy» de la fecha del registro, para los avisos del atajo.
  String get _fechaCorta => DateFormat('dd/MM/yyyy').format(_fecha);

  /// Vehículos planificados que ya ingresaron (tildados o con su placa puesta).
  int get _vehiculosPlanConfirmados =>
      _vehiculosPlan.where((v) => v.efectivo).length;

  /// Ofrece las visitas planificadas del día para elegir una.
  ///
  /// Es un atajo para la garita, no un paso obligatorio: sin elegir nada el
  /// formulario se llena igual escribiendo o escaneando la placa. Cuando no hay
  /// nada que ofrecer se dice por qué (sin descargar, fecha fuera de la
  /// descarga o ninguna visita): el vigilante no tiene que adivinar si la lista
  /// está vacía o si le falta descargar.
  Future<void> _pickVisitaPlanificada() async {
    if (!_planLocal.descargada) {
      showInfoToast(context, bioSinPlanificacionMsg);
      return;
    }
   /* if (!_planCubreFecha) {
      showInfoToast(
        context,
        'La descarga no incluye el $_fechaCorta. Actualícela desde el menú '
        'lateral.',
      );
      return;
    }*/
    final visitas = _planDelDia;
    if (visitas.isEmpty) {
      showInfoToast(
        context,
        _planesUsados.isNotEmpty
            ? 'No quedan visitas planificadas para el $_fechaCorta.'
            : 'No hay visitas planificadas para el $_fechaCorta.',
      );
      return;
    }
    final sel = await _showPlanificadasSheet(
      context: context,
      visitas: visitas,
      fecha: _fechaCorta,
    );
    if (sel == null || !mounted) return;
    await _elegirVisitaPlanificada(sel);
  }

  /// Carga la visita elegida: un bloque con personas y vehículos planificados,
  /// independientes entre sí. Al marcar, bajan a «Personas que ingresan» o
  /// «Vehículos que ingresan».
  Future<void> _elegirVisitaPlanificada(PlanVisita visita) async {
    _aplicarVisitaPlanificada(_PlanInfo(planificado: true, visita: visita));
  }

  // ---------------------------------------------------------------------------
  // Vehículos planificados y vehículos del formulario
  //
  // La web programa los vehículos con un interruptor «ingresa / no ingresa» y
  // la app los muestra todos, con su casilla. Tildar un vehículo es «ingresó»:
  // su placa baja al bloque del formulario (donde se guarda, se compara con la
  // planificación y se consulta su situación especial) y destildarlo la quita.
  // Es el mismo trato que tienen las personas planificadas.
  // ---------------------------------------------------------------------------

  /// Rehace la lista de vehículos planificados con los de [visita].
  ///
  /// Arrancan destildados: el aviso «ingresa / no ingresa» de la web es solo
  /// informativo. Lo que el vigilante ya había marcado se conserva al refrescar.
  void _cargarVehiculosPlan(PlanVisita? visita) {
    final previos = {for (final v in _vehiculosPlan) v.clave: v};
    _vehiculosPlan.clear();
    if (visita == null) return;
    for (final veh in visita.vehiculosEfectivos) {
      final plan = _VehiculoPlan(placa: veh.placa.trim(), ingresa: veh.ingresa);
      final previo = previos[plan.clave];
      plan.marcado = previo?.marcado ?? false;
      plan.estatus = previo?.estatus;
      _vehiculosPlan.add(plan);
      if (plan.marcado) _bajarPlacaAlFormulario(plan);
    }
    _sincronizarVehiculosPlan();
  }

  /// Baja la placa de [plan] a «Vehículos que ingresan» (renglón nuevo o el que
  /// ya tuviera esa placa).
  void _bajarPlacaAlFormulario(_VehiculoPlan plan) {
    if (plan.clave.isEmpty) return;
    for (final fila in _vehiculos) {
      if (fila.esLaPlaca(plan.placa)) {
        plan.fila = fila;
        fila.ingresaPlan = plan.ingresa;
        fila.planificada = plan.placa.toUpperCase();
        final visita = _planVisita?.visita;
        if (visita != null) {
          fila.plan = _PlanInfo(planificado: true, visita: visita);
        }
        final idx = _vehiculos.indexOf(fila);
        if (idx >= 0) _consultarPlanVehiculo(idx);
        return;
      }
    }
    final fila = _VehiculoFila();
    fila.ctrl.text = plan.placa.toUpperCase();
    fila.planificada = plan.placa.toUpperCase();
    fila.ingresaPlan = plan.ingresa;
    final visita = _planVisita?.visita;
    if (visita != null) {
      fila.plan = _PlanInfo(planificado: true, visita: visita);
    }
    plan.fila = fila;
    _vehiculos.add(fila);
    _consultarPlanVehiculo(_vehiculos.length - 1);
  }

  /// Mantiene alineadas la planificación y «Vehículos que ingresan».
  void _sincronizarVehiculosPlan() {
    for (final plan in _vehiculosPlan) {
      plan.fila = null;
      for (final fila in _vehiculos) {
        if (fila.esLaPlaca(plan.placa)) {
          plan.fila = fila;
          break;
        }
      }
    }
  }

  /// El vigilante confirma o descarta a mano un vehículo planificado.
  void _cambiarVehiculoPlan(int index, bool marcado) {
    if (index < 0 || index >= _vehiculosPlan.length) return;
    setState(() {
      final plan = _vehiculosPlan[index];
      plan.marcado = marcado;
      if (marcado) {
        _bajarPlacaAlFormulario(plan);
      } else {
        // Sin casilla, su placa ya no tiene quien la represente: se saca del
        // formulario (el campo principal o el renglón extra que la traía).
        final fila = plan.fila;
        plan.fila = null;
        if (fila != null) _quitarFilaDeVehiculos(fila);
      }
      _sincronizarVehiculosPlan();
    });
    _consultarEstatusSanitario();
  }

  /* ── Vehículos adicionales (multi-vehículo) ────────────────────────────── */

  /// Agrega un vehículo extra (placa) al registro.
  void _agregarVehiculo() {
    setState(() => _vehiculos.add(_VehiculoFila()));
  }

  void _quitarVehiculo(int index) {
    if (index < 0 || index >= _vehiculos.length) return;
    setState(() {
      _quitarFilaDeVehiculos(_vehiculos[index]);
      _sincronizarVehiculosPlan();
    });
    _consultarEstatusSanitario();
  }

  /// Saca del formulario el renglón [fila] y suelta lo que dependa de él: un
  /// vehículo planificado que la traía deja de estar confirmado por su placa
  /// (la casilla vuelve a depender del toque del vigilante).
  void _quitarFilaDeVehiculos(_VehiculoFila fila) {
    final index = _vehiculos.indexOf(fila);
    if (index < 0) return;
    fila.debounce?.cancel();
    for (final plan in _vehiculosPlan) {
      if (identical(plan.fila, fila)) {
        plan.fila = null;
        plan.marcado = false;
      }
    }
    _vehiculos.removeAt(index);
    fila.dispose();
  }

  /// Al escribir un vehículo extra: se resuelve su planificación con lo
  /// descargado (sin castigar la escritura), se rehacen los vínculos con los
  /// vehículos planificados y se reconsulta el estatus de todas las placas.
  void _alCambiarVehiculo(int index) {
    if (index >= _vehiculos.length) return;
    final fila = _vehiculos[index];
    fila.debounce?.cancel();
    fila.debounce = Timer(const Duration(milliseconds: 400), () {
      _consultarPlanVehiculo(index);
    });
  }

  /// Planificación y situación especial de la placa en [index] (descargado y
  /// en línea), igual que un DNI en la tabla.
  Future<void> _consultarPlanVehiculo(int index) async {
    if (index < 0 || index >= _vehiculos.length) return;
    final fila = _vehiculos[index];
    final placa = fila.placaNorm;
    final granja = _granja;
    final fecha = _fechaYmd;
    if (placa.length < _minPlaca) {
      if (mounted) {
        setState(() {
          if (!_vehiculoEsDePlanificacionActiva(fila)) {
            fila.plan = null;
            fila.ingresaPlan = null;
          }
          _sincronizarVehiculosPlan();
        });
      }
      _consultarEstatusSanitario();
      return;
    }
    if (_planLocal.cubre(fecha)) {
      final c = _planLocal.buscarPlaca(placa, granja: granja, fechaYmd: fecha);
      final veh = c.visita?.vehiculoDe(fila.ctrl.text);
      if (mounted && identical(_vehiculos[index], fila)) {
        setState(() {
          if (_vehiculoEsDePlanificacionActiva(fila)) {
            _fijarPlanVehiculoDesdePlanificacion(
              fila,
              visita: c.visita ?? _planVisita?.visita,
            );
          } else {
            fila.plan = _PlanInfo.deLocal(c);
          }
          fila.ingresaPlan = veh?.ingresa ?? fila.ingresaPlan;
          _sincronizarVehiculosPlan();
        });
      }
    }
    final res = await ApiService().consultarPlanificacion(
      fechaYmd: fecha,
      granja: granja,
      placa: placa,
    );
    if (!mounted ||
        index >= _vehiculos.length ||
        !identical(_vehiculos[index], fila) ||
        fila.placaNorm != placa ||
        _granja != granja ||
        _fechaYmd != fecha) {
      return;
    }
    final enLinea = _PlanInfo.desde(res?['placa']);
    if (enLinea != null) {
      final veh = enLinea.visita?.vehiculoDe(fila.ctrl.text);
      setState(() {
        if (_vehiculoEsDePlanificacionActiva(fila)) {
          _fijarPlanVehiculoDesdePlanificacion(
            fila,
            visita: enLinea.visita ?? _planVisita?.visita,
          );
        } else {
          fila.plan = enLinea;
        }
        fila.ingresaPlan = veh?.ingresa ?? fila.ingresaPlan;
        _sincronizarVehiculosPlan();
      });
    }
    _consultarEstatusSanitario();
  }

  /// Placas en «Vehículos que ingresan» (sin repetir).
  List<String> get _placasEscritas {
    final out = <String>[];
    for (final v in _vehiculos) {
      final t = v.ctrl.text.trim();
      if (t.isEmpty) continue;
      if (out.any((e) => PlanDescarga.normPlaca(e) == v.placaNorm)) continue;
      out.add(t);
    }
    return out;
  }

  /// Vehículos que viajan en el registro: placa + «ingresa» informativo de la web.
  List<Map<String, dynamic>> get _vehiculosRegistro {
    final out = <Map<String, dynamic>>[];
    for (final v in _vehiculos) {
      final t = v.placa.trim().toUpperCase();
      if (t.isEmpty || out.any((e) => e['placa'] == t)) continue;
      final ingresa =
          v.ingresaPlan ?? v.plan?.visita?.vehiculoDe(v.ctrl.text)?.ingresa;
      out.add({'placa': t, 'ingresa': ingresa == false ? 0 : 1});
    }
    return out;
  }

  /// Carga personas y vehículos de la visita en el bloque de planificación.
  ///
  /// Con [forzar] la lista se rehace también cuando la visita es la misma, pero
  /// conservando lo que el vigilante ya confirmó (a mano o escaneando el DNI):
  /// volver a bajar la planificación no puede desmarcar su trabajo.
  void _aplicarVisitaPlanificada(_PlanInfo info, {bool forzar = false}) {
    if (!mounted) return;
    final visita = info.planificado ? info.visita : null;
    if (visita == null) return;
    final catalogo = context.read<CatalogService>();
    setState(() {
      _planVisita = info;
      if (visita.id != _visitaPlanId || forzar) {
        final previas = {for (final p in _planificadas) p.dni: p};
        _visitaPlanId = visita.id;
        _planificadas
          ..clear()
          ..addAll(
            visita.personas.map(
              (p) {
                final fila = _PersonaPlan(
                  dni: p.dni,
                  // Sin nombre en la planificación: se intenta con el catálogo
                  // local de usuarios; si tampoco está, queda vacío.
                  nombre: p.nombre.isNotEmpty
                      ? p.nombre
                      : catalogo.nombrePorDni(p.dni),
                );
                final previa = previas[p.dni];
                if (previa != null) {
                  fila.marcado = previa.marcado;
                  fila.confirmadaPor = previa.confirmadaPor;
                }
                return fila;
              },
            ),
          );
        // Los vehículos de la visita, con su casilla y el switch de la web.
        _cargarVehiculosPlan(visita);
        // Lo que la web programó se trae al formulario para que el vigilante
        // confirme en vez de volver a escribirlo. Solo si la visita lo trae y
        // si el campo está vacío: lo que él ya haya elegido no se pisa.
        //
        // El proceso va en `proceso` en las planificaciones nuevas y en `motivo`
        // en las viejas, donde la lista de proveedores hacía de lista de
        // procesos: se aceptan las dos.
        if (_proceso.trim().isEmpty) {
          final plan = visita.proceso.trim().isNotEmpty
              ? visita.proceso.trim()
              : visita.areaProveedorValor.trim();
          if (plan.isNotEmpty) _proceso = plan;
        }
        if (_proveedor.estaVacio) {
          final nombre = visita.razonSocial.trim();
          final ruc = visita.ruc;
          if (nombre.isNotEmpty || ruc.isNotEmpty) {
            _proveedor = ProveedorSeleccion(ruc: ruc, nombre: nombre);
          }
        }
        if (visita.observacion.trim().isNotEmpty &&
            _observacionController.text.trim().isEmpty) {
          _observacionController.text = visita.observacion.trim();
        }
        // Los DNI que ya estaban escritos en la tabla (el vigilante los anotó
        // antes de cargar la placa) confirman su casilla al pasar.
        _confirmarDnisDeLaTabla();
      }
      _marcarYaIngresadosDelPlan();
    });
    _sincronizarPersonas();
    _consultarEstatusSanitario();
  }

  /// Marca en la lista planificada quién ya ingresó en un guardado anterior.
  void _marcarYaIngresadosDelPlan() {
    final planId = _planVisita?.visita?.id;
    final storage = _storage;
    if (planId == null || planId == 0 || storage == null) return;
    final ya = IngresoPresenciaService.dnisIngresadosEnPlanVisita(
      storage,
      planId.toString(),
      fechaYmd: _fechaYmd,
    );
    for (final p in _planificadas) {
      if (!ya.contains(p.dni)) continue;
      p.yaRegistrado = true;
      p.marcado = false;
      final fila = p.confirmadaPor;
      p.confirmadaPor = null;
      if (fila != null) _quitarFilaDeDnis(fila);
    }
  }

  // ---------------------------------------------------------------------------
  // Confirmación de la lista planificada
  //
  // La idea es contrastar la visita planificada con la real: la casilla de una
  // persona se marca cuando su DNI aparece en la tabla (escaneado o escrito
  // completo) o cuando el vigilante la toca a mano. Nada de esto bloquea el
  // registro: los DNI que no estaban planificados siguen entrando igual.
  // ---------------------------------------------------------------------------

  /// Confirma la casilla de las personas planificadas cuyo DNI ya está completo
  /// en la tabla.
  void _confirmarDnisDeLaTabla() {
    for (final fila in _dnis) {
      _confirmarEnLista(fila);
    }
  }

  /// Si el DNI de [fila] corresponde a una persona planificada, la confirma.
  /// Devuelve `true` si confirmó a alguien.
  bool _confirmarEnLista(_DniFila fila) {
    if (!fila.completo) return false;
    for (final p in _planificadas) {
      if (p.dni == fila.dni) {
        p.confirmadaPor = fila;
        _fijarPlanPersonaDesdePlanificacion(fila);
        return true;
      }
    }
    return false;
  }

  /// Suelta el vínculo de [fila] si su DNI ya no es el de la persona que había
  /// confirmado (lo cambió o lo borró). Devuelve `true` si hubo algo que soltar.
  bool _revisarConfirmacion(_DniFila fila) {
    var cambio = false;
    for (final p in _planificadas) {
      if (!identical(p.confirmadaPor, fila)) continue;
      if (!fila.completo || p.dni != fila.dni) {
        p.confirmadaPor = null;
        // La casilla marcada a mano también se destilda: ese renglón ya no es
        // suyo, así que la persona dejó de estar en la tabla.
        p.marcado = false;
        cambio = true;
      }
    }
    return cambio;
  }

  /// La fila que confirma a una persona ya no existe: se suelta el vínculo. Si
  /// la había marcado el vigilante a mano, la casilla también se destilda: sin
  /// renglón en la tabla, esa persona ya no está ingresando.
  void _soltarConfirmacion(_DniFila fila) {
    for (final p in _planificadas) {
      if (!identical(p.confirmadaPor, fila)) continue;
      p.confirmadaPor = null;
      p.marcado = false;
    }
  }

  /// El vigilante confirma o descarta a mano a una persona planificada.
  ///
  /// Las dos listas dicen lo mismo: marcar es «ingresó», así que la persona
  /// pasa a la tabla de los DNIs que ingresan —se enlaza el renglón que ya
  /// tuviera o se crea uno— y desmarcar es «no ingresó», así que ese renglón se
  /// va. Sin textos que lo expliquen: marcar y desmarcar se ve en la tabla.
  void _cambiarPersonaPlan(int index, bool marcado) {
    if (index < 0 || index >= _planificadas.length) return;
    if (_planificadas[index].yaRegistrado) return;
    setState(() {
      final p = _planificadas[index];
      p.marcado = marcado;
      if (!marcado) {
        // Al descartarla, su renglón de la tabla ya no tiene a quién
        // representar: se suelta y se elimina.
        final fila = p.confirmadaPor;
        p.confirmadaPor = null;
        if (fila != null) _quitarFilaDeDnis(fila);
        return;
      }

      // A mano o con el documento, la persona ingresa: tiene que estar en la
      // tabla. Si el vigilante ya la había escrito o escaneado, se enlaza ese
      // renglón; si no, se crea con el DNI y el nombre que trae la visita.
      final existente = _dnis.indexWhere((d) => d.dni == p.dni);
      if (existente >= 0) {
        p.confirmadaPor = _dnis[existente];
        _fijarPlanPersonaDesdePlanificacion(_dnis[existente]);
        return;
      }
      final fila = _DniFila();
      fila.ctrl.text = p.dni;
      final nombre = p.nombre.trim();
      if (nombre.isNotEmpty) {
        // El nombre ya se conoce (lo registró la web al programar la visita):
        // sale puesto en vez de volver a consultarlo.
        fila.nombre = nombre;
        fila.consultado = p.dni;
        fila.estado = _DniEstado.ok;
      }
      _fijarPlanPersonaDesdePlanificacion(fila);
      _dnis.add(fila);
      p.confirmadaPor = fila;
    });
    _sincronizarPersonas();
    // La persona acaba de entrar a la tabla: se consulta si viene de una granja
    // en situación especial, igual que si el DNI se hubiera escrito a mano.
    _consultarEstatusSanitario();
  }

  /// Saca de la tabla el renglón [fila], soltando lo que dependa de él.
  void _quitarFilaDeDnis(_DniFila fila) {
    final index = _dnis.indexWhere((d) => identical(d, fila));
    if (index < 0) return;
    // Sin el renglón, una consulta pendiente apuntaría al que ocupe su lugar.
    fila.debounce?.cancel();
    _soltarConfirmacion(fila);
    _dnis.removeAt(index);
    fila.dispose();
  }

  /// Planificación del DNI de una fila: primero lo descargado y, si hay red,
  /// la confirmación en línea.
  Future<void> _consultarPlanDni(int index) async {
    if (index < 0 || index >= _dnis.length) return;
    final fila = _dnis[index];
    final dni = fila.dni;
    if (dni.length != _largoDni) return;
    final granja = _granja;
    final fecha = _fechaYmd;
    if (_planLocal.cubre(fecha)) {
      setState(() {
        if (_dniEsDePlanificacionActiva(dni)) {
          _fijarPlanPersonaDesdePlanificacion(fila);
        } else {
          fila.plan = _PlanInfo.deLocal(
            _planLocal.buscarDni(dni, granja: granja, fechaYmd: fecha),
          );
        }
      });
      _sincronizarPersonas();
    }
    final res = await ApiService().consultarPlanificacion(
      fechaYmd: fecha,
      granja: granja,
      dnis: [dni],
    );
    if (!mounted || _granja != granja || _fechaYmd != fecha) return;
    if (!_dnis.any((d) => identical(d, fila)) || fila.dni != dni) return;
    final porDni = res?['dnis'];
    final enLinea = _PlanInfo.desde(porDni is Map ? porDni[dni] : null);
    if (enLinea != null) {
      setState(() {
        if (_dniEsDePlanificacionActiva(dni)) {
          _fijarPlanPersonaDesdePlanificacion(fila);
        } else {
          fila.plan = enLinea;
        }
      });
    }
    _sincronizarPersonas();
    // El DNI pudo ingresar a una granja en situación especial: se consulta para
    // la etiqueta. Va aparte de la planificación porque es otra consulta.
    _consultarEstatusSanitario();
  }

  /// Tras cambiar granja, fecha o lo descargado: se vuelve a evaluar todo.
  ///
  /// [forzar] llega del tirón de refresco: rehace la lista de personas
  /// planificadas aunque la visita descargada sea la misma de antes.
  void _refrescarPlanificacion({bool forzar = false}) {
    setState(() {
      for (final d in _dnis) {
        d.plan = null;
        d.estatus = null;
      }
      for (final v in _vehiculos) {
        v.plan = null;
        v.estatus = null;
      }
      for (final v in _vehiculosPlan) {
        v.estatus = null;
      }
    });
    final visita = _planLocal.visitaPorId(_visitaPlanId);
    if (visita != null) {
      _aplicarVisitaPlanificada(
        _PlanInfo(planificado: true, visita: visita),
        forzar: forzar,
      );
    }
    for (var i = 0; i < _dnis.length; i++) {
      _consultarPlanDni(i);
    }
    for (var i = 0; i < _vehiculos.length; i++) {
      _consultarPlanVehiculo(i);
    }
    _consultarEstatusSanitario();
  }

  // ---------------------------------------------------------------------------
  // Estatus sanitario por granja (solo informativo)
  //
  // Mientras una granja esté en sospecha o confirmado, quien haya ingresado a
  // ella lleva la etiqueta de situación especial al entrar a otra. La consulta
  // es puntual y silenciosa: si falla, no hay etiqueta y el registro sigue.
  // ---------------------------------------------------------------------------

  /// Consulta el estatus de la granja y de los DNIs escritos en la tabla.
  ///
  /// Con una pausa corta: al agregar varios DNI seguidos (o al refrescar) se
  /// consulta una sola vez con la lista completa.
  void _consultarEstatusSanitario() {
    _estatusDebounce?.cancel();
    _estatusDebounce = Timer(
      const Duration(milliseconds: 300),
      _consultarEstatusSanitarioAhora,
    );
  }

  Future<void> _consultarEstatusSanitarioAhora() async {
    final granja = _granja;
    final fecha = _fechaYmd;
    final dnis = <String>[
      for (final d in _dnis)
        if (d.completo) d.dni,
    ];
    final placas = _placasEscritas;
    if (granja.isEmpty && dnis.isEmpty && placas.isEmpty) {
      if (mounted && _estatusGranja != null) {
        setState(() => _estatusGranja = null);
      }
      return;
    }
    final res = await EstatusSanitarioService().consultar(
      fechaYmd: fecha,
      granja: granja,
      dnis: dnis,
      placas: placas,
    );
    if (!mounted) return;
    // Llegó tarde: el vigilante ya cambió de granja, de fecha o de DNIs.
    if (_granja != granja || _fechaYmd != fecha) return;
    setState(() {
      _estatusGranja = res?.granjaEnEstatus;
      for (final d in _dnis) {
        final e = res?.dnis[d.dni];
        d.estatus = (e != null && e.enRiesgo) ? e : null;
      }
      for (final v in _vehiculos) {
        v.estatus = _enRiesgo(res?.placas[PlanDescarga.normPlaca(v.ctrl.text)]);
      }
      for (final v in _vehiculosPlan) {
        v.estatus = v.efectivo
            ? _enRiesgo(res?.placas[PlanDescarga.normPlaca(v.placa)])
            : null;
        final fila = v.fila;
        if (fila != null && v.efectivo) {
          fila.estatus = v.estatus;
        }
      }
    });
    _sincronizarVehiculosPlan();
  }

  /// El estatus solo se dibuja cuando [EstatusDni.enRiesgo] es `true`.
  static EstatusDni? _enRiesgo(EstatusDni? e) =>
      (e != null && e.enRiesgo) ? e : null;

  /// Cuántos DNI ingresan: los planificados confirmados (a mano o por su DNI) y
  /// los escritos en la tabla, completos y sin repetir. Alimenta el campo
  /// «Personas», que sin visitas planificadas sigue siendo manual.
  int _conteoIngresan() {
    final vistos = <String>{};
    for (final p in _planificadas) {
      if (p.efectivo) vistos.add(p.dni);
    }
    for (final d in _dnis) {
      if (d.completo) vistos.add(d.dni);
    }
    return vistos.length;
  }

  /// Mantiene «Personas» al día con el conteo mientras el vigilante no lo haya
  /// escrito a mano. Solo actúa cuando hay personas planificadas cargadas.
  void _sincronizarPersonas() {
    final actual = _personasController.text.trim();
    if (actual.isNotEmpty && actual != _personasAuto) return;
    if (_planificadas.isEmpty && _personasAuto.isEmpty) return;
    final total = _conteoIngresan();
    // Al cargar la placa todavía no hay nadie confirmado: se propone el tamaño
    // de la visita para que el campo no arranque en 0.
    final nuevo = _planificadas.isEmpty
        ? ''
        : '${total == 0 ? _planificadas.length : total}';
    if (nuevo == actual) {
      _personasAuto = nuevo;
      return;
    }
    _personasAuto = nuevo;
    _personasController.text = nuevo;
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
    if (sel != null) {
      setState(() => _turno = sel);
    }
  }

  /// Elige el proveedor que llega: su RUC —y entonces la razón social la
  /// resuelve la consulta en línea— o su nombre escrito a mano.
  Future<void> _pickProveedor() async {
    final api = ApiService();
    final historial = ProveedorHistorialService(_storage!);
    final sel = await showProveedorDialog(
      context: context,
      actual: _proveedor,
      buscarProveedorLocal: (_) => const [],
      buscarProveedorCcte: (q) => api.buscarProveedorCcte(q),
      consultarRuc: (_) async => {'success': false},
    );
    if (sel == null) return;
    if (!sel.estaVacio) {
      unawaited(historial.registrar(sel, fuente: 'manual'));
    }
    setState(() => _proveedor = sel);
  }

  /// Elige el proceso del proveedor: una fila de la lista de proveedores del
  /// catálogo, o el texto de «Otro».
  Future<void> _pickProceso() async {
    final catalogo = context.read<CatalogService>();
    // La web guarda los procesos de proveedor en la lista de proveedores
    // (`bio_areaproveedor_catalogo()['PROVEEDOR']`); es la misma que ofrece
    // para planificar, así que la app muestra esa y no la de áreas.
    final procesos = catalogo.proveedores;
    if (!bioHayCatalogo(context, procesos)) return;
    final sel = await showProcesoDialog(
      context: context,
      actual: _proceso,
      procesos: procesos,
    );
    if (sel == null) return;
    setState(() => _proceso = sel);
  }

  /// Agrega un renglón vacío para escribir un DNI.
  void _agregarDni() {
    setState(() => _dnis.add(_DniFila()));
  }

  void _quitarDni(int index) {
    setState(() => _quitarFilaDeDnis(_dnis[index]));
    _sincronizarPersonas();
  }

  /// Consulta el nombre del documento de una fila.
  ///
  /// El token de la API vive en el servidor, así que la app solo manda los 8
  /// dígitos. Primero se intenta en línea; si eso falla (sin red, red lenta o
  /// error desconocido) se cae al catálogo local de usuarios, donde `libtri`
  /// guarda el DNI. Si la fila se eliminó mientras viajaba la respuesta, se
  /// descarta.
  Future<void> _consultarNombre(int index) async {
    if (index < 0 || index >= _dnis.length) return;
    final fila = _dnis[index];
    final dni = fila.dni;
    if (dni.length != _largoDni) return;
    if (fila.consultado == dni && fila.estado == _DniEstado.ok) return;

    // Se lee antes del await: el catálogo en memoria no cambia mientras tanto y
    // así el contexto no se usa después de un hueco asíncrono.
    final catalogo = context.read<CatalogService>();

    // La segunda barrera va primero: si el DNI está entre los usuarios
    // descargados el nombre aparece al instante, sin esperar a la red, y la
    // consulta en línea solo lo confirma (o lo corrige).
    final delCatalogo = catalogo.nombrePorDni(dni);
    setState(() {
      fila.nombre = delCatalogo;
      fila.estado = delCatalogo.isEmpty
          ? _DniEstado.consultando
          : _DniEstado.ok;
    });

    final res = await ApiService().consultarDni(dni);
    if (!mounted) return;
    // La fila pudo eliminarse o cambiar de documento mientras se consultaba.
    if (index >= _dnis.length || !identical(_dnis[index], fila)) return;
    if (fila.dni != dni) return;

    final enLinea =
        res['success'] == true ? (res['nombre'] ?? '').toString().trim() : '';

    setState(() {
      fila.consultado = dni;
      // Si en línea no hay nada, se queda lo que ya resolvió el catálogo.
      if (enLinea.isNotEmpty) {
        fila.nombre = enLinea;
        fila.estado = _DniEstado.ok;
      } else if (delCatalogo.isEmpty) {
        fila.nombre = '';
        fila.estado = _DniEstado.sinNombre;
      }
    });
  }

  /// Al escribir: se descarta el nombre anterior y, con los 8 dígitos, se
  /// consulta solo (con una pausa para no llamar en cada tecla).
  void _alCambiarDni(int index) {
    if (index >= _dnis.length) return;
    final fila = _dnis[index];
    fila.debounce?.cancel();
    final valor = fila.dni;

    // Al cambiar el documento se descarta lo que pertenecía al anterior: tanto
    // el nombre resuelto como el que el operador hubiera escrito a mano.
    if (fila.plan != null || fila.estatus != null) {
      setState(() {
        fila.plan = null;
        fila.estatus = null;
      });
    }
    if (valor != fila.consultado &&
        (fila.estado != _DniEstado.vacio ||
            fila.nombre.isNotEmpty ||
            fila.nombreCtrl.text.isNotEmpty)) {
      setState(() {
        fila.nombre = '';
        fila.nombreCtrl.clear();
        fila.estado = _DniEstado.vacio;
      });
    }

    if (fila.completo) {
      fila.debounce = Timer(const Duration(milliseconds: 450), () {
        _consultarNombre(index);
        _consultarPlanDni(index);
        // El DNI quedó completo: si es de una persona planificada, su casilla
        // se marca sola. Se confirma acá —una vez por documento— y no en cada
        // tecla, para que el vigilante pueda desmarcarla y no se vuelva a
        // marcar al instante.
        if (index < _dnis.length && identical(_dnis[index], fila)) {
          setState(() {
            _confirmarEnLista(fila);
          });
          _sincronizarPersonas();
        }
      });
    }
    // Con el DNI cambiado, la confirmación que hubiera hecho ya no vale. Se
    // revisa en cada tecla para que la casilla no quede mintiendo.
    if (_revisarConfirmacion(fila)) setState(() {});
    _sincronizarPersonas();
  }

  /// Abre el escáner y coloca el documento leído en la fila indicada.
  Future<void> _escanearEnFila(int index) async {
    final dni = await DniScannerScreen.open(context);
    if (dni == null || !mounted || index >= _dnis.length) return;
    final fila = _dnis[index];
    setState(() {
      fila.ctrl.text = dni;
      fila.consultado = '';
      fila.nombre = '';
      // El nombre escrito a mano era de otro documento.
      fila.nombreCtrl.clear();
      fila.estado = _DniEstado.vacio;
      fila.plan = null;
      fila.estatus = null;
      // El documento anterior ya no confirma a nadie y el nuevo, si está
      // planificado, marca su casilla de inmediato.
      _soltarConfirmacion(fila);
      _confirmarEnLista(fila);
    });
    _sincronizarPersonas();
    _consultarPlanDni(index);
    await _consultarNombre(index);
  }

  /// Abre el escáner y agrega una fila nueva con el documento leído.
  Future<void> _escanearNuevoDni() async {
    final dni = await DniScannerScreen.open(context);
    if (dni == null || !mounted) return;

    // Un documento repetido no genera otra fila: solo se refresca su nombre.
    final existente = _dnis.indexWhere((d) => d.dni == dni);
    if (existente >= 0) {
      setState(() {
        _confirmarEnLista(_dnis[existente]);
      });
      _sincronizarPersonas();
      _consultarPlanDni(existente);
      await _consultarNombre(existente);
      return;
    }

    final fila = _DniFila();
    fila.ctrl.text = dni;
    setState(() {
      _dnis.add(fila);
      _confirmarEnLista(fila);
    });
    _sincronizarPersonas();
    FocusManager.instance.primaryFocus?.unfocus();
    _consultarPlanDni(_dnis.length - 1);
    await _consultarNombre(_dnis.length - 1);
  }

  /// Cantidad de personas declarada en el formulario.
  int get _personas => int.tryParse(_personasController.text.trim()) ?? 0;

  Map<String, dynamic> _buildRecord(StorageService storage) {
    // Cada DNI viaja con su nombre: el que resolvió la consulta o, si no hubo
    // (sin conexión y sin catálogo), el que escribió el operador a mano.
    final dnis = <Map<String, String>>[];
    final vistos = <String>{};
    // Primero las personas planificadas que quedaron confirmadas (escaneadas o
    // marcadas a mano); el formato es el mismo de siempre (dni + nombre).
    for (final p in _planificadas) {
      if (!p.efectivo || !vistos.add(p.dni)) continue;
      dnis.add({'dni': p.dni, 'nombre': p.nombre});
    }
    for (final d in _dnis) {
      final v = d.dni;
      if (v.isEmpty || !vistos.add(v)) continue;
      dnis.add({'dni': v, 'nombre': d.nombreEfectivo});
    }

    final imagenes = _imagenes
        .whereType<String>()
        .where((p) => p.trim().isNotEmpty)
        .map((p) => {'path': p})
        .toList();

    final visita = _planVisita?.visita;
    return {
      'id': const Uuid().v4(),
      'reporte': 'ingreso',
      'fecha': _fechaYmd,
      'granja': _granja,
      'granjaNombre': _granjaNombre,
      'campania': _campania,
      'turno': _turno,
      'usuario': storage.getUserCodeSync() ?? '',
      'nombre_usuario': storage.getUserName() ?? '',
      'registro': {
        if (visita != null) 'plan_visita_id': visita.id,
        'hora': _hora,
        'vehiculos': _vehiculosRegistro,
        'numpersonas': _personas,
        // El registro es siempre de un proveedor: la web dejó de distinguir
        // áreas, así que el tipo va fijo y el proceso ocupa el motivo.
        'areaproveedor': TiposVisitante.proveedor,
        'motivo': _proceso.trim(),
        'galpon': _galponEfectivo,
        if (_galponPartes.isNotEmpty) 'galpones': _galponPartes,
        'proveedor': _proveedor.nombre.trim(),
        'proveedor_ruc': _proveedor.ruc.trim(),
        'observacion': _observacionController.text.trim(),
        'dnis': dnis,
      },
      'imagenes': imagenes,
      'synced': false,
      'guardado_backend': false,
      'created_at': DateTime.now().toIso8601String(),
    };
  }

  /// Devuelve el primer problema de los DNIs, o '' si todo está bien.
  String _validarDnis() {
    final vistos = <String>{};
    for (final d in _dnis) {
      final v = d.dni;
      if (v.isEmpty) continue;
      if (v.length != _largoDni) {
        return 'El DNI «$v» debe tener $_largoDni dígitos.';
      }
      if (!vistos.add(v)) {
        return 'El DNI «$v» está repetido.';
      }
    }
    return '';
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
    if (_galponEfectivo.isEmpty) {
      showErrorToast(context, 'Indique el galpón.');
      return;
    }
    if (_personas < 1) {
      showErrorToast(context, 'Indique cuántas personas ingresaron.');
      return;
    }
    if (_proceso.trim().isEmpty) {
      showErrorToast(context, 'Indique el proceso.');
      return;
    }
    final errorDni = _validarDnis();    if (errorDni.isNotEmpty) {
      showErrorToast(context, errorDni);
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
        if (!_proveedor.estaVacio) {
          unawaited(
            ProveedorHistorialService(storage).registrar(
              _proveedor,
              fuente: 'ingreso',
            ),
          );
        }
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
      final visitaUsada = _planVisita?.visita ??
          _planLocal.visitaPorId(_visitaPlanId);
      final planIdUsado = visitaUsada?.id;
      var planQuedaAbierto = false;
      if (planIdUsado != null && planIdUsado != 0) {
        final ingresados = IngresoPresenciaService.dnisIngresadosEnPlanVisita(
          storage,
          planIdUsado.toString(),
          fechaYmd: _fechaYmd,
        );
        planQuedaAbierto = visitaUsada!.personas.any(
          (p) => !ingresados.contains(p.dni),
        );
        if (!planQuedaAbierto) {
          await storage.addPlanVisitaUsada(planIdUsado.toString());
        }
      }
      if (!mounted) return;
      setState(() {
        _planesUsados = storage.getPlanesUsados().toSet();
        _estatusGranja = null;
        _personasAuto = '';
        _personasController.clear();
        _observacionController.clear();
        _galponesSel = _galponOpciones.length == 1
            ? [_galponOpciones.first]
            : [];
        _galponOtro = _galponOpciones.isEmpty;
        if (!_galponOtro) {
          _galponOtroController.clear();
        }
        for (final d in _dnis) {
          d.dispose();
        }
        _dnis.clear();
        for (final v in _vehiculos) {
          v.dispose();
        }
        _vehiculos.clear();
        _imagenes
          ..clear()
          ..addAll([null, null, null]);
        if (planQuedaAbierto) {
          _marcarYaIngresadosDelPlan();
          _sincronizarPersonas();
        } else {
          _planVisita = null;
          _planificadas.clear();
          _vehiculosPlan.clear();
          _visitaPlanId = null;
          _proveedor = ProveedorSeleccion.vacia;
          _proceso = '';
        }
      });
    }
  }

  /// Cómo se nombra a la persona en los avisos: su nombre si ya se resolvió y,
  /// si no, el DNI.
  String _sujetoDe(_DniFila fila) {
    final nombre = fila.nombreEfectivo.trim();
    return nombre.isNotEmpty ? nombre : 'DNI ${fila.dni}';
  }

  bool _dniEsDePlanificacionActiva(String dni) =>
      _planificadas.any((p) => p.dni == dni && p.efectivo);

  bool _vehiculoEsDePlanificacionActiva(_VehiculoFila fila) {
    if (fila.planificada.isNotEmpty) return true;
    return _vehiculosPlan.any(
      (p) =>
          p.marcado &&
          (identical(p.fila, fila) || fila.esLaPlaca(p.placa)),
    );
  }

  void _fijarPlanPersonaDesdePlanificacion(_DniFila fila) {
    fila.plan = _PlanInfo(
      planificado: true,
      visita: _planVisita?.visita,
    );
  }

  void _fijarPlanVehiculoDesdePlanificacion(
    _VehiculoFila fila, {
    PlanVisita? visita,
  }) {
    fila.plan = _PlanInfo(
      planificado: true,
      visita: visita ?? fila.plan?.visita ?? _planVisita?.visita,
    );
  }

  /// Celda «Nombre» con el aviso de planificación debajo («✔ Planificado» o
  /// «⚠ No planificado») y la etiqueta de situación especial cuando el DNI
  /// viene de una granja en sospecha o confirmado. Cuando se escribe el nombre
  /// a mano, los avisos quedan solo como ícono junto al DNI para no apretar la fila.
  Widget _conAvisoPlan(_DniFila fila, Widget celda) {
    final plan = fila.plan;
    final estatus = fila.estatus;
    final avisos = <Widget>[
      if (estatus != null)
        _EtiquetaSituacion(
          estatus: estatus,
          sujeto: _sujetoDe(fila),
          chico: true,
        ),
      if (_dniEsDePlanificacionActiva(fila.dni) &&
          fila.estado != _DniEstado.sinNombre)
        _AvisoPlan(
          plan: _PlanInfo(planificado: true, visita: _planVisita?.visita),
          sujeto: 'DNI ${fila.dni}',
          etiqueta: 'Planificado',
          chico: true,
        )
      else if (plan != null && fila.estado != _DniEstado.sinNombre)
        _AvisoPlan(
          plan: plan,
          sujeto: 'DNI ${fila.dni}',
          etiqueta: plan.planificado ? 'Planificado' : 'No planificado',
          chico: true,
        ),
    ];
    if (avisos.isEmpty) return celda;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(child: celda),
        const SizedBox(height: 2),
        ...avisos,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: SectionAppBar(
        title: AppStrings.menuIngreso,
        sectionIcon: Icons.badge_outlined,
        actions: _vistaIngreso == 0
            ? [AppBarSaveButton(onPressed: _guardar)]
            : null,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('Nuevo ingreso'),
                  icon: Icon(Icons.person_add_alt_1_rounded, size: 18),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('Regreso'),
                  icon: Icon(Icons.login_rounded, size: 18),
                ),
              ],
              selected: {_vistaIngreso},
              onSelectionChanged: (s) =>
                  setState(() => _vistaIngreso = s.first),
            ),
          ),
          Expanded(
            child: _vistaIngreso == 0
                ? RefreshIndicator(
                    onRefresh: _refrescar,
                    color: AppColors.primaryDark,
                    child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            32 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Orden: primero el contexto del registro (cuándo, en qué turno y en
              // qué granja) y después el hecho del ingreso, redactado como se
              // cuenta: a tal hora llegó tal vehículo con N personas de tal área
              // o proveedor y por tal motivo.
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
                      const SizedBox(width: _sepFila),
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
                  const SizedBox(height: _sepCampo),
                  GranjaCampaniaFields(
                    fechaYmd: _fechaYmd,
                    granja: _granja,
                    granjaNombre: _granjaNombre,
                    campania: _campania,
                    campanias: _campaniasDeGranja,
                    onSeleccion: _onGranjaCampania,
                  ),
                  if (_granja.isNotEmpty && _campania.isNotEmpty) ...[
                    const SizedBox(height: _sepCampo),
                    if (_galponOpciones.isNotEmpty)
                      EvidenciaGalponField(
                        value: _galponesSel,
                        options: _galponOpciones,
                        otroSeleccionado: _galponOtro,
                        textoOtro: _galponOtroController.text,
                        onSelected: (r) => setState(() {
                          _galponesSel = r.seleccionados;
                          _galponOtro = r.otro;
                          if (!r.otro) {
                            _galponOtroController.clear();
                          }
                        }),
                      ),
                    if (_galponPideTextoOtro) ...[
                      const SizedBox(height: _sepCampo),
                      TextField(
                        controller: _galponOtroController,
                        decoration: const InputDecoration(
                          labelText: 'Galpón (otro)',
                        ),
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ],
                  // El estatus va pegado a la granja/campaña: es el estado de
                  // esa granja, no un aviso suelto del formulario.
                  if (_estatusGranja != null) ...[
                    const SizedBox(height: _sepCampo),
                    _EstatusGranjaCard(estatus: _estatusGranja!),
                  ],
                ],
              ),
              const SizedBox(height: _sepBloque),
              // Atajo a las visitas planificadas de hoy, antes del ingreso: se
              // elige la que está llegando y el formulario se llena solo.
              // Aparece recién cuando hay granja elegida, porque la lista es la
              // de esa granja (ver [_PlanDelDiaAtajo]).
              // No cambia el flujo: sin usarlo el ingreso se registra igual.
              if (_granja.isNotEmpty) ...[
                _PlanDelDiaAtajo(
                  descargada: _planLocal.descargada,
                  cubreFecha: _planCubreFecha,
                  visitas: _planDelDia.length,
                  onTap: _pickVisitaPlanificada,
                ),
                const SizedBox(height: _sepBloque),
              ],
              BioFormSection(
                title: 'INGRESO',
                icon: Icons.directions_car_rounded,
                children: [
                  // El registro se lee en el orden en que ocurre: a qué hora
                  // llegó, de qué proveedor y con qué proceso viene, en qué
                  // vehículo y cuántas personas.
                  BioTimeField(
                    label: 'Hora de ingreso',
                    value: _hora,
                    onPicked: (v) => setState(() => _hora = v),
                  ),
                  const SizedBox(height: _sepCampo),
                  EvidenciaSelectField(
                    label: 'Proveedor',
                    value: _proveedor.etiqueta,
                    placeholder: 'RUC o nombre',
                    icon: Icons.storefront_rounded,
                    onTap: _pickProveedor,
                  ),
                  const SizedBox(height: _sepCampo),
                  EvidenciaSelectField(
                    label: 'Proceso',
                    value: _proceso,
                    placeholder: 'Seleccione',
                    icon: Icons.account_tree_rounded,
                    onTap: _pickProceso,
                  ),
                  const SizedBox(height: _sepCampo),
                  BioTextArea(
                    label: 'N° Personas',
                    controller: _personasController,
                    hint: 'Ej. 5',
                    maxLength: 3,
                    minLines: 1,
                    maxLines: 1,
                    textCapitalization: TextCapitalization.none,
                  ),
                  const SizedBox(height: _sepCampo),
                  BioTextArea(
                    label: 'Motivo de visita/ Obs.',
                    controller: _observacionController,
                    hint: 'Ej. Mantenimiento de comederos',
                    icon: Icons.edit_rounded,
                    maxLength: 200,
                    minLines: 2,
                    maxLines: 3,
                  ),
                ],
              ),
              const SizedBox(height: _sepBloque),
              // Visita elegida: personas y vehículos juntos. Marcar baja a las
              // secciones de ingreso; el switch «ingresa a granja» de la web es
              // solo informativo en cada renglón.
              if (_hayBloquePlanificacion) ...[
                BioSectionTitle(
                  title: 'Planificación',
                  icon: Icons.event_note_rounded,
                  trailing: Text(
                    '${_planConfirmadas + _vehiculosPlanConfirmados}/'
                    '${_planificadas.length + _vehiculosPlan.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _planConfirmadas == _planificadas.length &&
                              _vehiculosPlanConfirmados == _vehiculosPlan.length
                          ? AppColors.success
                          : AppColors.primaryDark,
                    ),
                  ),
                ),
                if (_planificadas.isNotEmpty) ...[
                  const SizedBox(height: _sepCampo),
                  Text(
                    'Personas',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: context.textThemeSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _ListaPlanificadas(
                    personas: _planificadas,
                    onCambiar: _cambiarPersonaPlan,
                  ),
                ],
                if (_vehiculosPlan.isNotEmpty) ...[
                  const SizedBox(height: _sepCampo),
                  Text(
                    'Vehículos',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: context.textThemeSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _ListaVehiculosPlan(
                    vehiculos: _vehiculosPlan,
                    onCambiar: _cambiarVehiculoPlan,
                  ),
                ],
                const SizedBox(height: _sepBloque),
              ],
              BioSectionTitle(
                title: 'Vehículos que ingresan',
                icon: Icons.directions_car_filled_rounded,
                trailing: Text(
                  '${_vehiculos.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              const SizedBox(height: _sepCampo),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _agregarVehiculo,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Agregar vehículo'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: AppColors.primaryDark,
                    textStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              for (var i = 0; i < _vehiculos.length; i++) ...[
                const SizedBox(height: _sepCampo),
                _FilaVehiculo(
                  fila: _vehiculos[i],
                  onChanged: () => _alCambiarVehiculo(i),
                  onQuitar: () => _quitarVehiculo(i),
                ),
              ],
              const SizedBox(height: _sepBloque),
              BioSectionTitle(
                title: 'Personas que ingresan',
                icon: Icons.credit_card_rounded,
                trailing: Text(
                  '${_dnis.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              const SizedBox(height: _sepCampo),
              // Las acciones van antes de la tabla: son el punto de partida del
              // bloque, no un pie de página.
              // Los dos botones en la misma fila (es donde se agregan los DNI).
              // Van compactos —ícono 17, relleno 6/4 y texto 12.5— para que
              // entren juntos en un teléfono de 360 sin puntos suspensivos ni
              // salirse de la pantalla.
              Row(
                children: [
                  BioAddRowButton(
                    label: 'Escanear DNI',
                    icon: Icons.qr_code_scanner_rounded,
                    onPressed: _escanearNuevoDni,
                  ),
                  const SizedBox(width: 4),
                  BioAddRowButton(
                    label: 'Agregar a mano',
                    onPressed: _agregarDni,
                  ),
                ],
              ),
              const SizedBox(height: _sepCampo),
              BioTable(
                rowHeight: 54,
                columns: const [
                  // Flexibles: la tabla ocupa todo el ancho disponible y ambos
                  // renglones se estiran; los anchos quedan como mínimo. El
                  // nombre pesa más que el DNI (2 a 1): el DNI son 8 dígitos
                  // justos y el nombre necesita el resto.
                  BioColumn('DNI', width: 104, align: TextAlign.left, flex: 1),
                  BioColumn('Nombre', width: 116, align: TextAlign.left, flex: 2),
                  BioColumn('', width: 38),
                ],
                rowCount: _dnis.length,
                rowBuilder: (context, index) {
                  final fila = _dnis[index];
                  return [
                    Row(
                      children: [
                        Expanded(
                          child: BioTextField(
                            controller: fila.ctrl,
                            hint: '$_largoDni dígitos',
                            keyboardType: TextInputType.number,
                            maxLength: _largoDni,
                            soloDigitos: true,
                            onChanged: (_) => _alCambiarDni(index),
                          ),
                        ),
                        if (fila.estatus != null)
                          _EtiquetaSituacion(
                            estatus: fila.estatus!,
                            sujeto: _sujetoDe(fila),
                            compacto: true,
                          ),
                        if (fila.plan != null &&
                            fila.estado == _DniEstado.sinNombre)
                          _AvisoPlan(
                            plan: fila.plan!,
                            sujeto: 'DNI ${fila.dni}',
                            compacto: true,
                          ),
                        _BotonEscanear(
                          tooltip: 'Escanear este DNI',
                          onTap: () => _escanearEnFila(index),
                        ),
                      ],
                    ),
                    _conAvisoPlan(
                      fila,
                      _EstadoNombre(
                        fila: fila,
                        onReintentar: () => _consultarNombre(index),
                      ),
                    ),
                    InkWell(
                      onTap: () => _quitarDni(index),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: AppColors.errorDark,
                      ),
                    ),
                  ];
                },
              ),
              const SizedBox(height: _sepBloque),
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
                  )
                : IngresoRegresoTab(
                    granja: _granja,
                    granjaNombre: _granjaNombre,
                    fechaYmd: _fechaYmd,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Botón compacto de escaneo que vive dentro de la celda del DNI.
class _BotonEscanear extends StatelessWidget {
  const _BotonEscanear({required this.tooltip, required this.onTap});

  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: const Padding(
          padding: EdgeInsets.all(2),
          child: Icon(
            Icons.qr_code_scanner_rounded,
            size: 17,
            color: AppColors.primaryDark,
          ),
        ),
      ),
    );
  }
}

/// Celda «Nombre»: muestra el estado de la consulta del documento.
///
/// Verde con el nombre cuando lo resolvió la consulta en línea; en celeste y con
/// otro ícono cuando salió del catálogo local de usuarios (la segunda barrera,
/// sin conexión). Mientras consulta muestra un indicador. Si ningún camino lo
/// resolvió (sin conexión y el documento fuera del catálogo) se habilita un campo
/// para que el operador escriba el nombre: un «Sin nombre» fijo no se podía
/// completar y el registro quedaba sin identificar a la persona. Nunca se pinta
/// un error, porque un aviso rojo solo estorba al que está registrando.
class _EstadoNombre extends StatelessWidget {
  const _EstadoNombre({required this.fila, required this.onReintentar});

  final _DniFila fila;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    switch (fila.estado) {
      case _DniEstado.consultando:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primaryDark,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Consultando…',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: context.textThemeMuted,
                ),
              ),
            ),
          ],
        );

      case _DniEstado.ok:
        // Sin ícono delante del nombre: el check verde de «Planificado» (ver
        // [_conAvisoPlan]) ya dice lo que hay que saber, y el iconito de
        // «vino del catálogo» o «respondió la consulta» era ruido al lado de
        // cada nombre. Si el nombre no se resolvió, la celda lo dice con su
        // campo para escribirlo (ver [_NombreManual]).
        return Text(
          fila.nombre,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: context.textThemePrimary,
          ),
        );

      case _DniEstado.sinNombre:
        // Ni la consulta en línea ni el catálogo local resolvieron el
        // documento. En vez de dejar un «Sin nombre» que nadie puede completar,
        // se habilita el campo para escribirlo a mano.
        return _NombreManual(
          controller: fila.nombreCtrl,
          onReintentar: onReintentar,
        );

      case _DniEstado.vacio:
        if (!fila.completo) {
          return Text(
            '—',
            style: TextStyle(fontSize: 12.5, color: context.textThemeMuted),
          );
        }
        return InkWell(
          onTap: onReintentar,
          child: Text(
            'Consultar',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: context.textThemePrimary,
              decoration: TextDecoration.underline,
            ),
          ),
        );
    }
  }
}

/// Campo para escribir el nombre a mano cuando la consulta no lo resolvió.
///
/// Se dibuja con una línea inferior para que se lea como algo editable y no como
/// el texto gris de antes: el operador tiene que ver que ahí se escribe. El botón
/// de refresco conserva el reintento de la consulta por si la conexión vuelve; si
/// el documento aparece en línea, su nombre reemplaza al escrito a mano.
class _NombreManual extends StatelessWidget {
  const _NombreManual({required this.controller, required this.onReintentar});

  final TextEditingController controller;
  final VoidCallback onReintentar;

  /// Mismo largo que la columna `nombre` de `rcontroingresodet` en el backend.
  static const int _largoNombre = 60;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.45),
                ),
              ),
            ),
            child: BioTextField(
              controller: controller,
              hint: 'Escriba el nombre',
              maxLength: _largoNombre,
              bold: true,
              textCapitalization: TextCapitalization.words,
            ),
          ),
        ),
        const SizedBox(width: 2),
        Tooltip(
          message: 'Volver a consultar el documento',
          child: InkWell(
            onTap: onReintentar,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                Icons.refresh_rounded,
                size: 14,
                color: context.textThemeMuted,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Hoja «Planificadas de hoy»: una tarjeta por visita con lo programado en la
/// web (placa, granja, campaña, área o proveedor y motivo) y la tabla de DNIs.
///
/// Antes era una lista de una sola línea («AHX-742 · 3 personas») y el
/// vigilante elegía a ciegas: dos visitas del mismo día se veían casi iguales y
/// los DNIs no aparecían hasta después de cargar la visita. Devuelve la visita
/// tocada, o `null` si se cierra sin elegir.
Future<PlanVisita?> _showPlanificadasSheet({
  required BuildContext context,
  required List<PlanVisita> visitas,
  required String fecha,
}) {
  return showModalBottomSheet<PlanVisita>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) => Material(
        // Material y no Container: los ListTile/InkWell pintan su onda sobre el
        // Material más cercano.
        color: context.dialogSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 6),
              decoration: BoxDecoration(
                color: context.textThemeMuted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Planificadas de hoy',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: context.textThemePrimary,
                          ),
                        ),
                        Text(
                          '$fecha · ${visitas.length} '
                          '${visitas.length == 1 ? 'visita' : 'visitas'}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: context.textThemeMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                itemCount: visitas.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _PlanificadaTile(
                  visita: visitas[i],
                  onTap: () => Navigator.pop(context, visitas[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Tarjeta de una visita dentro de la hoja: el encabezado con placa, granja y
/// campaña, la segunda línea con área o proveedor y motivo, y la tabla de DNIs.
class _PlanificadaTile extends StatelessWidget {
  const _PlanificadaTile({required this.visita, required this.onTap});

  final PlanVisita visita;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final granja = [visita.granja, visita.nombreGranja]
        .where((e) => e.trim().isNotEmpty)
        .join(' ');
    final campania = visita.campania.trim().isEmpty
        ? ''
        : GranjaCampaniaPicker.padCampania(visita.campania);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: context.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 14,
              runSpacing: 3,
              children: [
                _DatoInline(
                  label: 'Placa',
                  valor: visita.placasTexto.isEmpty
                      ? '—'
                      : visita.placasTexto.toUpperCase(),
                ),
                _DatoInline(label: 'Granja', valor: granja),
                _DatoInline(label: 'Camp', valor: campania),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 14,
              runSpacing: 3,
              children: [
                _DatoInline(
                  label: 'Área/Proveedor',
                  valor: visita.areaProveedorEtiqueta,
                ),
                _DatoInline(label: 'Motivo/Obs', valor: visita.observacion),
              ],
            ),
            const SizedBox(height: 8),
            _TablaDnisVisita(personas: visita.personas),
            const SizedBox(height: 8),
            Row(
              children: [
                /*Expanded(
                  child: Text(
                    '${visita.personas.length} '
                    '${visita.personas.length == 1 ? 'DNI' : 'DNIs'} '
                    'en la planificación',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: context.textThemeMuted,
                    ),
                  ),
                ),*/
                const Icon(
                  Icons.touch_app_rounded,
                  size: 14,
                  color: AppColors.primaryDark,
                ),
                const SizedBox(width: 3),
                const Text(
                  'Seleccionar esta planificación',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// «Etiqueta: valor» en una sola línea de texto, para encadenarlos con un
/// [Wrap] («Placa: … Granja: … Camp: …»). Un dato que la planificación no
/// registró se muestra como «—», para que se vea que falta.
class _DatoInline extends StatelessWidget {
  const _DatoInline({required this.label, required this.valor});

  final String label;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final texto = valor.trim();
    final vacio = texto.isEmpty;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.textThemeMuted,
            ),
          ),
          TextSpan(
            text: vacio ? '—' : texto,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: vacio ? FontWeight.w400 : FontWeight.w700,
              color: vacio ? context.textThemeMuted : context.textThemePrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tabla de los DNIs de una visita planificada (documento y nombre).
///
/// Una visita puede traer muchos DNIs y la hoja «Planificadas de hoy» se haría
/// larguísima: se ven los primeros y un «Ver más» abre el resto.
class _TablaDnisVisita extends StatefulWidget {
  const _TablaDnisVisita({required this.personas});

  /// Cuántos DNIs se ven antes de ofrecer «Ver más».
  static const int visibles = 3;

  final List<PlanPersona> personas;

  @override
  State<_TablaDnisVisita> createState() => _TablaDnisVisitaState();
}

class _TablaDnisVisitaState extends State<_TablaDnisVisita> {
  bool _todo = false;

  @override
  Widget build(BuildContext context) {
    final personas = widget.personas;
    if (personas.isEmpty) {
      return Text(
        'La planificación no registró DNIs.',
        style: TextStyle(
          fontSize: 11,
          fontStyle: FontStyle.italic,
          color: context.textThemeMuted,
        ),
      );
    }
    final ocultos = personas.length - _TablaDnisVisita.visibles;
    final mostradas = ocultos > 0 && !_todo
        ? personas.sublist(0, _TablaDnisVisita.visibles)
        : personas;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: context.borderSubtle),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _fila(context, 'DNI', 'Nombre', encabezado: true),
          for (var i = 0; i < mostradas.length; i++) ...[
            if (i > 0) Divider(height: 1, color: context.borderSubtle),
            _fila(context, mostradas[i].dni, mostradas[i].nombre),
          ],
          if (ocultos > 0) ...[
            Divider(height: 1, color: context.borderSubtle),
            InkWell(
              onTap: () => setState(() => _todo = !_todo),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Icon(
                      _todo
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 15,
                      color: AppColors.primaryDark,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _todo ? 'Ver menos' : 'Ver $ocultos más',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fila(
    BuildContext context,
    String dni,
    String nombre, {
    bool encabezado = false,
  }) {
    final estilo = TextStyle(
      fontSize: 12.5,
      fontWeight: encabezado ? FontWeight.w800 : FontWeight.w700,
      color: encabezado ? Colors.white : context.textThemePrimary,
    );
    final texto = nombre.trim();
    return Container(
      color: encabezado ? context.tableCaption : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(
              dni,
              style: estilo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Text(
              encabezado ? texto : (texto.isEmpty ? '—' : texto),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: estilo.copyWith(
                fontWeight: encabezado ? FontWeight.w800 : FontWeight.w500,
                color: encabezado
                    ? Colors.white
                    : (texto.isEmpty
                          ? context.textThemeMuted
                          : context.textThemePrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Atajo a las visitas planificadas del día.
///
/// Aparece cuando ya hay granja elegida: la planificación que se ofrece es la
/// de esa granja, así que mostrarlo antes era ofrecer la lista de todas.
///
/// Todo el estado va en el paréntesis del propio botón —cuántas visitas hay, o
/// que falta descargar— en lugar de un segundo renglón de aviso: era el mismo
/// dato repetido en dos o tres mensajes distintos debajo del atajo, y el
/// vigilante tenía que juntarlos para saber qué hacer.
///
/// Solo informa: el ingreso se registra igual sin usar el atajo.
class _PlanDelDiaAtajo extends StatelessWidget {
  const _PlanDelDiaAtajo({
    required this.descargada,
    required this.cubreFecha,
    required this.visitas,
    required this.onTap,
  });

  /// Se descargó la planificación alguna vez desde el menú lateral.
  final bool descargada;

  /// Lo descargado incluye la fecha del registro.
  final bool cubreFecha;

  /// Visitas planificadas de esa fecha (de la granja elegida, si hay una).
  final int visitas;

  final VoidCallback onTap;

  /// Ícono y texto que acompañan al atajo.
  ///
  /// Sin descarga, o con la fecha fuera de lo descargado, no se puede afirmar
  /// cuántas visitas hay: en ese caso el paréntesis dice qué falta hacer, en
  /// vez de mostrar un «(0)» que parecería «no hay ninguna». Con la descarga al
  /// día, el número se muestra siempre, incluido el cero.
  (IconData, String) get _estado {
    if (!descargada) {
      return (Icons.cloud_download_rounded, 'descargue en el panel lateral');
    }
    if (!cubreFecha) {
      return (Icons.update_rounded, 'actualice la descarga del panel lateral');
    }
    return (
      visitas == 0 ? Icons.event_busy_rounded : Icons.event_available_rounded,
      '$visitas',
    );
  }

  @override
  Widget build(BuildContext context) {
    final (icono, detalle) = _estado;

    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        // Row propio y no `TextButton.icon`: el rótulo con el paréntesis es más
        // largo que un teléfono y dentro del Row del botón —sin flexibilidad—
        // se salía de la pantalla. Acá el texto se reparte en dos líneas y el
        // ícono queda arriba, alineado con la primera.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icono, size: 18),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Ver las planificadas de hoy ($detalle)',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Etiqueta de «situación especial» de un DNI.
///
/// Se enciende cuando la persona ingresó recientemente a una granja que hoy
/// está en sospecha (ámbar) o confirmado (rojo). Solo alerta: el registro de
/// ingreso se guarda igual. Al tocarla aparece de qué granja viene y hasta
/// cuándo está vigente el estatus.
class _EtiquetaSituacion extends StatelessWidget {
  const _EtiquetaSituacion({
    required this.estatus,
    required this.sujeto,
    this.compacto = false,
    this.chico = false,
    this.avisoSujeto = 'Esta persona',
  });

  final EstatusDni estatus;
  final String sujeto;
  final bool compacto;
  final bool chico;

  /// Cómo arranca la frase del aviso: «Esta persona» o «El vehículo».
  final String avisoSujeto;

  void _mostrarDetalle(BuildContext context) {
    showSituacionDialog(context: context, estatus: estatus, sujeto: sujeto);
  }

  @override
  Widget build(BuildContext context) {
    final color = colorSituacion(estatus);

    if (compacto) {
      return Tooltip(
        message: estatus.mensaje(sujeto),
        child: InkWell(
          onTap: () => _mostrarDetalle(context),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(Icons.coronavirus_rounded, size: 16, color: color),
          ),
        ),
      );
    }

    return InkWell(
      onTap: () => _mostrarDetalle(context),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: chico ? 0 : 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.coronavirus_rounded, size: chico ? 11 : 13, color: color),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                estatus.avisoIngreso(avisoSujeto),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: chico ? 10 : 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _etiquetaPermisoIngresoGranja(bool ingresa) =>
    ingresa ? 'Ingresa a granja' : 'No ingresa a granja';

/// Varias etiquetas en una línea, separadas con « / ».
class _EtiquetasConSlash extends StatelessWidget {
  const _EtiquetasConSlash({required this.items});

  final List<({String text, Color color})> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final sep = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      color: context.textThemeMuted,
    );
    final spans = <InlineSpan>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) spans.add(TextSpan(text: ' / ', style: sep));
      final it = items[i];
      spans.add(
        TextSpan(
          text: it.text,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: it.color,
          ),
        ),
      );
    }
    return Text.rich(TextSpan(children: spans));
  }
}

List<({String text, Color color})> _etiquetasVehiculo({
  required bool? ingresaWeb,
  required bool planificado,
  required bool mostrarPlan,
}) {
  final out = <({String text, Color color})>[];
  if (ingresaWeb != null) {
    out.add((
      text: _etiquetaPermisoIngresoGranja(ingresaWeb),
      color: ingresaWeb ? AppColors.success : AppColors.warning,
    ));
  }
  if (mostrarPlan) {
    out.add((
      text: planificado ? 'Planificado' : 'No planificado',
      color: planificado ? AppColors.success : AppColors.warning,
    ));
  }
  return out;
}

Widget? _suffixVehiculoIngreso({
  required bool? ingresaWeb,
  required bool planificado,
  required bool mostrarPlan,
}) {
  final items = _etiquetasVehiculo(
    ingresaWeb: ingresaWeb,
    planificado: planificado,
    mostrarPlan: mostrarPlan,
  );
  if (items.isEmpty) return null;
  return Padding(
    padding: const EdgeInsets.only(top: 14, right: 2),
    child: _EtiquetasConSlash(items: items),
  );
}

/// Fila de un vehículo adicional: placa, avisos y botón para quitarlo.
class _FilaVehiculo extends StatelessWidget {
  const _FilaVehiculo({
    required this.fila,
    required this.onChanged,
    required this.onQuitar,
  });

  final _VehiculoFila fila;
  final VoidCallback onChanged;
  final VoidCallback onQuitar;

  @override
  Widget build(BuildContext context) {
    bool? ingresaWeb = fila.ingresaPlan;
    if (ingresaWeb == null) {
      final veh = fila.plan?.visita?.vehiculoDe(fila.ctrl.text);
      if (veh != null) ingresaWeb = veh.ingresa;
    }
    final esPlan = fila.planificada.isNotEmpty ||
        (fila.plan?.planificado ?? false);
    final muestraPlan = esPlan ||
        (fila.plan != null && !fila.plan!.planificado);
    final suffix = _suffixVehiculoIngreso(
      ingresaWeb: ingresaWeb,
      planificado: esPlan,
      mostrarPlan: muestraPlan,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: BioTextArea(
                label: 'Vehículo',
                controller: fila.ctrl,
                hint: 'Ej. AHX-742',
                icon: Icons.directions_car_filled_rounded,
                maxLength: 15,
                minLines: 1,
                maxLines: 1,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => onChanged(),
                suffix: suffix,
              ),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: IconButton(
                onPressed: onQuitar,
                tooltip: 'Quitar vehículo',
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                color: AppColors.error,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        if (fila.estatus != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _EtiquetaSituacion(
              estatus: fila.estatus!,
              sujeto: 'El vehículo ${fila.placa}',
              avisoSujeto: 'El vehículo',
              chico: true,
            ),
          ),
      ],
    );
  }
}

/// Tarjeta de la granja del registro en situación especial (sospecha o
/// confirmado). Va arriba del formulario, antes de los datos del registro.
class _EstatusGranjaCard extends StatelessWidget {
  const _EstatusGranjaCard({required this.estatus});

  final EstatusGranja estatus;

  @override
  Widget build(BuildContext context) {
    final confirmado = estatus.estado == 'CONFIRMADO';
    final color = confirmado ? AppColors.errorDark : AppColors.warning;
    final rango = estatus.rangoFechasEtiqueta;
    final galpones = estatus.galpones.join(', ');
    final detalle = [
      'Campaña ${estatus.campania}',
      if (rango.isNotEmpty) rango,
      if (galpones.isNotEmpty) 'Galpones $galpones',
    ].where((e) => e.trim().isNotEmpty).join(' · ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(AppColors.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Triángulo de aviso en vez del coronavirus: la tarjeta habla de una
          // granja en situación especial, no de una persona contagiada.
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.warning_amber_rounded, size: 15, color: color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Granja en situación especial · ${estatus.estadoLabel}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                if (detalle.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    detalle,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: context.textThemeMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Indicador informativo de la «Planificación de visitas».
///
/// Pequeño y corto: «✔ Vehículo planificado» en verde o «⚠ Vehículo no
/// planificado» en ámbar (en la fila del DNI, «Planificado» / «No
/// planificado»). Con [compacto] se muestra solo el ícono. Al tocarlo aparece
/// el detalle (fecha, granja). Nunca bloquea nada.
class _AvisoPlan extends StatelessWidget {
  const _AvisoPlan({
    required this.plan,
    required this.sujeto,
    this.etiqueta = '',
    this.compacto = false,
    this.chico = false,
  });

  final _PlanInfo plan;
  final String sujeto;
  final String etiqueta;
  final bool compacto;
  final bool chico;

  void _mostrarDetalle(BuildContext context) {
    final msg = '$sujeto: ${plan.mensaje}';
    if (plan.planificado) {
      showSuccessToast(context, msg);
    } else {
      showWarningToast(context, msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = plan.planificado ? AppColors.success : AppColors.warning;
    final icono = plan.planificado
        ? Icons.check_circle_rounded
        : Icons.warning_amber_rounded;

    if (compacto) {
      return Tooltip(
        message: plan.mensaje,
        child: InkWell(
          onTap: () => _mostrarDetalle(context),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(icono, size: 16, color: color),
          ),
        ),
      );
    }

    return InkWell(
      onTap: () => _mostrarDetalle(context),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: chico ? 0 : 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: chico ? 11 : 13, color: color),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                etiqueta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: chico ? 10 : 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de la visita planificada que coincide con la placa.
///
/// Solo los datos de lo programado en la web —placa, granja, campaña, área o
/// proveedor y motivo—. La lista de personas planificadas no va acá: tiene su
/// propia sección junto a la tabla de DNIs (ver `Planificados`), porque son dos
/// flujos distintos —comprobar lo programado y registrar quién entra— y
/// mezclados en la misma tarjeta se confundían.
///
/// Cuando la visita se eligió en la hoja «Planificadas de hoy» la tarjeta no se
/// dibuja: los datos ya se leyeron completos ahí y el formulario solo se
/// autocompleta.
class _VisitaPlanCard extends StatelessWidget {
  const _VisitaPlanCard({required this.visita});

  final PlanVisita visita;

  /// Renglón «etiqueta · valor» de los datos de la visita. Un dato que la
  /// planificación no pidió se muestra como «—» para que se vea que falta, en
  /// vez de desaparecer y dejar la duda de si la app lo omitió.
  Widget _dato(BuildContext context, String label, String valor) {
    final texto = valor.trim();
    final vacio = texto.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: context.textThemeMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              vacio ? '—' : texto,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.25,
                fontWeight: vacio ? FontWeight.w400 : FontWeight.w700,
                color: vacio ? context.textThemeMuted : context.textThemePrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final granja = [visita.granja, visita.nombreGranja]
        .where((e) => e.trim().isNotEmpty)
        .join(' ');

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
            // Solo la etiqueta del vehículo: el «Planificación: dd/MM HH:mm»
            // (cuándo se bajó la planificación) se quitó del formulario, ver
            // arriba, junto al aviso de «no planificado».
            child: _AvisoPlan(
              plan: _PlanInfo(planificado: true, visita: visita),
              sujeto: 'Vehículo',
              etiqueta: 'Vehículo planificado',
            ),
          ),
          _dato(context, 'Placa', visita.placasTexto.toUpperCase()),
          _dato(context, 'Granja', granja),
          _dato(
            context,
            'Campaña',
            visita.campania.trim().isEmpty
                ? ''
                : GranjaCampaniaPicker.padCampania(visita.campania),
          ),
          // «Proveedor» muestra la razón social del RUC que planificó; si la
          // visita es de un área (sin proveedor) cae al área elegida.
          _dato(
            context,
            'Proveedor',
            visita.razonSocial.isNotEmpty
                ? visita.razonSocial
                : visita.areaProveedorEtiqueta,
          ),
          _dato(context, 'RUC', visita.ruc),
          _dato(context, 'Proceso', visita.proceso),
          _dato(context, 'Motivo de visita/ Obs.', visita.observacion),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

/// Lista de vehículos de la visita planificada: una casilla por vehículo.
///
/// Los muestra todos —también los que la web marcó «no ingresa a la granja»—
/// para poder contrastar lo programado con lo que realmente entró. La casilla se
/// marca sola cuando la placa aparece en el formulario (la bajó la planificación
/// al cargar la visita o la escribió el vigilante) y también se puede tocar a
/// mano: tildar baja la placa al bloque de vehículos, destildar la saca.
class _ListaVehiculosPlan extends StatelessWidget {
  const _ListaVehiculosPlan({required this.vehiculos, required this.onCambiar});

  final List<_VehiculoPlan> vehiculos;
  final void Function(int index, bool marcado) onCambiar;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: context.borderSubtle),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          for (var i = 0; i < vehiculos.length; i++) ...[
            if (i > 0) Divider(height: 1, color: context.borderSubtle),
            _FilaVehiculoPlan(
              vehiculo: vehiculos[i],
              onCambiar: (v) => onCambiar(i, v),
            ),
          ],
        ],
      ),
    );
  }
}

/// Renglón de la lista: casilla, placa, el switch de la web y la situación
/// especial de la placa.
class _FilaVehiculoPlan extends StatelessWidget {
  const _FilaVehiculoPlan({required this.vehiculo, required this.onCambiar});

  final _VehiculoPlan vehiculo;
  final ValueChanged<bool> onCambiar;

  @override
  Widget build(BuildContext context) {
    final marcado = vehiculo.efectivo;
    final placa = vehiculo.placa.toUpperCase();
    return InkWell(
      onTap: () => onCambiar(!marcado),
      child: Padding(
        padding: const EdgeInsets.only(right: 10, top: 4, bottom: 4),
        child: Row(
          children: [
            Checkbox(
              value: marcado,
              onChanged: (v) => onCambiar(v ?? false),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              activeColor: AppColors.primaryDark,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    placa,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: marcado
                          ? context.textThemePrimary
                          : context.textThemeMuted,
                    ),
                  ),
                  const SizedBox(height: 1),
                  // «Planificado» siempre: el renglón sale de la planificación.
                  // El switch de la web («no ingresa») se dice al lado, y la
                  // situación especial solo cuando la placa la tiene.
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _EtiquetasConSlash(
                        items: [
                          (
                            text: _etiquetaPermisoIngresoGranja(vehiculo.ingresa),
                            color: vehiculo.ingresa
                                ? AppColors.success
                                : AppColors.warning,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lista de personas de la visita planificada: una casilla por persona.
///
/// La casilla se marca sola cuando el DNI de esa persona aparece en la tabla
/// (escaneado o escrito completo) y también se puede marcar a mano. Sirve para
/// contrastar la visita planificada con quien realmente llegó.
class _ListaPlanificadas extends StatelessWidget {
  const _ListaPlanificadas({required this.personas, required this.onCambiar});

  final List<_PersonaPlan> personas;
  final void Function(int index, bool marcado) onCambiar;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: context.borderSubtle),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          for (var i = 0; i < personas.length; i++) ...[
            if (i > 0) Divider(height: 1, color: context.borderSubtle),
            _FilaPlanificada(
              persona: personas[i],
              onCambiar: (v) => onCambiar(i, v),
            ),
          ],
        ],
      ),
    );
  }
}

/// Renglón de la lista: casilla, DNI, nombre y de dónde salió la confirmación.
class _FilaPlanificada extends StatelessWidget {
  const _FilaPlanificada({required this.persona, required this.onCambiar});

  final _PersonaPlan persona;
  final ValueChanged<bool> onCambiar;

  @override
  Widget build(BuildContext context) {
    final bloqueada = persona.yaRegistrado;
    final marcada = persona.casillaMarcada;
    return InkWell(
      onTap: bloqueada ? null : () => onCambiar(!marcada),
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Row(
          children: [
            Checkbox(
              value: marcada,
              onChanged: bloqueada ? null : (v) => onCambiar(v ?? false),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              activeColor: AppColors.primaryDark,
            ),
            SizedBox(
              width: 78,
              child: Text(
                persona.dni,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.textThemePrimary,
                ),
              ),
            ),
            Expanded(
              child: Text(
                persona.nombre.isEmpty ? '—' : persona.nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: bloqueada
                      ? context.textThemeMuted
                      : marcada
                          ? context.textThemePrimary
                          : context.textThemeMuted,
                ),
              ),
            ),
            if (bloqueada)
              Tooltip(
                message: 'Ya ingresó en un registro anterior',
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 14,
                  color: context.textThemeMuted,
                ),
              )
            // De dónde salió la confirmación: del toque del vigilante o del DNI
            // leído. Si nadie la confirmó no se muestra nada: la casilla vacía
            // ya lo dice. El toque manda: es lo que el vigilante acaba de hacer.
            else if (persona.marcado)
              Tooltip(
                message: 'Confirmado a mano',
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 14,
                  color: context.textThemeMuted,
                ),
              )
            else if (persona.confirmadaPor != null)
              const Tooltip(
                message: 'Confirmado con el DNI escaneado o escrito',
                child: Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 14,
                  color: AppColors.success,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

