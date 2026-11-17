import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../services/api_service.dart';
import '../services/app_version_service.dart';
import '../services/avisos_ingreso_offline_service.dart';
import '../services/catalog_service.dart';
import '../services/estatus_sanitario_service.dart';
import '../services/ingreso_presencia_service.dart';
import '../services/nomina_proveedor_service.dart';
import '../services/plan_visitas_service.dart';
import '../services/proveedor_historial_service.dart';
import '../services/proveedor_plan_catalog_service.dart';
import '../services/storage_service.dart';
import '../utils/galpones_resolver.dart';
import '../utils/constants.dart';
import '../utils/documento_persona.dart';
import '../utils/documento_scan_flow.dart';
import '../utils/dni_utils.dart';
import '../utils/placa_ocr_parser.dart';
import '../utils/plan_ingreso_helper.dart';
import '../utils/dialog_helper.dart';
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
import '../widgets/bio_scan_tiles.dart';
import '../widgets/placa_input_dialog.dart';
import '../widgets/section_app_bar.dart';
import '../widgets/dismiss_keyboard_scope.dart';
import '../widgets/ingreso_alcoholemia_section.dart';
import '../services/alcoholemia_api_service.dart';
import '../widgets/orden_edad_dialog.dart';
import '../widgets/planificadas_sheet.dart';
import '../widgets/situacion_dialog.dart';
import 'register_summary_screen.dart';
import 'verificacion_facial_screen.dart';

/// Control de ingreso: cuántas personas entran a la granja, en qué vehículo,
/// de qué proveedor y con qué proceso vienen. Los DNIs son opcionales porque en
/// campañas entran grupos grandes y no siempre se pide el documento a todos.
class RegisterControlIngresoScreen extends StatefulWidget {
  const RegisterControlIngresoScreen({super.key});

  @override
  State<RegisterControlIngresoScreen> createState() =>
      _RegisterControlIngresoScreenState();
}

/// Qué hacer con los no planificados al guardar un ingreso planificado.
enum _NoPlanificados { cancelar, incluir, aparte }

/// Estado de la consulta del nombre para un DNI.
/// No hay estado de error a propósito: si la consulta en línea falla y el
/// documento tampoco está en el catálogo local, el nombre queda pendiente y el
/// operador puede escribirlo a mano. Un aviso rojo solo molesta al guardia que
/// está registrando.
enum _DniEstado { vacio, consultando, ok, sinNombre }

/// Resultado informativo de la «Planificación de visitas» del portal web para
/// la placa o para un DNI.
/// Solo informa: el registro se guarda igual esté o no planificado. Cuando no
/// se pudo saber (sin datos descargados para esa fecha y sin red, o la
/// planificación aún no instalada en el servidor) no hay objeto y la pantalla
/// no muestra nada (estado neutro).
class _PlanInfo {
  const _PlanInfo({
    required this.planificado,
    this.visita,
    this.otraGranja,
    this.visitas = const [],
  });

  final bool planificado;

  /// Todas las visitas del día que coinciden (cualquier granja), solo en la
  /// respuesta en línea: con varias, el vigilante marca a cuáles ingresa.
  final List<PlanVisita> visitas;

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
    final todas = item['visitas'];
    return _PlanInfo(
      planificado: item['planificado'] == true,
      visita: visita is Map ? PlanVisita.fromJson(visita) : null,
      otraGranja: otra is Map ? PlanVisita.fromJson(otra) : null,
      visitas: todas is List
          ? todas
                .whereType<Map>()
                .map(PlanVisita.fromJson)
                .where((v) => v.id != 0)
                .toList()
          : const [],
    );
  }
}

/// Fila editable de la tabla de DNIs (un renglón por documento).
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

  /// DNI (normalizado) al que pertenece [plan]; evita borrar el plan en
  /// `onChanged` espurios con el mismo documento.
  String dniPlanificado = '';

  /// Resultado informativo de la planificación (`null` = neutro).
  _PlanInfo? plan;

  /// Estatus sanitario de la persona: `null` = neutro (sin red o sin novedad).
  /// Solo se dibuja cuando [EstatusDni.enRiesgo] es `true`.
  EstatusDni? estatus;

  /// Orden de edad: visitó hoy una granja de mayor edad que la del registro.
  OrdenEdadDni? ordenEdad;

  /// Varias visitas planificadas para este DNI (distintas granjas/ids).
  List<PlanVisita> visitasPlanAmbiguas = const [];

  /// Visitas confirmadas para ingreso (multi-granja); vacío = usar [plan] único.
  Set<int> visitasPlanIdsSeleccionados = {};

  /// Está en salida temporal de un ingreso guardado en el equipo: esta fila es
  /// su regreso (no un ingreso nuevo).
  PresenciaCoincidencia? regreso;

  /// Ya figura dentro (ingreso sin salida): se puede registrar igual (olvido).
  bool yaDentro = false;

  /// `ok` si el servidor validó el rostro; `sin_verificacion_facial` si se
  /// siguió solo con el documento.
  String verificacionFacial = '';
  String empresaFacial = '';

  Timer? debounce;

  bool get esRegreso => regreso != null;

  String get dni => ctrl.text.trim();

  /// Nombre que viaja en el registro: el que resolvió la consulta o, si no
  /// hubo, el que escribió el operador.
  String get nombreEfectivo =>
      nombreDniEfectivo(resuelto: nombre, manual: nombreCtrl.text);

  bool get completo => DocumentoPersona.esCompleto(dni);

  void dispose() {
    debounce?.cancel();
    ctrl.dispose();
    nombreCtrl.dispose();
  }
}

/// Fila editable en «Vehículos que ingresan»: placa a mano o bajada al marcar
/// la planificación. Cada una consulta si está planificada y su situación
/// especial, igual que un DNI en la tabla de personas.
/// Personas (y vehículos) que comparten una misma visita planificada del portal.
class _GrupoIngresoPlan {
  const _GrupoIngresoPlan({
    required this.visita,
    required this.dnis,
    required this.vehiculos,
  });

  final PlanVisita visita;
  final List<_DniFila> dnis;
  final List<_VehiculoFila> vehiculos;
}

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

  OrdenEdadDni? ordenEdad;

  /// Salida temporal pendiente: esta fila es el regreso del vehículo.
  PresenciaCoincidencia? regreso;

  bool yaDentro = false;

  Timer? debounce;

  bool get esRegreso => regreso != null;

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

class _RegisterControlIngresoScreenState
    extends State<RegisterControlIngresoScreen> {
  static const int _largoDocMax = DocumentoPersona.maxLength;

  /// Separación vertical entre campos de un mismo bloque del formulario.
  static const double _sepCampo = 6;

  /// Separación vertical entre bloques del formulario.
  static const double _sepBloque = 10;

  /// Separación horizontal entre dos campos que comparten fila.
  static const double _sepFila = 10;

  final _observacionController = TextEditingController();

  /// Fecha del registro (solo lectura, siempre el día de hoy).
  final DateTime _fecha = DateTime.now();
  String _granja = '';
  String _granjaNombre = '';
  String _campania = '';
  List<String> _campaniasDeGranja = [];
  String _turno = 'Dia';

  String _hora = '';

  /// Proveedor que llega: su RUC (con la razón social consultada) o su nombre
  /// escrito a mano. La web ya no distingue áreas: el registro es de un
  /// proveedor y su proceso.
  ProveedorSeleccion _proveedor = ProveedorSeleccion.vacia;

  /// El operador eligió (o borró) el proveedor: ya no se propone el de la nómina.
  bool _proveedorElegidoAMano = false;

  /// El operador eligió el proceso: ya no se propone el del proveedor.
  bool _procesoElegidoAMano = false;

  /// Proceso del proveedor: una fila de la lista de proveedores del catálogo o
  /// el texto de «Otro». Es el motivo del ingreso que ve el reporte web.
  String _proceso = '';

  final List<String?> _imagenes = [null, null, null];

  final List<_DniFila> _dnis = [];

  /// Placas en «Vehículos que ingresan»: escritas a mano o por escaneo.
  final List<_VehiculoFila> _vehiculos = [];

  /// Visita planificada vinculada al escanear DNI o placa.
  _PlanInfo? _planVisita;

  /// Largo mínimo de placa para consultar la planificación (ABC123 = 6).
  static const int _minPlaca = 5;

  /// Planificación descargada en el equipo (nube del menú lateral) y la hora
  /// de su descarga. Vacía si nunca se descargó: la pantalla funciona como
  /// antes, consultando en línea si hay red.
  PlanDescarga _planLocal = PlanDescarga.vacia;
  DateTime? _planDescargadoEn;

  StorageService? _storage;
  bool _actualizandoPlan = false;
  bool _planForzadoEnPantalla = false;

  /// Estatus sanitario vigente de la granja del registro (`null` = sin novedad).
  EstatusGranja? _estatusGranja;
  Timer? _estatusDebounce;

  int _planCargaActivas = 0;
  Timer? _planCargaTimer;
  void Function()? _cerrarPlanCarga;

  int? _visitaPlanId;

  bool _avisoMultiPlanMostrado = false;

  List<String> _galponOpciones = [];
  List<String> _galponesSel = [];
  bool _galponOtro = false;

  final AlcoholemiaIngresoState _alcoholemia = AlcoholemiaIngresoState();
  final _galponOtroController = TextEditingController();

  /// Último valor que la app escribió sola en «Personas». Mientras el campo
  /// conserve ese valor se mantiene al día con el conteo; si el vigilante lo
  /// cambia, se respeta lo que escribió.

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _cargarGalpones();
    });
    final avisos = AvisosIngresoOfflineService.local(_storage!);
    if (avisos.fecha != _fechaYmd) {
      unawaited(AvisosIngresoOfflineService().descargar(_storage!));
    }
    if (NominaProveedorService.desactualizada(_storage!)) {
      unawaited(_descargarNomina());
    }
  }

  Future<void> _descargarNomina() async {
    final storage = _storage;
    if (storage == null) return;
    final ok = await NominaProveedorService().descargar(storage);
    if (ok && mounted) setState(() {});
  }

  /// Proveedores de la nómina para los DNI del ingreso no planificado.
  List<SugerenciaProveedor> get _sugerenciasProveedor {
    final storage = _storage;
    if (storage == null || !_grupoIngresoNoPlanificado) return const [];
    return NominaProveedorService.local(storage).sugerir([
      for (final d in _dnisIngreso)
        if (d.completo) d.dni,
    ]);
  }

  /// Proveedor propuesto por la nómina cuando el operador aún no eligió uno:
  /// el que agrupa más personas, si no empata con otro.
  SugerenciaProveedor? get _proveedorSugerido {
    if (_proveedorElegidoAMano || !_proveedor.estaVacio) return null;
    final s = _sugerenciasProveedor;
    if (s.isEmpty) return null;
    if (s.length > 1 && s[1].dnis.length == s[0].dnis.length) return null;
    return s.first;
  }

  /// Proveedor que viaja en el registro no planificado.
  ProveedorSeleccion get _proveedorEfectivo =>
      _proveedorSugerido?.proveedor ?? _proveedor;

  /// Proceso propuesto según el proveedor (el único que tiene asignado o el
  /// último con que vino) mientras el operador no elija uno.
  String get _procesoSugerido {
    final storage = _storage;
    if (storage == null || !_grupoIngresoNoPlanificado) return '';
    if (_procesoElegidoAMano || _proceso.trim().isNotEmpty) return '';
    final ruc = _proveedorEfectivo.ruc;
    if (ruc.isEmpty) return '';
    return NominaProveedorService.local(storage).procesoSugerido(ruc);
  }

  String get _procesoEfectivo {
    final s = _procesoSugerido;
    return s.isNotEmpty ? s : _proceso;
  }

  bool get _sinGranjasTrabajoConfiguradas =>
      (_storage?.getGranjasTrabajo() ?? const []).isEmpty;

  /// Ingreso manual: solo granjas de Mis granjas si hay alguna configurada.
  List<String>? get _granjasPermitidasIngresoNoPlanificado {
    final gs = _storage?.getGranjasTrabajo() ?? const [];
    return gs.isEmpty ? null : gs;
  }

  bool _granjaPermitidaParaIngresoManual(String granja) {
    final gs = _granjasPermitidasIngresoNoPlanificado;
    if (gs == null) return true;
    final g = GranjaCampaniaPicker.normGranja(granja);
    if (g.isEmpty) return false;
    return gs.any((e) => GranjaCampaniaPicker.normGranja(e) == g);
  }

  Widget _avisoConfigurarMisGranjas(BuildContext context) {
    if (!_sinGranjasTrabajoConfiguradas) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: _sepCampo),
      child: Material(
        color: context.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: context.textThemeMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Defina sus granjas de trabajo en Mis granjas.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    color: context.textThemeSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
    _planCargaTimer?.cancel();
    _cerrarPlanCarga?.call();
    _cerrarPlanCarga = null;
    _storage?.removeListener(_alCambiarStorage);
    _observacionController.dispose();
    _galponOtroController.dispose();
    super.dispose();
  }

  /// Granja de contexto (formulario, visita única o única en Mis granjas).
  String get _granjaEfectiva {
    if (_granja.trim().isNotEmpty) return _granja.trim();
    final v = _planVisita?.visita;
    if (v != null && v.granja.isNotEmpty) return v.granja;
    final gs = _storage?.getGranjasTrabajo() ?? const [];
    if (gs.length == 1) return gs.first;
    return '';
  }

  /// Granja/campaña para consultar estatus (solo formulario o plan resuelto).
  ({String granja, String campania}) _contextoEstatusSanitario() {
    final visitasFilas = <PlanVisita?>[
      for (final d in _dnis)
        if (d.plan?.planificado == true) d.plan?.visita,
    ];
    final ctx = granjaCampaniaParaEstatusSanitario(
      granjaFormulario: _granja,
      campaniaFormulario: _campania,
      visitaFormularioGlobal: _planVisita?.visita,
      visitasResueltasEnFilas: visitasFilas,
    );
    var campania = ctx.campania;
    if (campania.isNotEmpty) {
      campania = GranjaCampaniaPicker.padCampania(campania);
    }
    return (granja: ctx.granja, campania: campania);
  }

  bool get _variasGranjasMiGranja =>
      (_storage?.getGranjasTrabajo().length ?? 0) > 1;

  /// Visitas del DNI/placa limitadas a Mis granjas del punto.
  List<PlanVisita> _candidatasPlanEnAlcanceMiGranja(List<PlanVisita> visitas) {
    if (visitas.isEmpty) return visitas;
    final granjas = _storage?.getGranjasTrabajo() ?? const [];
    if (granjas.isEmpty) return visitas;
    return visitas.where((v) => granjas.contains(v.granja)).toList();
  }

  Set<int> _planIdsDeFilaDni(_DniFila d) {
    return planVisitaIdsEnFilaDni(
      planificado: d.plan?.planificado == true,
      visitaPlanId: d.plan?.visita?.id,
      visitasPlanIdsSeleccionados: d.visitasPlanIdsSeleccionados,
    );
  }

  void _limpiarVisitasAmbiguasDni(_DniFila fila) {
    fila.visitasPlanAmbiguas = const [];
    fila.visitasPlanIdsSeleccionados = {};
  }

  void _aplicarVisitaElegidaEnFilaDni(_DniFila fila, PlanVisita visita) {
    fila.visitasPlanAmbiguas = const [];
    fila.visitasPlanIdsSeleccionados =
        visita.id != 0 ? {visita.id} : const {};
    fila.plan = _PlanInfo(planificado: true, visita: visita);
    _vincularPlanAlDni(fila);
  }

  void _vincularPlanAlDni(_DniFila fila) {
    if (fila.plan == null) {
      fila.dniPlanificado = '';
      return;
    }
    final d = DocumentoPersona.normalizar(fila.dni);
    fila.dniPlanificado =
        DocumentoPersona.esCompleto(d) ? d : fila.dniPlanificado;
  }

  Future<void> _elegirVisitaPlanParaDni(int index, List<PlanVisita> alcance) async {
    if (index < 0 || index >= _dnis.length) return;
    final fila = _dnis[index];
    final ordenadas = _ordenarCandidatas(alcance, dniReferencia: fila.dni);
    if (ordenadas.isEmpty) {
      if (mounted && identical(_dnis[index], fila)) {
        setState(() {
          _limpiarVisitasAmbiguasDni(fila);
          fila.plan = _PlanInfo(planificado: false, visita: null);
        });
        _sincronizarPlanificacionGlobal();
      }
      return;
    }
    if (ordenadas.length == 1) {
      if (!mounted || !identical(_dnis[index], fila)) return;
      setState(() => _aplicarVisitaElegidaEnFilaDni(fila, ordenadas.first));
      await _vincularVisitaDesdeCoincidencia(
        PlanCoincidencia(visita: ordenadas.first),
        forzar: false,
      );
      return;
    }
    // Varias visitas: se muestran como tarjetas en la pantalla y el vigilante
    // marca a cuáles ingresa. Se conserva lo ya marcado (refresco, respuesta
    // en línea) mientras siga entre las candidatas.
    if (!mounted || !identical(_dnis[index], fila)) return;
    final ids = {for (final v in ordenadas) v.id};
    setState(() {
      fila.visitasPlanAmbiguas = ordenadas;
      fila.visitasPlanIdsSeleccionados = {
        for (final id in fila.visitasPlanIdsSeleccionados)
          if (ids.contains(id)) id,
      };
      fila.plan = _PlanInfo(
        planificado: true,
        visita: _primeraSeleccionada(fila),
      );
    });
    _sincronizarPlanificacionGlobal();
  }

  PlanVisita? _primeraSeleccionada(_DniFila fila) {
    for (final v in fila.visitasPlanAmbiguas) {
      if (fila.visitasPlanIdsSeleccionados.contains(v.id)) return v;
    }
    return null;
  }

  /// Hay algún DNI con varias visitas planificadas hoy.
  bool get _hayVisitasPorElegir =>
      _dnis.any((d) => d.visitasPlanAmbiguas.length > 1);

  /// Visitas candidatas de todas las filas (sin repetir), en orden de aparición.
  List<PlanVisita> get _visitasCandidatas {
    final out = <PlanVisita>[];
    final vistos = <int>{};
    for (final d in _dnis) {
      if (d.visitasPlanAmbiguas.length < 2) continue;
      for (final v in d.visitasPlanAmbiguas) {
        if (vistos.add(v.id)) out.add(v);
      }
    }
    return out;
  }

  bool _visitaMarcada(PlanVisita v) => _dnis.any(
    (d) =>
        d.visitasPlanAmbiguas.any((a) => a.id == v.id) &&
        d.visitasPlanIdsSeleccionados.contains(v.id),
  );

  /// Marca o desmarca una visita en todas las filas que la tienen como opción.
  void _alternarVisitaPlan(PlanVisita visita, bool marcar) {
    setState(() {
      for (final d in _dnis) {
        if (!d.visitasPlanAmbiguas.any((a) => a.id == visita.id)) continue;
        final sel = Set<int>.from(d.visitasPlanIdsSeleccionados);
        if (marcar) {
          sel.add(visita.id);
        } else {
          sel.remove(visita.id);
        }
        d.visitasPlanIdsSeleccionados = sel;
        d.plan = _PlanInfo(planificado: true, visita: _primeraSeleccionada(d));
      }
    });
    _sincronizarPlanificacionGlobal();
    for (var i = 0; i < _vehiculos.length; i++) {
      _consultarPlanVehiculo(i);
    }
    _consultarEstatusSanitario();
  }

  /// Varias visitas en juego para la misma placa (mismo criterio que DNI).
  bool _requiereElegirPlanificacion(List<PlanVisita> alcance) {
    return alcance.length > 1;
  }

  Future<PlanVisita?> _resolverCandidatasPlanificacion(
    List<PlanVisita> candidatas, {
    PlanVisita? preferida,
    String? dniReferencia,
    String tituloSheet = 'Elija granja de visita',
  }) async {
    final alcance = _candidatasPlanEnAlcanceMiGranja(candidatas);
    if (alcance.isEmpty) return preferida;
    if (alcance.length == 1) return alcance.first;
    final ordenadas = _ordenarCandidatas(
      alcance,
      dniReferencia: dniReferencia,
    );
    if (ordenadas.isEmpty) return preferida;
    if (!mounted) return preferida;
    return showPlanificadasSheet(
      context: context,
      visitas: ordenadas,
      fecha: DateFormat('dd/MM/yyyy').format(_fecha),
      titulo: tituloSheet,
    );
  }

  Set<int> _visitasPlanResueltasPorDnis() {
    final ids = <int>{};
    for (final d in _dnis) {
      if (!DocumentoPersona.esCompleto(d.dni)) continue;
      if (d.plan?.planificado != true) continue;
      ids.addAll(_planIdsDeFilaDni(d).where((id) => id != 0));
    }
    return ids;
  }

  PlanCoincidencia? _coincidenciaVehiculoEnCuadrilla(
    String placa,
    Set<int> visitaIds,
  ) {
    for (final id in visitaIds) {
      final visita = _visitaPlanEnFilas(id);
      if (visita == null) continue;
      if (visita.vehiculoDe(placa) != null) {
        return PlanCoincidencia(visita: visita);
      }
    }
    return null;
  }

  Set<String> get _planVisitaIdsUsados =>
      _storage?.getPlanesUsados().toSet() ?? const {};

  List<PlanVisita> _filtrarVisitasNoUsadas(List<PlanVisita> visitas) {
    final usados = _planVisitaIdsUsados;
    if (usados.isEmpty) return visitas;
    return visitas.where((v) => !usados.contains(v.id.toString())).toList();
  }

  PlanCoincidencia _coincidenciaSinPlanesUsados(PlanCoincidencia c) {
    final usados = _planVisitaIdsUsados;
    if (c.visita != null && usados.contains(c.visita!.id.toString())) {
      return PlanCoincidencia(visita: null, otraGranja: c.otraGranja);
    }
    return c;
  }

  bool _planDniYaIngresoEnVisita(
    PlanVisita visita,
    String dni, {
    String? fechaYmd,
  }) {
    final storage = _storage;
    if (storage == null) return false;
    final d = DocumentoPersona.normalizar(dni);
    if (!DocumentoPersona.esCompleto(d)) return false;
    return IngresoPresenciaService.dnisIngresadosEnPlanVisita(
      storage,
      visita.id.toString(),
      fechaYmd: fechaYmd ?? _fechaYmd,
    ).contains(d);
  }

  PlanCoincidencia _coincidenciaSinDniConsumido(
    PlanCoincidencia c,
    String dni,
  ) {
    final v = c.visita;
    if (v != null && _planDniYaIngresoEnVisita(v, dni)) {
      return PlanCoincidencia(visita: null, otraGranja: c.otraGranja);
    }
    return c;
  }

  PlanCoincidencia _coincidenciaEfectiva(
    PlanCoincidencia c, {
    String? dni,
  }) {
    var out = _coincidenciaSinPlanesUsados(c);
    if (dni != null && DocumentoPersona.esCompleto(dni)) {
      out = _coincidenciaSinDniConsumido(out, dni);
    }
    return out;
  }

  _PlanInfo? _planInfoSinPlanesUsados(_PlanInfo? info) {
    if (info == null) return null;
    final v = info.visita;
    if (v != null && _planVisitaIdsUsados.contains(v.id.toString())) {
      return _PlanInfo(
        planificado: false,
        visita: null,
        otraGranja: info.otraGranja,
      );
    }
    return info;
  }

  _PlanInfo? _planInfoEfectiva(_PlanInfo? info, {required String dni}) {
    final base = _planInfoSinPlanesUsados(info);
    if (base == null) return null;
    final v = base.visita;
    if (v != null && _planDniYaIngresoEnVisita(v, dni)) {
      return _PlanInfo(
        planificado: false,
        visita: null,
        otraGranja: base.otraGranja,
      );
    }
    return base;
  }

  List<PlanVisita> _candidatasDniPendientes(String dni, String fecha) {
    final todas = _filtrarVisitasNoUsadas(
      _planLocal.visitasPorDni(dni, granja: '', fechaYmd: fecha),
    );
    final d = DocumentoPersona.normalizar(dni);
    if (!DocumentoPersona.esCompleto(d) || _storage == null) return todas;
    return todas
        .where((v) => !_planDniYaIngresoEnVisita(v, d, fechaYmd: fecha))
        .toList();
  }

  List<PlanVisita> _ordenarCandidatas(
    List<PlanVisita> visitas, {
    String? dniReferencia,
  }) {
    return priorizarVisitasCandidatas(
      visitas,
      granjaFormulario: _granja.trim(),
      granjasTrabajo: _storage?.getGranjasTrabajo() ?? const [],
      dniReferencia: dniReferencia,
      fechaYmd: _fechaYmd,
      storage: _storage,
    );
  }

  bool get _galponPideTextoOtro => _galponOtro || _galponOpciones.isEmpty;

  /// Galpones de la planificación web o elegidos en ingreso no planificado.
  List<String> get _galponPartes {
    final visita = _planVisita?.visita;
    if (visita != null && visita.galpones.isNotEmpty) {
      return List<String>.from(visita.galpones);
    }
    final out = List<String>.from(_galponesSel);
    if (_galponPideTextoOtro) {
      final t = _galponOtroController.text.trim();
      if (t.isNotEmpty) out.add(t);
    }
    return out;
  }

  String get _galponEfectivo => _galponPartes.join(', ');

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
    final storage = _storage;
    if (storage == null) return;
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
      _galponesSel = _galponesSel.where((g) => codigos.contains(g)).toList();
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
    });
    _consultarEstatusSanitario();
    // La planificación depende de la granja y de la fecha: se vuelve a
    // consultar y, si hay red, se actualiza en silencio lo descargado.
    _refrescarPlanificacion();
    if (sel.desdeGranja) _actualizarPlanSilencioso();
    _galponesSel = [];
    _galponOtro = false;
    _galponOtroController.clear();
    _cargarGalpones();
  }

  // Planificación de visitas (solo informativo)
  // Criterio: visitas activas del portal web con la misma fecha del registro y
  // la misma granja (sin granja elegida se busca en todas). La placa se compara
  // sin guiones ni espacios y el DNI por sus 8 dígitos. Nada de esto valida ni
  // bloquea: si la consulta falla, simplemente no se muestra ningún indicador.

  /// Lee la planificación descargada en el equipo.
  void _cargarPlanLocal() {
    final storage = _storage;
    if (storage == null) return;
    _planLocal = PlanVisitasService.local(storage);
    _planDescargadoEn = storage.getPlanVisitasFecha();
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
  /// [forzar]: la consulta en línea trajo visitas que no están en lo
  /// descargado; se baja de nuevo sin esperar los 10 minutos (una vez por
  /// pantalla, para no entrar en un ciclo si el servidor no las incluye).
  Future<void> _actualizarPlanSilencioso({bool forzar = false}) async {
    final storage = _storage;
    if (storage == null || _actualizandoPlan) return;
    if (forzar) {
      if (_planForzadoEnPantalla) return;
      _planForzadoEnPantalla = true;
    } else {
      final ultima = _planDescargadoEn;
      if (ultima != null &&
          DateTime.now().difference(ultima) < const Duration(minutes: 10)) {
        return;
      }
    }
    _actualizandoPlan = true;
    try {
      // Si descarga, el listener de StorageService refresca la pantalla.
      await PlanVisitasService().descargar(storage);
      unawaited(AvisosIngresoOfflineService().descargar(storage));
    } catch (_) {
    } finally {
      _actualizandoPlan = false;
    }
  }

  /// Tirar hacia abajo: vuelve a bajar la planificación y rehace la pantalla con
  /// lo nuevo, sin salir del formulario.
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
      final avisos = AvisosIngresoOfflineService().descargar(storage);
      final nomina = NominaProveedorService().descargar(storage);
      ok = await PlanVisitasService().descargar(storage);
      await avisos;
      await nomina;
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

  PlanIngresoFormState get _planForm => PlanIngresoFormState(
        planVisita: _planVisita?.visita,
        visitaPlanId: _visitaPlanId,
        proveedor: _proveedor,
        proceso: _proceso,
        observacion: _observacionController.text,
      );

  void _aplicarPlanForm(PlanIngresoFormState f) {
    _planVisita = f.planVisita != null
        ? _PlanInfo(planificado: true, visita: f.planVisita)
        : _planVisita;
    _visitaPlanId = f.visitaPlanId;
    _proveedor = f.proveedor;
    _proceso = f.proceso;
    if (f.observacion != _observacionController.text) {
      _observacionController.text = f.observacion;
    }
  }

  Future<void> _vincularVisitaDesdeCoincidencia(
    PlanCoincidencia c, {
    bool forzar = false,
  }) async {
    if (!mounted || c.visita == null) return;
    final visita = c.visita!;

    // Varios grupos planificados: cada DNI/placa conserva su visita y su ficha.
    if (_idsPlanVisitaEnFilas().length > 1) {
      _sincronizarPlanificacionGlobal();
      return;
    }

    // Misma sesión, otra visita en el formulario global: no reemplazar; sincronizar.
    if (!forzar &&
        _visitaPlanId != null &&
        _visitaPlanId != visita.id &&
        _visitaPlanId != 0) {
      _sincronizarPlanificacionGlobal();
      return;
    }

    if (!mounted) return;
    setState(() {
      final form = _planForm;
      vincularVisitaDesdeCoincidencia(
        form: form,
        coincidencia: c,
        forzar: forzar,
      );
      _aplicarPlanForm(form);
      _planVisita = _PlanInfo(planificado: true, visita: visita);
      _aplicarUbicacionDesdeVisita(visita);
    });
    _sincronizarPlanificacionGlobal();
    _consultarEstatusSanitario();
  }

  /// Granja y campaña de la visita planificada (sin obligar a elegirlas antes del escaneo).
  void _aplicarUbicacionDesdeVisita(PlanVisita visita) {
    if (visita.granja.isEmpty) return;
    final storage = _storage;
    if (storage == null) return;

    final sel = GranjaCampaniaPicker.seleccionDeGranja(
      proyeccion: storage.getProyeccion(),
      cencosGalpones: storage.getCencosGalpones(),
      granja3: visita.granja,
      fechaYmd: _fechaYmd,
    );

    final campanias = sel != null
        ? ((sel['campanias'] as List?) ?? [])
            .map((e) => e.toString())
            .toList()
        : <String>[];

    var camp = visita.campania.trim().isNotEmpty
        ? GranjaCampaniaPicker.padCampania(visita.campania)
        : '';
    if (camp.isEmpty && sel != null) {
      camp = (sel['campania'] ?? '').toString();
    }
    if (camp.isEmpty && campanias.length == 1) {
      camp = campanias.first;
    }

    _granja = visita.granja;
    _granjaNombre = visita.nombreGranja.trim().isNotEmpty
        ? visita.nombreGranja.trim()
        : (sel?['granjaNombre'] ?? '').toString();
    if (camp.isNotEmpty) _campania = camp;
    if (campanias.isNotEmpty) _campaniasDeGranja = campanias;

  }

  /// Filas que son un ingreso nuevo (no el regreso de una salida temporal).
  Iterable<_DniFila> get _dnisIngreso => _dnis.where((d) => !d.esRegreso);

  Iterable<_VehiculoFila> get _vehiculosIngreso =>
      _vehiculos.where((v) => !v.esRegreso);

  List<_DniFila> get _dnisRegreso => [
    for (final d in _dnis)
      if (d.esRegreso && d.completo) d,
  ];

  List<_VehiculoFila> get _vehiculosRegreso => [
    for (final v in _vehiculos)
      if (v.esRegreso && v.escrita) v,
  ];

  bool get _hayRegresos =>
      _dnisRegreso.isNotEmpty || _vehiculosRegreso.isNotEmpty;

  bool get _hayElementosIngreso =>
      _dnisIngreso.any((d) => d.dni.isNotEmpty) ||
      _vehiculosIngreso.any((v) => v.placaNorm.length >= _minPlaca);

  /// Hay al menos una visita planificada en las filas escaneadas (fuente de verdad).
  bool get _algunEscaneadoPlanificado =>
      _gruposIngresoPorPlanificacion().isNotEmpty;

  /// Una sola planificación activa en el grupo (no multi-ficha).
  bool get _visitaPlanificadaActiva =>
      !_hayIngresoMultiPlanificacion &&
      _gruposIngresoPorPlanificacion().length == 1;

  /// Planificación ya consultada para cada identificador completo del grupo.
  bool get _planificacionResueltaParaGrupo {
    for (final d in _dnisIngreso) {
      if (!DocumentoPersona.esCompleto(d.dni)) continue;
      if (d.visitasPlanAmbiguas.length > 1 &&
          d.visitasPlanIdsSeleccionados.isEmpty) {
        return false;
      }
      if (d.plan == null) return false;
    }
    for (final v in _vehiculosIngreso) {
      if (v.placaNorm.length >= _minPlaca && v.plan == null) return false;
    }
    return true;
  }

  /// Ingreso «libre» solo si nadie del grupo está planificado aquí.
  bool get _grupoIngresoNoPlanificado {
    if (!_hayElementosIngreso) return false;
    if (_algunEscaneadoPlanificado) return false;
    if (!_planificacionResueltaParaGrupo) return false;
    return _dnisIngreso.any((d) => DocumentoPersona.esCompleto(d.dni)) ||
        _vehiculosIngreso.any((v) => v.placaNorm.length >= _minPlaca);
  }

  /// Formulario listo en pantalla principal (sin ficha intermedia).
  bool get _puedeConfirmarEnPantalla {
    if (!_hayElementosIngreso) return _hayRegresos;
    return _planificacionResueltaParaGrupo &&
        (_grupoIngresoNoPlanificado ||
            _visitaPlanificadaActiva ||
            _hayIngresoMultiPlanificacion);
  }

  Set<int> _idsPlanVisitaEnFilas() {
    final ids = <int>{};
    for (final d in _dnisIngreso) {
      if (!DocumentoPersona.esCompleto(d.dni)) continue;
      if (d.plan?.planificado != true) continue;
      ids.addAll(_planIdsDeFilaDni(d));
    }
    for (final ve in _vehiculosIngreso) {
      if (!ve.escrita) continue;
      final v = ve.plan?.visita;
      if (ve.plan?.planificado == true && v != null && v.id != 0) {
        ids.add(v.id);
      }
    }
    return ids;
  }

  bool get _hayIngresoMultiPlanificacion => _idsPlanVisitaEnFilas().length > 1;

  PlanVisita? _visitaPlanEnFilas(int planVisitaId) {
    for (final d in _dnis) {
      final v = d.plan?.visita;
      if (v != null && v.id == planVisitaId) return v;
      for (final a in d.visitasPlanAmbiguas) {
        if (a.id == planVisitaId) return a;
      }
    }
    for (final ve in _vehiculos) {
      final v = ve.plan?.visita;
      if (v != null && v.id == planVisitaId) return v;
    }
    return _planLocal.visitaPorId(planVisitaId);
  }

  List<_GrupoIngresoPlan> _gruposIngresoPorPlanificacion() {
    final dnisPorId = <int, List<_DniFila>>{};
    for (final d in _dnisIngreso) {
      if (!DocumentoPersona.esCompleto(d.dni)) continue;
      if (d.plan?.planificado != true) continue;
      for (final id in _planIdsDeFilaDni(d)) {
        dnisPorId.putIfAbsent(id, () => []).add(d);
      }
    }
    final vehPorId = <int, List<_VehiculoFila>>{};
    for (final ve in _vehiculosIngreso) {
      if (!ve.escrita) continue;
      final v = ve.plan?.visita;
      if (ve.plan?.planificado != true || v == null || v.id == 0) continue;
      vehPorId.putIfAbsent(v.id, () => []).add(ve);
    }
    final ids = {...dnisPorId.keys, ...vehPorId.keys};
    final out = <_GrupoIngresoPlan>[];
    for (final id in ids) {
      final visita = _visitaPlanEnFilas(id);
      if (visita == null) continue;
      out.add(
        _GrupoIngresoPlan(
          visita: visita,
          dnis: dnisPorId[id] ?? const [],
          vehiculos: vehPorId[id] ?? const [],
        ),
      );
    }
    out.sort((a, b) => a.visita.id.compareTo(b.visita.id));
    return out;
  }

  void _sincronizarPlanificacionGlobal() {
    final grupos = _gruposIngresoPorPlanificacion();
    if (grupos.isEmpty) {
    setState(() {
        _planVisita = null;
        _visitaPlanId = null;
      });
      return;
    }
    if (grupos.length == 1) {
      final visita = grupos.first.visita;
      setState(() {
        final form = _planForm;
        form.visitaPlanId = null;
        vincularVisitaPlanEnFormulario(form: form, visita: visita);
        _aplicarPlanForm(form);
        _planVisita = _PlanInfo(planificado: true, visita: visita);
        _aplicarUbicacionDesdeVisita(visita);
        if (visita.galpones.isNotEmpty) {
          _galponesSel = List<String>.from(visita.galpones);
          _galponOtro = false;
          _galponOtroController.clear();
        }
      });
      if (visita.galpones.isEmpty) _cargarGalpones();
    _consultarEstatusSanitario();
      return;
    }
    if (grupos.length > 1) {
      setState(() {
        _planVisita = null;
        _visitaPlanId = null;
      });
      if (!_avisoMultiPlanMostrado && mounted) {
        _avisoMultiPlanMostrado = true;
      }
    }
  }

  void _avisarSiDniYaIngresoEnPlan(String dni) {
    final planId = _planVisita?.visita?.id ?? _visitaPlanId;
    final storage = _storage;
    if (planId == null || planId == 0 || storage == null) return;
    final ya = IngresoPresenciaService.dnisIngresadosEnPlanVisita(
      storage,
      planId.toString(),
      fechaYmd: _fechaYmd,
    );
    if (ya.contains(dni)) {
      showInfoToast(
        context,
        'Este DNI ya figura en un ingreso de hoy para esta visita planificada.',
      );
    }
  }

  /* ── Vehículos adicionales (multi-vehículo) ────────────────────────────── */

  /// Agrega un vehículo extra (placa) al registro.
  void _agregarVehiculo() {
    setState(() => _vehiculos.add(_VehiculoFila()));
  }

  Future<void> _escanearPlacaNueva() async {
    final placa = await PlacaInputDialog.capture(context);
    if (placa == null || !mounted) return;
    if (!await _evaluarPresenciaTrasEscaneo(placaNorm: placa)) return;
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _trasEscaneoPlaca(placa);
    });
  }

  void _agregarPlacaAlFormulario(String placaNorm) {
    final legible = PlacaOcrParser.paraCampo(placaNorm);
    final clave = PlanDescarga.normPlaca(legible);
    final existente = _vehiculos.indexWhere((v) => v.placaNorm == clave);
    if (existente >= 0) {
      setState(() => _vehiculos[existente].ctrl.text = legible);
      _consultarPlanVehiculo(existente);
        return;
      }
    setState(() {
    final fila = _VehiculoFila();
      fila.ctrl.text = legible;
    _vehiculos.add(fila);
    });
    _consultarPlanVehiculo(_vehiculos.length - 1);
  }

  void _trasEscaneoPlaca(String placa) {
    if (!mounted) return;
    _agregarPlacaAlFormulario(placa);
  }

  void _quitarVehiculo(int index) {
    if (index < 0 || index >= _vehiculos.length) return;
    setState(() {
      _quitarFilaDeVehiculos(_vehiculos[index]);
    });
    _sincronizarPlanificacionGlobal();
    _consultarEstatusSanitario();
  }

  void _quitarFilaDeVehiculos(_VehiculoFila fila) {
    final index = _vehiculos.indexOf(fila);
    if (index < 0) return;
    fila.debounce?.cancel();
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
    final granja = _granjaEfectiva;
    final fecha = _fechaYmd;
    if (placa.length < _minPlaca) {
      if (mounted) {
        setState(() {
            fila.plan = null;
            fila.ingresaPlan = null;
            fila.regreso = null;
            fila.yaDentro = false;
        });
        _sincronizarPlanificacionGlobal();
      }
      _consultarEstatusSanitario();
      return;
    }
    if (_marcarPresenciaVehiculo(fila)) {
      _sincronizarPlanificacionGlobal();
      _consultarEstatusSanitario();
      return;
    }
    final visitasCuadrilla = _visitasPlanResueltasPorDnis();
    if (visitasCuadrilla.isNotEmpty) {
      final enCuadrilla = _coincidenciaVehiculoEnCuadrilla(placa, visitasCuadrilla);
      if (mounted && identical(_vehiculos[index], fila)) {
        setState(() {
          if (enCuadrilla?.visita != null) {
            final veh = enCuadrilla!.visita!.vehiculoDe(fila.ctrl.text);
            fila.plan = _PlanInfo.deLocal(enCuadrilla);
            fila.ingresaPlan = veh?.ingresa;
          } else {
            fila.plan = const _PlanInfo(planificado: false, visita: null);
            fila.ingresaPlan = null;
          }
        });
        _sincronizarPlanificacionGlobal();
      }
      _consultarEstatusSanitario();
      return;
    }
    if (_planLocal.cubre(fecha)) {
      var c = _coincidenciaSinPlanesUsados(
        _planLocal.buscarPlaca(placa, granja: granja, fechaYmd: fecha),
      );
      final candidatas = _filtrarVisitasNoUsadas(
        _planLocal.visitasPorPlaca(placa, granja: '', fechaYmd: fecha),
      );
      final alcance = _candidatasPlanEnAlcanceMiGranja(candidatas);
      if (alcance.length == 1) {
        c = PlanCoincidencia(visita: alcance.first);
      } else if (_requiereElegirPlanificacion(alcance)) {
        final elegida = await _resolverCandidatasPlanificacion(
          candidatas,
          preferida: c.visita,
        );
        if (elegida != null) {
          c = PlanCoincidencia(visita: elegida);
        }
      } else if (alcance.isNotEmpty) {
        c = PlanCoincidencia(
          visita: _ordenarCandidatas(alcance).first,
        );
      }
      final veh = c.visita?.vehiculoDe(fila.ctrl.text);
      if (mounted && identical(_vehiculos[index], fila)) {
        setState(() {
            fila.plan = _PlanInfo.deLocal(c);
          fila.ingresaPlan = veh?.ingresa ?? fila.ingresaPlan;
        });
        if (c.planificado && c.visita != null) {
          await _vincularVisitaDesdeCoincidencia(
            c,
            forzar: _requiereElegirPlanificacion(alcance),
          );
        } else {
          _sincronizarPlanificacionGlobal();
        }
      }
    }
    final granjaAntes = _granja;
    final res = await ApiService().consultarPlanificacion(
      fechaYmd: fecha,
      granja: granja,
      placa: placa,
    );
    if (!mounted ||
        index >= _vehiculos.length ||
        !identical(_vehiculos[index], fila) ||
        fila.placaNorm != placa ||
        _fechaYmd != fecha) {
      return;
    }
    if (_granja != granjaAntes) {
      _consultarEstatusSanitario();
      return;
    }
    final enLinea = _planInfoSinPlanesUsados(_PlanInfo.desde(res?['placa']));
    // Si lo descargado ya resolvió la visita (quizá elegida entre varias), la
    // respuesta en línea no la reemplaza.
    final yaResuelta = fila.plan?.planificado == true && fila.plan?.visita != null;
    if (enLinea != null &&
        (!yaResuelta || enLinea.visita?.id == fila.plan?.visita?.id)) {
      final veh = enLinea.visita?.vehiculoDe(fila.ctrl.text);
      setState(() {
          fila.plan = enLinea;
        fila.ingresaPlan = veh?.ingresa ?? fila.ingresaPlan;
      });
      if (enLinea.planificado && enLinea.visita != null) {
        await _vincularVisitaDesdeCoincidencia(
          PlanCoincidencia(visita: enLinea.visita, otraGranja: enLinea.otraGranja),
        );
      } else if (mounted) {
        _sincronizarPlanificacionGlobal();
      }
    } else if (mounted) {
      if (fila.plan == null) {
        setState(
          () => fila.plan = const _PlanInfo(planificado: false, visita: null),
        );
      }
      _sincronizarPlanificacionGlobal();
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
  List<Map<String, dynamic>> _vehiculosRegistroDe(Iterable<_VehiculoFila> filas) {
    final out = <Map<String, dynamic>>[];
    for (final v in filas) {
      final t = v.placa.trim().toUpperCase();
      if (t.isEmpty || out.any((e) => e['placa'] == t)) continue;
      final ingresa =
          v.ingresaPlan ?? v.plan?.visita?.vehiculoDe(v.ctrl.text)?.ingresa;
      out.add({'placa': t, 'ingresa': ingresa == false ? 0 : 1});
    }
    return out;
  }

  void _quitarFilaDeDnis(_DniFila fila) {
    final index = _dnis.indexWhere((d) => identical(d, fila));
    if (index < 0) return;
    fila.debounce?.cancel();
    _dnis.removeAt(index);
    fila.dispose();
  }

  void _iniciarCargaPlanificacion() {
    _planCargaActivas++;
    if (_planCargaActivas != 1) return;
    _planCargaTimer?.cancel();
    _planCargaTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || _planCargaActivas < 1 || _cerrarPlanCarga != null) {
        return;
      }
      _cerrarPlanCarga = showChickenLoadingDialog(
        context,
        'Consultando planificación…',
      );
    });
  }

  Future<void> _finalizarCargaPlanificacion() async {
    if (_planCargaActivas <= 0) return;
    _planCargaActivas--;
    if (_planCargaActivas > 0) return;
    _planCargaTimer?.cancel();
    _planCargaTimer = null;
    final close = _cerrarPlanCarga;
    _cerrarPlanCarga = null;
    if (close != null) {
      await dismissLoadingDialog(close);
    }
  }

  /// Planificación del DNI de una fila: primero lo descargado y, si hay red,
  /// la confirmación en línea.
  Future<void> _consultarPlanDni(int index) async {
    if (index < 0 || index >= _dnis.length) return;
    final fila = _dnis[index];
    final dni = fila.dni;
    if (!DocumentoPersona.esCompleto(dni)) return;
    if (_marcarPresenciaDni(fila)) {
      _sincronizarPlanificacionGlobal();
      _consultarEstatusSanitario();
      return;
    }
    _iniciarCargaPlanificacion();
  try {
    final granja = _granjaEfectiva;
    final fecha = _fechaYmd;
    if (_planLocal.cubre(fecha)) {
      var c = _coincidenciaEfectiva(
            _planLocal.buscarDni(dni, granja: granja, fechaYmd: fecha),
        dni: dni,
      );
      final candidatas = _candidatasDniPendientes(dni, fecha);
      final alcance = _candidatasPlanEnAlcanceMiGranja(candidatas);
      if (mounted && identical(_dnis[index], fila)) {
        if (alcance.length > 1) {
          await _elegirVisitaPlanParaDni(index, alcance);
        } else if (alcance.length == 1) {
          c = PlanCoincidencia(visita: alcance.first);
          setState(() {
            _limpiarVisitasAmbiguasDni(fila);
            fila.visitasPlanIdsSeleccionados = {alcance.first.id};
            fila.plan = _PlanInfo.deLocal(c);
          });
          if (c.planificado && c.visita != null) {
            await _vincularVisitaDesdeCoincidencia(c, forzar: false);
          } else {
            _sincronizarPlanificacionGlobal();
          }
        } else {
          setState(() {
            _limpiarVisitasAmbiguasDni(fila);
            fila.plan = _PlanInfo.deLocal(c);
          });
          _sincronizarPlanificacionGlobal();
        }
      }
    }
    // Lo descargado pudo fijar la granja al vincular la visita: la respuesta
    // en línea solo se descarta si la granja cambia durante la consulta.
    final granjaAntes = _granja;
    final res = await ApiService().consultarPlanificacion(
      fechaYmd: fecha,
      granja: granja,
      dnis: [dni],
    );
    if (!mounted || _fechaYmd != fecha) return;
    if (!_dnis.any((d) => identical(d, fila)) || fila.dni != dni) return;
    if (_granja != granjaAntes) {
      _consultarEstatusSanitario();
      return;
    }
    final porDni = res?['dnis'];
    final crudo = _PlanInfo.desde(porDni is Map ? porDni[dni] : null);
    final enLinea = _planInfoEfectiva(crudo, dni: dni);
    final alcanceEnLinea = _candidatasPlanEnAlcanceMiGranja(
      _filtrarVisitasNoUsadas(crudo?.visitas ?? const [])
          .where((v) => !_planDniYaIngresoEnVisita(v, dni, fechaYmd: fecha))
          .toList(),
    );
    if (alcanceEnLinea.length > 1 ||
        (alcanceEnLinea.length == 1 && fila.visitasPlanAmbiguas.length > 1)) {
      // Varias visitas en línea (o lo descargado ya tenía varias): todas las
      // candidatas van a las tarjetas, sin perder las de lo descargado.
      final union = <int, PlanVisita>{
        for (final v in fila.visitasPlanAmbiguas) v.id: v,
        for (final v in alcanceEnLinea) v.id: v,
      };
      await _elegirVisitaPlanParaDni(index, union.values.toList());
      if (alcanceEnLinea.any((v) => _planLocal.visitaPorId(v.id) == null)) {
        // Lo descargado no tiene alguna de esas visitas: se baja de nuevo para
        // que también estén sin señal.
        _actualizarPlanSilencioso(forzar: true);
      }
    } else if (enLinea != null && fila.visitasPlanAmbiguas.length <= 1) {
      final yaResuelta = fila.plan?.planificado == true &&
          (fila.plan?.visita != null ||
              fila.visitasPlanIdsSeleccionados.isNotEmpty);
      final mismoId = enLinea.visita != null &&
          fila.plan?.visita != null &&
          enLinea.visita!.id == fila.plan!.visita!.id;
      final puedeActualizar = !yaResuelta ||
          mismoId ||
          (enLinea.planificado && enLinea.visita != null);
      if (puedeActualizar) {
        setState(() {
          if (enLinea.planificado && enLinea.visita != null) {
            _limpiarVisitasAmbiguasDni(fila);
            fila.visitasPlanIdsSeleccionados = {enLinea.visita!.id};
          }
          if (!enLinea.planificado && yaResuelta) {
            // Respuesta en línea vacía: se conserva lo descargado / ya elegido.
          } else {
            fila.plan = enLinea;
            _vincularPlanAlDni(fila);
          }
        });
        if (enLinea.planificado && enLinea.visita != null) {
          await _vincularVisitaDesdeCoincidencia(
            PlanCoincidencia(
              visita: enLinea.visita,
              otraGranja: enLinea.otraGranja,
            ),
          );
        } else if (mounted && !yaResuelta) {
          _sincronizarPlanificacionGlobal();
        }
      }
    } else if (mounted) {
      if (fila.plan == null && fila.visitasPlanAmbiguas.isEmpty) {
        // Sin señal y sin nada descargado para hoy: no figura en lo que hay.
        setState(
          () => fila.plan = const _PlanInfo(planificado: false, visita: null),
        );
      }
      _sincronizarPlanificacionGlobal();
    }
    if (fila.plan != null) _vincularPlanAlDni(fila);
    if (fila.estado == _DniEstado.sinNombre) _completarNombreDesdePlan(fila);
    _avisarSiDniYaIngresoEnPlan(dni);
    _consultarEstatusSanitario();
  } finally {
    await _finalizarCargaPlanificacion();
  }
  }

  /// Tras cambiar granja, fecha o lo descargado: se vuelve a evaluar todo.
  void _refrescarPlanificacion({bool forzar = false}) {
    setState(() {
      for (final d in _dnis) {
        final ambiguas = List<PlanVisita>.from(d.visitasPlanAmbiguas);
        final idsSel = Set<int>.from(d.visitasPlanIdsSeleccionados);
        d.plan = null;
        d.dniPlanificado = '';
        d.estatus = null;
        d.ordenEdad = null;
        // Lo marcado en las tarjetas se conserva: al volver a evaluar se
        // queda con las visitas que sigan siendo candidatas.
        d.visitasPlanAmbiguas = ambiguas;
        d.visitasPlanIdsSeleccionados = idsSel;
      }
      for (final v in _vehiculos) {
        v.plan = null;
        v.estatus = null;
        v.ordenEdad = null;
      }
    });
    for (var i = 0; i < _dnis.length; i++) {
      _consultarPlanDni(i);
    }
    for (var i = 0; i < _vehiculos.length; i++) {
      _consultarPlanVehiculo(i);
    }
    _consultarEstatusSanitario();
  }

  // Estatus sanitario por granja (solo informativo)
  // Mientras una granja esté en sospecha o confirmado, quien haya ingresado a
  // ella lleva la etiqueta de situación especial al entrar a otra. La consulta
  // es puntual y silenciosa: si falla, no hay etiqueta y el registro sigue.

  /// Consulta el estatus de la granja y de los DNIs escritos en la tabla.
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
    final ctx = _contextoEstatusSanitario();
    final granja = ctx.granja;
    final campania = ctx.campania;
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
    final enLinea = await EstatusSanitarioService().consultar(
      fechaYmd: fecha,
      granja: granja,
      campania: campania,
      dnis: dnis,
      placas: placas,
    );
    if (!mounted) return;
    if (_fechaYmd != fecha) {
      return;
    }
    // Sin señal: se calcula con el catálogo descargado y los ingresos del equipo.
    final res = enLinea ?? AvisosIngresoOfflineService.calcular(
      storage: _storage!,
      fechaYmd: fecha,
      granja: granja,
      campania: campania,
      dnis: dnis,
      placas: placas,
    );
    if (res == null) return;
    setState(() {
      _estatusGranja = granja.isEmpty ? null : res.granjaEnEstatus;
      final oe = res.ordenEdad;
      for (final d in _dnis) {
        final e = estatusSanitarioDeDocumento(res.dnis, d.dni);
        d.estatus = (e != null && e.enRiesgo) ? e : null;
        d.ordenEdad = _enRiesgoOrdenEdad(
          ordenEdadDeDocumento(oe?.dnis ?? const {}, d.dni),
        );
      }
      for (final v in _vehiculos) {
        final placa = PlanDescarga.normPlaca(v.ctrl.text);
        v.estatus = _enRiesgo(res.placas[placa]);
        v.ordenEdad = _enRiesgoOrdenEdad(oe?.placas[placa]);
      }
    });
  }

  /// El estatus solo se dibuja cuando [EstatusDni.enRiesgo] es `true`.
  static EstatusDni? _enRiesgo(EstatusDni? e) =>
      (e != null && e.enRiesgo) ? e : null;

  static OrdenEdadDni? _enRiesgoOrdenEdad(OrdenEdadDni? e) =>
      (e != null && e.enRiesgo) ? e : null;

  int _conteoIngresan() {
    final vistos = <String>{};
    for (final d in _dnisIngreso) {
      if (d.completo) vistos.add(d.dni);
    }
    return vistos.length;
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
    final storage = _storage!;
    final historial = ProveedorHistorialService(storage);
    final catalogo = ProveedorPlanCatalogService(storage);
    final sel = await showProveedorDialog(
      context: context,
      actual: _proveedor,
      buscarProveedorLocal: (q) => fusionarBusquedaLocal(
        historial.buscar(q),
        catalogo.buscar(q),
      ),
      buscarProveedorCcte: (q) => api.buscarProveedorCcte(q),
      consultarRuc: (ruc) => api.consultarRuc(ruc),
    );
    if (sel == null) return;
    if (!sel.estaVacio) {
      unawaited(historial.registrar(sel, fuente: 'manual'));
    }
    setState(() {
      _proveedor = sel;
      _proveedorElegidoAMano = true;
    });
  }

  void _elegirProveedorSugerido(SugerenciaProveedor s) {
    setState(() {
      _proveedor = s.proveedor;
      _proveedorElegidoAMano = true;
    });
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
    setState(() {
      _proceso = sel;
      _procesoElegidoAMano = true;
    });
  }

  void _elegirProcesoSugerido(String proceso) {
    setState(() {
      _proceso = proceso;
      _procesoElegidoAMano = true;
    });
  }

  /// Agrega un renglón vacío para escribir un DNI.
  void _agregarDni() {
    setState(() => _dnis.add(_DniFila()));
  }

  void _quitarDni(int index) {
    setState(() => _quitarFilaDeDnis(_dnis[index]));
    _sincronizarPlanificacionGlobal();
  }

  /// Consulta el nombre del documento de una fila.
  /// El token de la API vive en el servidor, así que la app solo manda los 8
  /// dígitos. Primero se intenta en línea; si eso falla (sin red, red lenta o
  /// error desconocido) se cae al catálogo local de usuarios, donde `libtri`
  /// guarda el DNI. Si la fila se eliminó mientras viajaba la respuesta, se
  /// descarta.
  Future<void> _consultarNombre(int index) async {
    if (index < 0 || index >= _dnis.length) return;
    final fila = _dnis[index];
    final dni = fila.dni;
    if (!DocumentoPersona.esCompleto(dni)) return;
    if (fila.consultado == dni && fila.estado == _DniEstado.ok) return;

    // Se lee antes del await: el catálogo en memoria no cambia mientras tanto y
    // así el contexto no se usa después de un hueco asíncrono.
    final catalogo = context.read<CatalogService>();

    // La segunda barrera va primero: si el DNI está entre los usuarios
    // descargados el nombre aparece al instante, sin esperar a la red, y la
    // consulta en línea solo lo confirma (o lo corrige).
    var delCatalogo = catalogo.nombrePorDni(dni);
    if (delCatalogo.isEmpty) delCatalogo = _nombreDesdePlanificacion(fila);
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
    _completarNombreDesdePlan(fila);
  }

  /// Nombre de la persona según la planificación (lo descargado o lo que trajo
  /// la consulta en línea). Vacío si la web no lo registró.
  String _nombreDesdePlanificacion(_DniFila fila) {
    final dni = DocumentoPersona.normalizar(fila.dni);
    if (dni.isEmpty) return '';
    final visitas = <PlanVisita>[
      if (fila.plan?.visita != null) fila.plan!.visita!,
      ...fila.visitasPlanAmbiguas,
      ..._planLocal.visitasPorDni(dni, granja: '', fechaYmd: _fechaYmd),
    ];
    for (final v in visitas) {
      for (final p in v.personas) {
        if (p.dni == dni && p.nombre.trim().isNotEmpty) return p.nombre.trim();
      }
    }
    return '';
  }

  /// Si el nombre quedó pendiente y la planificación lo trae, se completa.
  void _completarNombreDesdePlan(_DniFila fila) {
    if (fila.estado != _DniEstado.sinNombre &&
        fila.estado != _DniEstado.consultando) {
      return;
    }
    final nombre = _nombreDesdePlanificacion(fila);
    if (nombre.isEmpty) return;
    setState(() {
      fila.nombre = nombre;
      fila.estado = _DniEstado.ok;
    });
  }

  /// Al escribir: se descarta el nombre anterior y, con los 8 dígitos, se
  /// consulta solo (con una pausa para no llamar en cada tecla).
  void _alCambiarDni(int index) {
    if (index >= _dnis.length) return;
    final fila = _dnis[index];
    fila.debounce?.cancel();
    final valor = fila.dni;
    final norm = DocumentoPersona.normalizar(valor);
    final mismoDniPlan =
        fila.dniPlanificado.isNotEmpty && norm == fila.dniPlanificado;

    // Solo si cambió el documento se descarta planificación / estatus del anterior.
    if (!mismoDniPlan &&
        (fila.plan != null ||
            fila.estatus != null ||
            fila.ordenEdad != null ||
            fila.regreso != null ||
            fila.yaDentro ||
            fila.visitasPlanAmbiguas.isNotEmpty)) {
      setState(() {
        fila.plan = null;
        fila.dniPlanificado = '';
        fila.estatus = null;
        fila.ordenEdad = null;
        fila.regreso = null;
        fila.yaDentro = false;
        _limpiarVisitasAmbiguasDni(fila);
      });
      _sincronizarPlanificacionGlobal();
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

    if (fila.completo && !mismoDniPlan) {
      fila.debounce = Timer(const Duration(milliseconds: 450), () {
        _consultarNombre(index);
        _consultarPlanDni(index);
        _consultarEstatusSanitario();
      });
    }
  }

  /// Abre el escáner y coloca el documento leído en la fila indicada.
  Future<void> _escanearEnFila(int index) async {
    final dni = await escanearDocumentoPersona(context);
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
      fila.dniPlanificado = '';
      fila.estatus = null;
      fila.ordenEdad = null;
      fila.regreso = null;
      fila.yaDentro = false;
      _limpiarVisitasAmbiguasDni(fila);
    });
    _sincronizarPlanificacionGlobal();
    _consultarPlanDni(index);
    await _consultarNombre(index);
    _consultarEstatusSanitario();
  }

  /// Avisos informativos de presencia; no bloquea el ingreso (olvido de registro).
  Future<bool> _evaluarPresenciaTrasEscaneo({
    String? dni,
    String? placaNorm,
  }) async {
    // La presencia (regreso / ya dentro) se marca en la fila al consultarla.
    return true;
  }

  /// Dónde figura la persona o la placa según los ingresos del equipo.
  PresenciaCoincidencia? _presenciaDe({String? dni, String? placa}) {
    final storage = _storage;
    if (storage == null) return null;
    final alcance = alcancePresenciaGranjas(storage, granjaFormulario: '');
    final c = dni != null
        ? IngresoPresenciaService.resolverPorDni(
            storage,
            dni: dni,
            granja: alcance.granja,
            granjas: alcance.granjas,
          )
        : IngresoPresenciaService.resolverPorPlaca(
            storage,
            placa: placa ?? '',
            granja: alcance.granja,
            granjas: alcance.granjas,
          );
    return c.encontrado ? c : null;
  }

  /// Marca la fila como regreso (salida temporal pendiente) o «ya dentro».
  /// Devuelve `true` si es regreso: entonces no se consulta la planificación.
  bool _marcarPresenciaDni(_DniFila fila) {
    final c = _presenciaDe(dni: fila.dni);
    final regreso = c?.ubicacion == PresenciaUbicacion.fueraTemporal ? c : null;
    final dentro = c?.ubicacion == PresenciaUbicacion.dentro;
    if (!identical(fila.regreso, regreso) || fila.yaDentro != dentro) {
      setState(() {
        fila.regreso = regreso;
        fila.yaDentro = dentro;
        if (regreso != null) {
          fila.plan = null;
          _limpiarVisitasAmbiguasDni(fila);
        }
      });
    }
    return regreso != null;
  }

  bool _marcarPresenciaVehiculo(_VehiculoFila fila) {
    final c = fila.escrita ? _presenciaDe(placa: fila.placaNorm) : null;
    final regreso = c?.ubicacion == PresenciaUbicacion.fueraTemporal ? c : null;
    final dentro = c?.ubicacion == PresenciaUbicacion.dentro;
    if (!identical(fila.regreso, regreso) || fila.yaDentro != dentro) {
      setState(() {
        fila.regreso = regreso;
        fila.yaDentro = dentro;
        if (regreso != null) {
          fila.plan = null;
          fila.ingresaPlan = null;
        }
      });
    }
    return regreso != null;
  }

  Future<void> _agregarDniEscaneado(String dni) async {
    final existente = _dnis.indexWhere((d) => d.dni == dni);
    if (existente >= 0) {
      _consultarPlanDni(existente);
      await _consultarNombre(existente);
      _consultarEstatusSanitario();
      return;
    }

    final fila = _DniFila();
    fila.ctrl.text = dni;
    setState(() => _dnis.add(fila));
    FocusManager.instance.primaryFocus?.unfocus();
    _consultarPlanDni(_dnis.length - 1);
    await _consultarNombre(_dnis.length - 1);
    _consultarEstatusSanitario();
  }

  Future<VerificacionFacialResult?> _resolverRostro(RostroCaptura cap) async {
    if (cap.manual || cap.rgb == null) return dniManualFacial(context);
    final close = showChickenLoadingDialog(context, '');
    await WidgetsBinding.instance.endOfFrame;
    VerificacionFacialResult? reconocido;
    try {
      final jpeg = jpegRostro(cap.rgb!, cap.ancho, cap.alto);
      if (jpeg.length >= 32) {
        final res = await ApiService()
            .verificarRostro(jpeg: jpeg)
            .timeout(const Duration(seconds: 90));
        final data = res['data'];
        final map =
            data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
        final dni = (map['dni'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
        if (res['success'] == true && map['verificado'] == true && dni.isNotEmpty) {
          reconocido = VerificacionFacialResult(
            dni: dni,
            nombre: (map['nombre'] ?? '').toString().trim(),
            empresa: (map['empresa'] ?? '').toString().trim(),
            verificado: true,
          );
        }
      }
    } on TimeoutException {
      debugPrint('[BioVerif] timeout en pantalla');
    } catch (e) {
      debugPrint('[BioVerif] error en pantalla $e');
    } finally {
      await dismissLoadingDialog(close);
    }
    if (!mounted) return null;
    return reconocido ?? await dniManualFacial(context);
  }

  Future<void> _identificarPorRostro() async {
    final cap = await Navigator.of(context).push<RostroCaptura>(
      MaterialPageRoute(builder: (_) => const VerificacionFacialScreen()),
    );
    if (cap == null || !mounted) return;
    final r = await _resolverRostro(cap);
    if (r == null || !mounted) return;
    if (!await _evaluarPresenciaTrasEscaneo(dni: r.dni)) return;
    if (!mounted) return;
    await _agregarDniEscaneado(r.dni);
    if (!mounted) return;
    final i = _dnis.indexWhere(
      (d) =>
          DocumentoPersona.normalizar(d.dni) ==
          DocumentoPersona.normalizar(r.dni),
    );
    if (i < 0) return;
    final fila = _dnis[i];
    setState(() {
      fila.verificacionFacial =
          r.verificado ? 'ok' : 'sin_verificacion_facial';
      if (r.empresa.trim().isNotEmpty) {
        fila.empresaFacial = r.empresa.trim();
      }
      if (fila.nombre.trim().isEmpty && r.nombre.trim().isNotEmpty) {
        fila.nombre = r.nombre.trim();
        fila.estado = _DniEstado.ok;
        fila.consultado = fila.dni;
      }
    });
  }

  /// Abre el escáner y agrega una fila nueva con el documento leído.
  Future<void> _escanearNuevoDni() async {
    final dni = await escanearDocumentoPersona(context);
    if (dni == null || !mounted) return;
    if (!await _evaluarPresenciaTrasEscaneo(dni: dni)) return;
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_agregarDniEscaneado(dni));
    });
  }

  /// Cantidad de personas (DNIs completos escaneados o ingresados a mano).
  int get _personas => _conteoIngresan();

  List<Map<String, dynamic>> _imagenesRegistro() => _imagenes
        .whereType<String>()
        .where((p) => p.trim().isNotEmpty)
        .map((p) => {'path': p})
        .toList();

  /// Ingreso por planificación (no el formulario de ingreso no planificado).
  bool get _esIngresoPlanificado =>
      _algunEscaneadoPlanificado && !_grupoIngresoNoPlanificado;

  /// En un ingreso planificado, los DNI que no van en ninguna visita: no se
  /// guardan con ella; quedan en la tabla para un ingreso aparte.
  List<_DniFila> get _dnisFueraDePlan {
    if (!_esIngresoPlanificado) return const [];
    return [
      for (final d in _dnisIngreso)
        if (d.completo &&
            (d.plan?.planificado != true || _planIdsDeFilaDni(d).isEmpty))
          d,
    ];
  }

  /// Con varias visitas, los vehículos que no son de ninguna tampoco se
  /// guardan (no se sabe a qué cuadrilla van). Con una sola visita viajan con
  /// ella: pudo cambiar el vehículo.
  List<_VehiculoFila> get _vehiculosFueraDePlan {
    if (!_esIngresoPlanificado || !_hayIngresoMultiPlanificacion) {
      return const [];
    }
    return [
      for (final v in _vehiculosIngreso)
        if (v.escrita &&
            (v.plan?.planificado != true ||
                v.plan?.visita == null ||
                v.plan!.visita!.id == 0))
          v,
    ];
  }

  /// [dnisFuera]: DNI que no van en la visita (se registran aparte).
  Map<String, dynamic> _buildRecord(
    StorageService storage, {
    List<_DniFila>? dnisFuera,
  }) {
    if (_hayIngresoMultiPlanificacion) {
      final g = _gruposIngresoPorPlanificacion().first;
      return _buildRecordForGrupo(g, storage);
    }
    final visita = _planVisita?.visita;
    final fuera = (dnisFuera ?? const <_DniFila>[]).toSet();
    return _buildRecordManual(
      storage,
      dnisFilas: _dnisIngreso.where((d) => !fuera.contains(d)),
      vehiculosFilas: _vehiculosIngreso,
      visita: visita,
      proceso: _procesoEfectivo.trim(),
      proveedor: _proveedorEfectivo,
      observacion: _observacionController.text.trim(),
      galponPartes: _galponPartes,
      galponEfectivo: _galponEfectivo,
    );
  }

  Map<String, dynamic> _buildRecordForGrupo(
    _GrupoIngresoPlan grupo,
    StorageService storage,
  ) {
    final form = PlanIngresoFormState();
    vincularVisitaPlanEnFormulario(form: form, visita: grupo.visita);
    final galpones = grupo.visita.galpones.isNotEmpty
        ? List<String>.from(grupo.visita.galpones)
        : _galponPartes;
    return _buildRecordManual(
      storage,
      dnisFilas: grupo.dnis,
      vehiculosFilas: grupo.vehiculos,
      visita: grupo.visita,
      proceso: form.proceso.trim(),
      proveedor: form.proveedor,
      observacion: form.observacion.trim().isNotEmpty
          ? form.observacion.trim()
          : _observacionController.text.trim(),
      galponPartes: galpones,
      galponEfectivo: galpones.join(', '),
    );
  }

  Future<void> _syncAlcoholemiaAgc(
    Map<String, dynamic> record,
    StorageService storage,
  ) async {
    if (!_alcoholemia.activa) return;
    if (!mounted) return;
    final umbral = context.read<CatalogService>().alcoholemiaMeta.umbralGl;
    for (final f in _alcoholemia.filas) {
      if (f.dni.isEmpty) continue;
      final g = double.tryParse(f.gradoGl.replaceAll(',', '.'));
      if (g == null || g <= umbral + 1e-9) continue;
      try {
        await AlcoholemiaApiService().guardarAlcoholemiaAgc({
          'granja': record['granja']?.toString() ?? _granja,
          'campania': record['campania']?.toString() ?? _campania,
          'fecha': record['fecha']?.toString() ?? _fechaYmd,
          'usuario': storage.getUserCodeSync() ?? '',
          'dni': f.dni,
          'nombre': f.nombre,
          'valor_aparato': f.valorAparato,
          'grado_g_l': g,
          'umbral_g_l': umbral,
          'agente_causal': f.agenteCausal,
          'anomalia': f.anomalia,
          'accion': f.accion,
        });
      } catch (_) {}
    }
  }

  List<Map<String, dynamic>> _alcoholemiaRegistroJson() {
    if (!_alcoholemia.activa) return const [];
    final out = <Map<String, dynamic>>[];
    for (final f in _alcoholemia.filas) {
      if (f.dni.isEmpty || f.gradoGl.trim().isEmpty) continue;
      final fotos = f.fotos
          .whereType<String>()
          .where((p) => p.isNotEmpty)
          .map((p) => {'path': p})
          .toList();
      out.add({
        'dni': f.dni,
        'nombre': f.nombre,
        'valor_aparato': f.valorAparato,
        'grado_g_l': f.gradoGl,
        'agente_causal': f.agenteCausal,
        'anomalia': f.anomalia,
        'accion': f.accion,
        'imagenes': fotos,
      });
    }
    return out;
  }

  Map<String, dynamic> _buildRecordManual(
    StorageService storage, {
    required Iterable<_DniFila> dnisFilas,
    required Iterable<_VehiculoFila> vehiculosFilas,
    required PlanVisita? visita,
    required String proceso,
    required ProveedorSeleccion proveedor,
    required String observacion,
    required List<String> galponPartes,
    required String galponEfectivo,
  }) {
    final dnis = <Map<String, String>>[];
    final vistos = <String>{};
    for (final d in dnisFilas) {
      final v = d.dni;
      if (v.isEmpty || !vistos.add(v)) continue;
      dnis.add({
        'dni': v,
        'nombre': d.nombreEfectivo,
        if (d.verificacionFacial.isNotEmpty)
          'verificacion_facial': d.verificacionFacial,
        if (d.empresaFacial.isNotEmpty) 'empresa': d.empresaFacial,
      });
    }
    final g3 = visita != null && visita.granja.isNotEmpty
        ? visita.granja
        : _granja;
    final gNom = visita != null && visita.nombreGranja.isNotEmpty
        ? visita.nombreGranja
        : _granjaNombre;
    final camp = visita != null && visita.campania.trim().isNotEmpty
        ? GranjaCampaniaPicker.padCampania(visita.campania)
        : _campania;
    return {
      'id': const Uuid().v4(),
      'reporte': 'ingreso',
      'fecha': _fechaYmd,
      'granja': g3,
      'granjaNombre': gNom,
      'campania': camp,
      'turno': _turno,
      'usuario': storage.getUserCodeSync() ?? '',
      'nombre_usuario': storage.getUserName() ?? '',
      'registro': {
        if (visita != null) 'plan_visita_id': visita.id,
        'hora': _hora,
        'vehiculos': _vehiculosRegistroDe(vehiculosFilas),
        'numpersonas': dnis.length,
        'areaproveedor': TiposVisitante.proveedor,
        'motivo': proceso,
        'galpon': galponEfectivo,
        if (galponPartes.isNotEmpty) 'galpones': galponPartes,
        'proveedor': proveedor.nombre.trim(),
        'proveedor_ruc': proveedor.ruc.trim(),
        'observacion': observacion,
        'dnis': dnis,
        if (_alcoholemiaRegistroJson().isNotEmpty) ...{
          'alcoholemia_pruebas': _alcoholemiaRegistroJson(),
          'alcoholemia': _alcoholemiaRegistroJson().first,
        },
      },
      'imagenes': _imagenesRegistro(),
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
      if (!DocumentoPersona.esCompleto(v)) {
        return 'El documento «$v» no es un DNI (8 dígitos) ni un CEE válido.';
      }
      if (!vistos.add(v)) {
        return 'El DNI «$v» está repetido.';
      }
    }
    return '';
  }

  int? _visitaIncluirSeleccionada;

  Future<void> _guardar() async {
    final hayIngreso = _hayElementosIngreso;
    if (!hayIngreso && !_hayRegresos) {
      showErrorToast(context, 'Escanee o ingrese al menos un DNI.');
      return;
    }
    final ingresoPlanificado = _esIngresoPlanificado;
    if (hayIngreso) {
      if (_personas < 1) {
        showErrorToast(context, 'Escanee o ingrese al menos un DNI.');
        return;
      }
      if (!ingresoPlanificado && (_granja.isEmpty || _campania.isEmpty)) {
        showErrorToast(
          context,
          _granja.isEmpty ? 'Seleccione la granja.' : 'Seleccione la campaña.',
        );
        return;
      }
      if (!ingresoPlanificado &&
          !_granjaPermitidaParaIngresoManual(_granja)) {
        showErrorToast(
          context,
          'La granja debe estar entre las de Mis granjas.',
        );
        return;
      }
    }
    if (_hora.trim().isEmpty) {
      showErrorToast(context, 'Indique la hora.');
      return;
    }
    final errorDni = _validarDnis();
    if (errorDni.isNotEmpty) {
      showErrorToast(context, errorDni);
      return;
    }
    if (_alcoholemia.activa) {
      final umbral = context.read<CatalogService>().alcoholemiaMeta.umbralGl;
      for (final f in _alcoholemia.filas) {
        if (f.dni.isEmpty) continue;
        final g = double.tryParse(f.gradoGl.replaceAll(',', '.'));
        if (g == null) continue;
        if (g <= umbral + 1e-9) continue;
        final tieneFoto = f.fotos.any((p) => p != null && p.isNotEmpty);
        if (!tieneFoto) {
          showErrorToast(
            context,
            'Adjunte evidencia de alcoholemia para ${f.nombre.isNotEmpty ? f.nombre : f.dni}.',
          );
          return;
        }
      }
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

    var dnisFuera = const <_DniFila>[];
    var vehiculosFuera = const <_VehiculoFila>[];
    final records = <Map<String, dynamic>>[];
    int? incluirEnVisitaId;
    var dnisIncluidos = const <_DniFila>[];
    var vehiculosIncluidos = const <_VehiculoFila>[];
    if (hayIngreso) {
      dnisFuera = _dnisFueraDePlan;
      vehiculosFuera = _vehiculosFueraDePlan;
      if (dnisFuera.isNotEmpty || vehiculosFuera.isNotEmpty) {
        _visitaIncluirSeleccionada = null;
        final opcion = await _confirmarSepararNoPlanificados(
          dnisFuera,
          vehiculosFuera,
          permitirIncluir: !_hayIngresoMultiPlanificacion,
        );
        if (opcion == _NoPlanificados.cancelar || !mounted) return;
        if (opcion == _NoPlanificados.incluir) {
          if (_hayIngresoMultiPlanificacion) {
            incluirEnVisitaId = _visitaIncluirSeleccionada;
            dnisIncluidos = dnisFuera;
            vehiculosIncluidos = vehiculosFuera;
            vehiculosFuera = const [];
          }
          dnisFuera = const [];
        }
      }
      if (_hayIngresoMultiPlanificacion) {
        records.addAll([
          for (final g0 in _gruposIngresoPorPlanificacion())
            for (final g in [
              g0.visita.id == incluirEnVisitaId
                  ? _GrupoIngresoPlan(
                      visita: g0.visita,
                      dnis: [...g0.dnis, ...dnisIncluidos],
                      vehiculos: [...g0.vehiculos, ...vehiculosIncluidos],
                    )
                  : g0,
            ])
            if (g.dnis.isNotEmpty || g.vehiculos.any((v) => v.escrita))
              _buildRecordForGrupo(g, storage),
        ]);
      } else {
        records.add(_buildRecord(storage, dnisFuera: dnisFuera));
      }
    }
    records.addAll(_buildRecordsRegreso(storage));
    if (records.isEmpty) {
      showInfoToast(context, 'No hay registros para guardar.');
      return;
    }

    await _guardarRegistros(
      storage,
      records,
      conservarDnis: dnisFuera,
      conservarVehiculos: vehiculosFuera,
    );
  }

  /// Regresos de salida temporal: un registro por ingreso (grupo) del que
  /// salieron, igual que lo guardaba la antigua pantalla de Regreso.
  List<Map<String, dynamic>> _buildRecordsRegreso(StorageService storage) {
    final grupos = <String, GrupoPresencia>{};
    final dnisPorGrupo = <String, List<Map<String, String>>>{};
    final placasPorGrupo = <String, List<Map<String, String>>>{};
    for (final d in _dnisRegreso) {
      final g = d.regreso!.grupo;
      if (g == null) continue;
      grupos[g.grupoId] = g;
      final lista = dnisPorGrupo.putIfAbsent(g.grupoId, () => []);
      if (lista.any((e) => e['dni'] == d.dni)) continue;
      final nombre = d.nombreEfectivo.trim().isNotEmpty
          ? d.nombreEfectivo.trim()
          : (d.regreso!.persona?.nombre ?? '');
      lista.add({
        'dni': d.dni,
        'nombre': nombre,
        if (d.verificacionFacial.isNotEmpty)
          'verificacion_facial': d.verificacionFacial,
        if (d.empresaFacial.isNotEmpty) 'empresa': d.empresaFacial,
      });
    }
    for (final v in _vehiculosRegreso) {
      final g = v.regreso!.grupo;
      if (g == null) continue;
      grupos[g.grupoId] = g;
      final lista = placasPorGrupo.putIfAbsent(g.grupoId, () => []);
      final placa = v.placa.toUpperCase();
      if (lista.any((e) => e['placa'] == placa)) continue;
      lista.add({'placa': placa});
    }
    return [
      for (final g in grupos.values)
        {
          'id': const Uuid().v4(),
          'reporte': 'salida',
          'fecha': _fechaYmd,
          'granja': g.granja,
          'granjaNombre': g.granjaNombre,
          'campania': g.campania,
          'turno': g.turno.isNotEmpty ? g.turno : 'Dia',
          'usuario': storage.getUserCodeSync() ?? '',
          'nombre_usuario': storage.getUserName() ?? '',
          'registro': {
            'hora': _hora.trim(),
            'movimiento': 'regreso',
            'grupo_id': g.grupoId,
            'proveedor': g.proveedor,
            'motivo': g.motivo,
            'dnis': dnisPorGrupo[g.grupoId] ?? const [],
            if ((placasPorGrupo[g.grupoId] ?? const []).isNotEmpty)
              'vehiculos': placasPorGrupo[g.grupoId],
          },
          'imagenes': const [],
          'synced': false,
          'guardado_backend': false,
          'created_at': DateTime.now().toIso8601String(),
        },
    ];
  }

  /// Aviso antes de guardar un ingreso planificado con personas (o vehículos)
  /// que no figuran en ninguna visita: se guardan las visitas y esos quedan en
  /// la tabla para registrarlos en otro ingreso con su proveedor.
  /// Con una sola visita se ofrece además incluirlos en ella (reemplazo en la
  /// misma cuadrilla o planificación sin lista de personas).
  Future<_NoPlanificados> _confirmarSepararNoPlanificados(
    List<_DniFila> dnis,
    List<_VehiculoFila> vehiculos, {
    required bool permitirIncluir,
  }) async {
    final nomina = NominaProveedorService.local(_storage!);
    final rucsVisita = <String>{
      for (final g in _gruposIngresoPorPlanificacion())
        if (g.visita.ruc.isNotEmpty) g.visita.ruc,
      if ((_planVisita?.visita?.ruc ?? '').isNotEmpty) _planVisita!.visita!.ruc,
    };
    var algunoDeLaVisita = false;
    String conProveedor(String dni) {
      final s = nomina.sugerir([dni], preferir: rucsVisita);
      if (s.isEmpty) return dni;
      final p = s.first.proveedor;
      final nombre = p.nombre.isNotEmpty ? p.nombre : 'RUC ${p.ruc}';
      if (rucsVisita.contains(p.ruc)) {
        algunoDeLaVisita = true;
        return '$dni (nómina de $nombre, proveedor de la visita)';
      }
      return '$dni ($nombre)';
    }

    final partes = <String>[
      if (dnis.isNotEmpty)
        '${dnis.length == 1 ? 'DNI' : 'DNIs'} '
            '${dnis.map((d) => conProveedor(d.dni)).join(', ')}',
      if (vehiculos.isNotEmpty)
        '${vehiculos.length == 1 ? 'Placa' : 'Placas'} '
            '${vehiculos.map((v) => v.placa.toUpperCase()).join(', ')}',
    ];
    final opcion = await showDialog<_NoPlanificados>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: AppColors.warning,
          size: 32,
        ),
        title: const Text('No planificados'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              partes.join('\n'),
              style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35),
            ),
            const SizedBox(height: 10),
            Text(
              permitirIncluir
                  ? 'No figuran en la visita planificada. Si son de la misma '
                        'cuadrilla, inclúyalos; si son de otro proveedor, '
                        'regístrelos aparte: quedarán en la pantalla para un '
                        'ingreso con su proveedor.'
                  : 'No figuran en las visitas planificadas. Se guardarán las '
                        'visitas y quedarán en la pantalla para registrarlos '
                        'en un ingreso aparte con su proveedor.',
              style: const TextStyle(height: 1.35),
            ),
            if (algunoDeLaVisita) ...[
              const SizedBox(height: 8),
              Text(
                permitirIncluir
                    ? 'Quien figura en la nómina del proveedor de la visita '
                          'probablemente es un reemplazo de la cuadrilla.'
                    : 'Quien figura en la nómina del proveedor de una visita '
                          'probablemente es un reemplazo: regístrelo aparte '
                          'con ese proveedor.',
                style: const TextStyle(
                  height: 1.35,
                  color: AppColors.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
        actionsOverflowDirection: VerticalDirection.up,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _NoPlanificados.cancelar),
            child: const Text('Cancelar'),
          ),
          if (permitirIncluir)
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, _NoPlanificados.incluir),
              child: const Text('Incluir en la visita'),
            )
          else
            for (final g in _gruposIngresoPorPlanificacion())
              OutlinedButton(
                onPressed: () {
                  _visitaIncluirSeleccionada = g.visita.id;
                  Navigator.pop(ctx, _NoPlanificados.incluir);
                },
                child: Text(
                  'Incluir con ${g.visita.razonSocial.trim().isNotEmpty ? g.visita.razonSocial.trim() : 'visita ${g.visita.id}'}',
                ),
              ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, _NoPlanificados.aparte),
            child: const Text('Registrar aparte'),
          ),
        ],
      ),
    );
    return opcion ?? _NoPlanificados.cancelar;
  }

  /// Resumen único (ingresos por proveedor y regresos) y guardado de todos.
  Future<void> _guardarRegistros(
    StorageService storage,
    List<Map<String, dynamic>> records, {
    List<_DniFila> conservarDnis = const [],
    List<_VehiculoFila> conservarVehiculos = const [],
  }) async {
    if (!mounted) return;
    final soloRegresos = records.every((r) => r['reporte'] != 'ingreso');
    final titulo = records.length > 1
        ? 'Resumen de registros (${records.length})'
        : (soloRegresos ? 'Resumen de regreso' : null);
    final saved = await RegisterSummarySheet.show(
      context,
      record: records.first,
      records: records,
      titulo: titulo,
      onConfirm: () async {
        var algunoOk = false;
        for (final record in records) {
          if (!mounted) return;
          final ok = await BioRecordSaver.save(context, record);
          algunoOk = algunoOk || ok;
          if (record['reporte'] != 'ingreso') continue;
          final reg =
              Map<String, dynamic>.from((record['registro'] as Map?) ?? {});
          final proveedorGrupo = ProveedorSeleccion(
            ruc: (reg['proveedor_ruc'] ?? '').toString(),
            nombre: (reg['proveedor'] ?? '').toString(),
          );
          if (!proveedorGrupo.estaVacio) {
            unawaited(
              ProveedorHistorialService(storage).registrar(
                proveedorGrupo,
                fuente: 'ingreso',
              ),
            );
          }
          unawaited(_syncAlcoholemiaAgc(record, storage));
        }
        if (!mounted) return;
        if (algunoOk) {
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
      _resetearFormularioTrasGuardar(
        planQuedaAbierto: false,
        conservarDnis: conservarDnis,
        conservarVehiculos: conservarVehiculos,
      );
    }
  }

  /// [conservarDnis] / [conservarVehiculos]: filas no planificadas que no se
  /// guardaron con las visitas; siguen en la tabla para el ingreso aparte.
  void _resetearFormularioTrasGuardar({
    required bool planQuedaAbierto,
    List<_DniFila> conservarDnis = const [],
    List<_VehiculoFila> conservarVehiculos = const [],
  }) {
      if (!mounted) return;
      final quedanDnis = conservarDnis.toSet();
      final quedanVehiculos = conservarVehiculos.toSet();
      setState(() {
        _estatusGranja = null;
        _observacionController.clear();
        _alcoholemia
          ..activa = false
          ..filas.clear();
        _avisoMultiPlanMostrado = false;
        for (final d in _dnis.where((d) => !quedanDnis.contains(d)).toList()) {
          _quitarFilaDeDnis(d);
        }
        for (final v in _vehiculos
            .where((v) => !quedanVehiculos.contains(v))
            .toList()) {
          _quitarFilaDeVehiculos(v);
        }
        _imagenes
          ..clear()
          ..addAll([null, null, null]);
      if (!planQuedaAbierto) {
          _planVisita = null;
          _visitaPlanId = null;
          _proveedor = ProveedorSeleccion.vacia;
          _proveedorElegidoAMano = false;
          _proceso = '';
          _procesoElegidoAMano = false;
          if (quedanDnis.isNotEmpty || quedanVehiculos.isNotEmpty) {
            _galponesSel = [];
            _galponOtro = false;
            _galponOtroController.clear();
          }
        }
      });
      if (quedanDnis.isNotEmpty || quedanVehiculos.isNotEmpty) {
        _cargarGalpones();
        _sincronizarPlanificacionGlobal();
        _consultarEstatusSanitario();
      }
  }

  /// Cómo se nombra a la persona en los avisos: su nombre si ya se resolvió y,
  /// si no, el DNI.
  String _sujetoDe(_DniFila fila) {
    final nombre = fila.nombreEfectivo.trim();
    return nombre.isNotEmpty ? nombre : 'DNI ${fila.dni}';
  }

  /// Celda «Nombre» con el aviso de planificación debajo (« Planificado» o
  /// « No planificado») y la etiqueta de situación especial cuando el DNI
  /// viene de una granja en sospecha o confirmado.
  Widget _conAvisoPlan(_DniFila fila, Widget celda) {
    final plan = fila.plan;
    final estatus = fila.estatus;
    final avisos = <Widget>[
      if (fila.esRegreso || fila.yaDentro)
        _EtiquetaPresencia(regreso: fila.regreso, yaDentro: fila.yaDentro),
      if (estatus != null)
        _EtiquetaSituacion(
          estatus: estatus,
          sujeto: _sujetoDe(fila),
          avisoSujeto: 'Esta persona',
          compacto: true,
        ),
      if (fila.ordenEdad != null)
        _EtiquetaOrdenEdad(
          aviso: fila.ordenEdad!,
          sujeto: _sujetoDe(fila),
          avisoSujeto: 'Esta persona',
          compacto: true,
        ),
      if (plan != null && fila.completo && !fila.esRegreso)
        _AvisoPlan(
          plan: plan,
          sujeto: 'DNI ${fila.dni}',
          etiqueta: !plan.planificado
              ? 'No planificado'
              : (fila.visitasPlanAmbiguas.length > 1 &&
                    fila.visitasPlanIdsSeleccionados.isEmpty)
              ? 'Planificado · ${fila.visitasPlanAmbiguas.length} visitas'
              : 'Planificado',
          chico: true,
        ),
    ];
    if (avisos.isEmpty) return celda;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        celda,
        const SizedBox(height: 2),
        ...avisos,
      ],
    );
  }

  Widget _buildFaseIdentificar(BuildContext context) {
    return BioFormSection(
      title: '1. Identificar',
      icon: Icons.qr_code_scanner_rounded,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _identificarPorRostro,
            icon: const Icon(Icons.face_retouching_natural),
            label: const Text('Verificación facial'),
          ),
        ),
        const SizedBox(height: _sepCampo),
        BioScanTiles(
          onScanDni: _escanearNuevoDni,
          onScanPlaca: _escanearPlacaNueva,
          onManualDni: _agregarDni,
          onManualPlaca: _agregarVehiculo,
        ),
        if (_dnis.isNotEmpty) ...[
          const SizedBox(height: _sepCampo),
          BioTable(
              caption: 'Personas',
              rowHeight: 54,
              columns: const [
                BioColumn('Documento', width: 104, align: TextAlign.left, flex: 1),
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
                          hint: 'DNI o CEE',
                          keyboardType: TextInputType.text,
                          maxLength: _largoDocMax,
                          soloDigitos: false,
                          onChanged: (_) => _alCambiarDni(index),
                        ),
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
        ],
        if (_vehiculos.isNotEmpty) ...[
                  const SizedBox(height: _sepCampo),
          BioTable(
            caption: 'Vehículos',
            rowHeight: 72,
            columns: const [
              BioColumn('Placa', width: 120, align: TextAlign.left, flex: 2),
              BioColumn('', width: 38),
            ],
            rowCount: _vehiculos.length,
            rowBuilder: (context, index) {
              final fila = _vehiculos[index];
              return [
                _TablaCeldaPlaca(
                  fila: fila,
                  onChanged: () => _alCambiarVehiculo(index),
                ),
                InkWell(
                  onTap: () => _quitarVehiculo(index),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: AppColors.errorDark,
                  ),
                ),
              ];
            },
          ),
        ],
      ],
    );
  }

  /// Tarjeta «granja en situación especial» (sospecha / confirmado).
  Widget _avisoEstatusGranjaRegistro() {
    final e = _estatusGranja;
    if (e == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: _sepCampo),
      child: _EstatusGranjaCard(estatus: e),
    );
  }

  /// Aviso de estatus sanitario justo debajo de la fila «Granja».
  Widget _avisoEstatusDebajoGranja() {
    final e = _estatusGranja;
    if (e == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: _EstatusGranjaCard(estatus: e),
    );
  }

  Widget _campoHoraIngreso() {
    return BioTimeField(
      label: 'Hora de ingreso',
      value: _hora,
      onPicked: (v) => setState(() => _hora = v),
    );
  }

  /// Personas y vehículos con salida temporal pendiente: se registra su regreso
  /// (sin formulario de ingreso). Si no hay ingresos nuevos, aquí va la hora.
  Widget _buildSeccionRegreso(BuildContext context) {
    final grupos = <String, GrupoPresencia>{};
    final personas = <String, List<String>>{};
    final placas = <String, List<String>>{};
    for (final d in _dnisRegreso) {
      final g = d.regreso!.grupo;
      if (g == null) continue;
      grupos[g.grupoId] = g;
      final nombre = d.nombreEfectivo.trim();
      personas.putIfAbsent(g.grupoId, () => []).add(
        nombre.isEmpty ? d.dni : '${d.dni} · $nombre',
      );
    }
    for (final v in _vehiculosRegreso) {
      final g = v.regreso!.grupo;
      if (g == null) continue;
      grupos[g.grupoId] = g;
      placas.putIfAbsent(g.grupoId, () => []).add(v.placa);
    }
    final soloRegreso = !_hayElementosIngreso;
    final muted = context.textThemeMuted;
    return BioFormSection(
      title: soloRegreso ? '2. Confirmar regreso' : 'Regreso',
      icon: Icons.u_turn_left_rounded,
      children: [
        Text(
          'Tenían salida temporal: se registra su regreso a la visita.',
          style: TextStyle(fontSize: 11.5, color: muted),
        ),
        for (final g in grupos.values) ...[
          const SizedBox(height: _sepCampo),
          _lineaFichaVisita(
            context,
            g.proveedor.trim().isEmpty ? 'Visita' : g.proveedor.trim(),
            [
              if (g.granjaNombre.trim().isNotEmpty) g.granjaNombre.trim(),
              if (g.horaIngreso.trim().isNotEmpty)
                'Ingresó ${g.horaIngreso.trim()}',
              ...?personas[g.grupoId],
              ...?placas[g.grupoId],
            ].join('\n'),
            maxLines: 12,
          ),
        ],
        if (soloRegreso) ...[
          const SizedBox(height: _sepCampo),
          BioTimeField(
            label: 'Hora de regreso',
            value: _hora,
            onPicked: (v) => setState(() => _hora = v),
          ),
        ],
      ],
    );
  }

  Widget _buildSeccionFichaPlanificada(BuildContext context) {
    if (_hayVisitasPorElegir) return _buildSeccionElegirVisitas(context);
    final grupos = _gruposIngresoPorPlanificacion();
    final visitas = grupos.isNotEmpty
        ? [for (final g in grupos) g.visita]
        : [if (_planVisita?.visita != null) _planVisita!.visita!];
    if (visitas.isEmpty) return const SizedBox.shrink();
    final varias = visitas.length > 1;
    return BioFormSection(
      title: varias
          ? '2. Visitas planificadas (${visitas.length})'
          : '2. Visita planificada',
      icon: Icons.event_available_rounded,
      children: [
        if (varias)
          for (var i = 0; i < grupos.length; i++) ...[
            _filaResumenVisitaPlan(grupos[i]),
          ],
        for (var i = 0; i < visitas.length; i++) ...[
          if (i > 0 || varias) const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _mostrarDialogoFichaVisita(visitas[i]),
            icon: const Icon(Icons.description_outlined, size: 18),
            label: Text(
              varias ? 'Ver Ficha de Ingreso ${i + 1}' : 'Ver Ficha de Ingreso',
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              foregroundColor: AppColors.primaryDark,
            ),
          ),
        ],
      ],
    );
  }

  Widget _contenidoFichaVisita(BuildContext context, PlanVisita visita) {
    final form = PlanIngresoFormState();
    vincularVisitaPlanEnFormulario(form: form, visita: visita);
    final fecha = DateTime.tryParse(visita.fecha);
    final fechaTxt =
        fecha != null ? DateFormat('dd/MM/yyyy').format(fecha) : visita.fecha;
    final camp = visita.campania.trim().isNotEmpty
        ? GranjaCampaniaPicker.padCampania(visita.campania)
        : '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _lineaFichaVisita(context, 'Fecha', fechaTxt),
        _lineaFichaVisita(
          context,
          'Granja',
          GranjaCampaniaPicker.formatGranjaLabel(
            visita.granja,
            visita.nombreGranja,
          ),
        ),
        _lineaFichaVisita(context, 'Campaña', camp),
        _lineaFichaVisita(
          context,
          'Galpones',
          visita.galpones.isNotEmpty ? visita.galpones.join(', ') : '—',
          maxLines: 4,
        ),
        _lineaFichaVisita(
          context,
          'Proveedor',
          form.proveedor.etiqueta,
          maxLines: 3,
        ),
        _lineaFichaVisita(context, 'Proceso', form.proceso, maxLines: 3),
        if (form.observacion.trim().isNotEmpty)
          _lineaFichaVisita(
            context,
            'Observación',
            form.observacion.trim(),
            maxLines: 4,
          ),
      ],
    );
  }

  Future<void> _mostrarDialogoFichaVisita(PlanVisita visita) async {
    final titulo = visita.razonSocial.trim().isNotEmpty
        ? visita.razonSocial.trim()
        : 'Visita planificada #${visita.id}';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final ancho = MediaQuery.sizeOf(dialogContext).width - 16;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: ancho, minWidth: ancho),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          titulo,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: _contenidoFichaVisita(dialogContext, visita),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Varias visitas planificadas hoy para la misma persona: una tarjeta por
  /// visita (granja) y el vigilante marca a cuáles ingresa (una o varias).
  Widget _buildSeccionElegirVisitas(BuildContext context) {
    final candidatas = _visitasCandidatas;
    final idsCandidatas = {for (final v in candidatas) v.id};
    final otras = [
      for (final g in _gruposIngresoPorPlanificacion())
        if (!idsCandidatas.contains(g.visita.id)) g,
    ];
    final ambiguos = [
      for (final d in _dnis)
        if (d.visitasPlanAmbiguas.length > 1) d,
    ];
    final ninguna = !candidatas.any(_visitaMarcada);
    return BioFormSection(
      title: '2. Visitas planificadas (${candidatas.length + otras.length})',
      icon: Icons.event_available_rounded,
      children: [
        for (final d in ambiguos)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 13,
                  height: 1.3,
                  color: context.textThemeSecondary,
                ),
                children: [
                  TextSpan(
                    text: _sujetoDe(d),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(
                    text: ' tiene ${d.visitasPlanAmbiguas.length} visitas '
                        'planificadas hoy.',
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Marque las granjas a las que ingresa.',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: ninguna ? AppColors.warning : context.textThemeMuted,
            ),
          ),
        ),
        for (final v in candidatas) ...[
          _TarjetaVisitaPlan(
            visita: v,
            marcada: _visitaMarcada(v),
            personas: [
              for (final d in _dnis)
                if (d.visitasPlanAmbiguas.any((a) => a.id == v.id)) d.dni,
            ],
            onCambiar: (m) => _alternarVisitaPlan(v, m),
            onVerFicha: () => _mostrarDialogoFichaVisita(v),
          ),
          const SizedBox(height: 8),
        ],
        for (final g in otras) ...[
          _filaResumenVisitaPlan(g),
          OutlinedButton.icon(
            onPressed: () => _mostrarDialogoFichaVisita(g.visita),
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('Ver Ficha de Ingreso'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              foregroundColor: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _filaResumenVisitaPlan(_GrupoIngresoPlan grupo) {
    final v = grupo.visita;
    final razon = v.razonSocial.trim();
    final etiqueta = razon.isNotEmpty ? '${v.granja} · $razon' : v.granja;
    final n = grupo.dnis.length;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(Icons.place_outlined, size: 20, color: context.textThemeMuted),
      title: Text(
        etiqueta,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: n > 0
          ? Text(
              n == 1 ? '1 persona' : '$n personas',
              style: TextStyle(fontSize: 12, color: context.textThemeMuted),
            )
          : null,
    );
  }

  Widget _lineaFichaVisita(
    BuildContext context,
    String etiqueta,
    String valor, {
    int maxLines = 2,
  }) {
    final v = valor.trim().isEmpty ? '—' : valor.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: TextStyle(
            fontSize: 13,
            height: 1.35,
            color: context.textThemePrimary,
          ),
            children: [
            TextSpan(
              text: '$etiqueta: ',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: context.textThemeSecondary,
              ),
            ),
            TextSpan(
              text: v,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectorGalponesIngreso() {
    return EvidenciaGalponField(
      value: _galponesSel,
      options: _galponOpciones,
      otroSeleccionado: _galponOtro,
      textoOtro: _galponOtroController.text,
      onSelected: (r) => setState(() {
        _galponesSel = r.seleccionados;
        _galponOtro = r.otro;
        if (!r.otro) {
          _galponOtroController.clear();
        } else if (r.textoOtro.trim().isNotEmpty) {
          _galponOtroController.text = r.textoOtro.trim();
        }
      }),
    );
  }

  /// Debajo de «Proveedor»: de dónde salió la propuesta, otros proveedores
  /// posibles y quiénes figuran en la nómina de otro proveedor.
  Widget _avisoProveedorNomina(BuildContext context) {
    final sugerencias = _sugerenciasProveedor;
    if (sugerencias.isEmpty) return const SizedBox.shrink();
    final sugerido = _proveedorSugerido;
    final total = _dnisIngreso.where((d) => d.completo).length;
    final ruc = _proveedorEfectivo.ruc;
    final actual = ruc.isEmpty
        ? null
        : sugerencias.where((s) => s.proveedor.ruc == ruc).firstOrNull;
    final otras = [
      for (final s in sugerencias)
        if (s.proveedor.ruc != ruc) s,
    ];
    final enOtro = actual == null
        ? const <String>[]
        : <String>{
            for (final s in otras)
              for (final d in s.dnis)
                if (!actual.dnis.contains(d)) d,
          }.toList();
    final muted = context.textThemeMuted;
    final estilo = TextStyle(fontSize: 11, color: muted, height: 1.3);

    String nombreDe(SugerenciaProveedor s) => s.proveedor.nombre.isNotEmpty
        ? s.proveedor.nombre
        : 'RUC ${s.proveedor.ruc}';

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (actual != null)
            Text(
              '${sugerido != null ? 'Propuesto según ' : 'Según '}'
              '${actual.desdeNomina ? 'la nómina del proveedor' : 'ingresos anteriores'}'
              ' · ${actual.dnis.length} de $total '
              '${total == 1 ? 'persona' : 'personas'}',
              style: estilo,
            )
          else if (_proveedorEfectivo.estaVacio)
            Text(
              'Según la nómina, estas personas pueden ser de:',
              style: estilo,
            ),
          if (enOtro.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${enOtro.length == 1 ? 'El DNI' : 'Los DNI'} ${enOtro.join(', ')} '
                '${enOtro.length == 1 ? 'figura' : 'figuran'} con otro proveedor: '
                'si no son de esta cuadrilla, regístrelos en otro ingreso.',
                style: estilo.copyWith(color: AppColors.warning),
              ),
            ),
          if (otras.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final s in otras.take(4))
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.storefront_rounded, size: 14),
                      label: Text(
                        '${nombreDe(s)} (${s.dnis.length})',
                        style: const TextStyle(fontSize: 11),
                      ),
                      onPressed: () => _elegirProveedorSugerido(s),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Debajo de «Proceso»: de dónde salió la propuesta o, si el proveedor tiene
  /// varios procesos asignados y no se sabe cuál, los procesos para elegir.
  Widget _avisoProcesoProveedor(BuildContext context) {
    final storage = _storage;
    final ruc = _proveedorEfectivo.ruc;
    if (storage == null || ruc.isEmpty || _procesoElegidoAMano) {
      return const SizedBox.shrink();
    }
    final estilo = TextStyle(
      fontSize: 11,
      color: context.textThemeMuted,
      height: 1.3,
    );
    if (_procesoSugerido.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('Propuesto según el proveedor', style: estilo),
      );
    }
    if (_proceso.trim().isNotEmpty) return const SizedBox.shrink();
    final procesos = NominaProveedorService.local(storage).procesosDe(ruc);
    if (procesos.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final p in procesos.take(6))
            ActionChip(
              visualDensity: VisualDensity.compact,
              label: Text(p, style: const TextStyle(fontSize: 11)),
              onPressed: () => _elegirProcesoSugerido(p),
            ),
        ],
      ),
    );
  }

  /// Visita no planificada: formulario completo en pantalla (estilo ficha antigua).
  Widget _buildFormularioNoPlanificado(BuildContext context) {
    return BioFormSection(
      title: '2. Ingreso',
      icon: Icons.edit_note_rounded,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: EvidenciaSelectField(
                          label: 'Fecha',
                          value: DateFormat('dd/MM/yyyy').format(_fecha),
                          placeholder: 'Hoy',
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
                    granjasPermitidas: _granjasPermitidasIngresoNoPlanificado,
                    onSeleccion: _onGranjaCampania,
                  ),
        _avisoEstatusDebajoGranja(),
                    const SizedBox(height: _sepCampo),
        _selectorGalponesIngreso(),
                      const SizedBox(height: _sepCampo),
        _campoHoraIngreso(),
                  const SizedBox(height: _sepCampo),
                  EvidenciaSelectField(
                    label: 'Proveedor',
                    value: _proveedorEfectivo.etiqueta,
                    placeholder: 'RUC o nombre',
                    icon: Icons.storefront_rounded,
                    onTap: _pickProveedor,
                  ),
                  _avisoProveedorNomina(context),
                  const SizedBox(height: _sepCampo),
                  EvidenciaSelectField(
                    label: 'Proceso',
                    value: _procesoEfectivo,
                    placeholder: 'Seleccione',
                    icon: Icons.account_tree_rounded,
                    onTap: _pickProceso,
                  ),
                  _avisoProcesoProveedor(context),
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
                  const SizedBox(height: _sepCampo),
        ImageSlotRow(
          paths: _imagenes,
          onChanged: (i, path) => setState(() => _imagenes[i] = path),
        ),
      ],
    );
  }

  /// Galpones de la planificación web (ficha) o selector si no vinieron del portal.
  Widget _buildGalponesPlanificacion(
    BuildContext context, {
    PlanVisita? visitaOverride,
  }) {
    final visita = visitaOverride ?? _planVisita?.visita;
    if (visita != null && visita.galpones.isNotEmpty) {
      return _lineaFichaVisita(
        context,
        'Galpones',
        visita.galpones.join(', '),
        maxLines: 4,
      );
    }
    return _selectorGalponesIngreso();
  }

  Widget _buildAlcoholemiaIngreso() {
    return IngresoAlcoholemiaSection(
      candidatos: [
        for (final d in _dnisIngreso)
          if (DocumentoPersona.esCompleto(d.dni))
            (dni: d.dni, nombre: d.nombreEfectivo),
      ],
      data: _alcoholemia,
      onChanged: (_) => setState(() {}),
    );
  }

  /// Fecha, turno, hora de ingreso (garita) y fotos; galpones en ficha si planificado.
  Widget _buildSeccionConfirmarIngreso(
    BuildContext context, {
    bool incluirEvidencias = true,
    bool incluirGalpones = false,
    bool incluirHoraIngreso = false,
    PlanVisita? visitaGalpones,
  }) {
    return BioFormSection(
      title: '3. Confirmar ingreso',
      icon: Icons.task_alt_rounded,
      children: [
        if (incluirGalpones) ...[
          _buildGalponesPlanificacion(
            context,
            visitaOverride: visitaGalpones,
              ),
              const SizedBox(height: _sepCampo),
        ],
        if (incluirHoraIngreso) ...[
          _campoHoraIngreso(),
              const SizedBox(height: _sepCampo),
        ],
                    Row(
                      children: [
                        Expanded(
              child: EvidenciaSelectField(
                label: 'Fecha',
                value: DateFormat('dd/MM/yyyy').format(_fecha),
                placeholder: 'Hoy',
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
        if (incluirEvidencias) ...[
          const SizedBox(height: _sepCampo),
          ImageSlotRow(
            paths: _imagenes,
            onChanged: (i, path) => setState(() => _imagenes[i] = path),
          ),
        ],
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
        actions: [
          if (_puedeConfirmarEnPantalla)
            AppBarSaveButton(onPressed: _guardar),
        ],
      ),
      body: DismissKeyboardScope(
        child: RefreshIndicator(
          onRefresh: _refrescar,
          color: AppColors.primaryDark,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
              const BioCatalogoAviso(),
              _avisoConfigurarMisGranjas(context),
              _buildFaseIdentificar(context),
              if (_dnisIngreso.any((d) => DocumentoPersona.esCompleto(d.dni))) ...[
                const SizedBox(height: _sepBloque),
                _buildAlcoholemiaIngreso(),
              ],
              if (_hayRegresos) ...[
                const SizedBox(height: _sepBloque),
                _buildSeccionRegreso(context),
              ],
              if (_hayElementosIngreso) ...[
                const SizedBox(height: _sepBloque),
                if (_hayVisitasPorElegir ||
                    (_algunEscaneadoPlanificado &&
                        !_grupoIngresoNoPlanificado)) ...[
                  _buildSeccionFichaPlanificada(context),
                  if (_personas >= 1) ...[
                    const SizedBox(height: _sepBloque),
                    if (_algunEscaneadoPlanificado)
                      _avisoEstatusGranjaRegistro(),
                    _buildSeccionConfirmarIngreso(
                      context,
                      incluirHoraIngreso: true,
                    ),
                  ],
                ] else if (_grupoIngresoNoPlanificado)
                  _buildFormularioNoPlanificado(context)
                else if (!_planificacionResueltaParaGrupo)
                  const BioFormSection(
                    title: '2. Planificación',
                    icon: Icons.hourglass_top_rounded,
                    children: [
                      Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
          ),
        ],
                  ),
              ],
            ],
          ),
        ),
        ),
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

/// Etiqueta de «situación especial» de un DNI.
/// Se enciende cuando la persona ingresó recientemente a una granja que hoy
/// está en sospecha (ámbar) o confirmado (rojo). Solo alerta: el registro de
/// ingreso se guarda igual. Al tocarla aparece de qué granja viene y hasta
/// cuándo está vigente el estatus.
class _EtiquetaOrdenEdad extends StatelessWidget {
  const _EtiquetaOrdenEdad({
    required this.aviso,
    required this.sujeto,
    this.compacto = false,
    this.enTabla = false,
    this.avisoSujeto = 'Esta persona',
  });

  final OrdenEdadDni aviso;
  final String sujeto;
  final bool compacto;
  final bool enTabla;
  final String avisoSujeto;

  void _mostrarDetalle(BuildContext context) {
    showOrdenEdadDialog(context: context, aviso: aviso, sujeto: sujeto);
  }

  @override
  Widget build(BuildContext context) {
    final color = colorOrdenEdad();
    final texto = aviso.avisoIngresoCorto(avisoSujeto);
    final iconSize = enTabla || compacto ? 13.0 : 13.0;
    final fontSize = enTabla ? 10.0 : (compacto ? 10.0 : 11.0);

    if (enTabla) {
      return InkWell(
        onTap: () => _mostrarDetalle(context),
        borderRadius: BorderRadius.circular(6),
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Icon(Icons.swap_vert_rounded, size: iconSize, color: color),
            const SizedBox(width: 4),
          Expanded(
            child: Text(
                texto,
                maxLines: 3,
              overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: fontSize,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                  color: color,
              ),
            ),
          ),
        ],
      ),
    );
    }

    return InkWell(
      onTap: () => _mostrarDetalle(context),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_vert_rounded, size: iconSize, color: color),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                texto,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: fontSize,
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

class _EtiquetaSituacion extends StatelessWidget {
  const _EtiquetaSituacion({
    required this.estatus,
    required this.sujeto,
    this.compacto = false,
    this.enTabla = false,
    this.avisoSujeto = 'Esta persona',
  });

  final EstatusDni estatus;
  final String sujeto;
  final bool compacto;

  /// Fila de vehículos: icono + texto en ancho completo bajo la placa.
  final bool enTabla;

  /// Cómo arranca la frase del aviso: «Esta persona» o «El vehículo».
  final String avisoSujeto;

  void _mostrarDetalle(BuildContext context) {
    showSituacionDialog(context: context, estatus: estatus, sujeto: sujeto);
  }

  @override
  Widget build(BuildContext context) {
    final color = colorSituacion(estatus);
    final aviso = estatus.avisoIngreso(avisoSujeto);

    if (enTabla) {
      return InkWell(
        onTap: () => _mostrarDetalle(context),
        borderRadius: BorderRadius.circular(6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.coronavirus_rounded, size: 13, color: color),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                aviso,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (compacto) {
      return InkWell(
          onTap: () => _mostrarDetalle(context),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.coronavirus_rounded, size: 13, color: color),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  estatus.avisoIngreso(avisoSujeto),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
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

    return InkWell(
      onTap: () => _mostrarDetalle(context),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.coronavirus_rounded, size: 13, color: color),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                estatus.avisoIngreso(avisoSujeto),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
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

/// Celda «Placa» en la tabla de vehículos (misma idea que DNI + nombre).
class _TablaCeldaPlaca extends StatelessWidget {
  const _TablaCeldaPlaca({
    required this.fila,
    required this.onChanged,
  });

  final _VehiculoFila fila;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    bool? ingresaWeb = fila.ingresaPlan;
    if (ingresaWeb == null) {
      final veh = fila.plan?.visita?.vehiculoDe(fila.ctrl.text);
      if (veh != null) ingresaWeb = veh.ingresa;
    }
    final esPlan = fila.planificada.isNotEmpty ||
        (fila.plan?.planificado ?? false);
    final muestraPlan = !fila.esRegreso &&
        (esPlan || (fila.plan != null && !fila.plan!.planificado));
    final suffix = fila.esRegreso
        ? null
        : _suffixVehiculoIngreso(
            ingresaWeb: ingresaWeb,
            planificado: esPlan,
            mostrarPlan: muestraPlan,
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: BioTextField(
                controller: fila.ctrl,
                hint: 'Placa',
                maxLength: 15,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => onChanged(),
              ),
            ),
            if (suffix != null) suffix,
          ],
        ),
        if (fila.esRegreso || fila.yaDentro)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _EtiquetaPresencia(
              regreso: fila.regreso,
              yaDentro: fila.yaDentro,
            ),
          ),
        if (fila.estatus != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _EtiquetaSituacion(
              estatus: fila.estatus!,
              sujeto: 'El vehículo ${fila.placa}',
              avisoSujeto: 'El vehículo',
              enTabla: true,
            ),
          ),
        if (fila.ordenEdad != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _EtiquetaOrdenEdad(
              aviso: fila.ordenEdad!,
              sujeto: 'El vehículo ${fila.placa}',
              avisoSujeto: 'El vehículo',
              enTabla: true,
            ),
          ),
      ],
    );
  }
}

/// Tarjeta de la granja del registro en situación especial (sospecha o
/// confirmado). Se muestra en la fila siguiente al campo «Granja».
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
/// Pequeño y corto: « Vehículo planificado» en verde o « Vehículo no
/// planificado» en ámbar (en la fila del DNI, «Planificado» / «No
/// planificado»). Con [compacto] se muestra solo el ícono. Al tocarlo aparece
/// el detalle (fecha, granja). Nunca bloquea nada.
/// «Regreso · proveedor» (tenía salida temporal pendiente) o «Ya figura
/// dentro» (ingresó y no tiene salida registrada en este equipo).
class _EtiquetaPresencia extends StatelessWidget {
  const _EtiquetaPresencia({required this.regreso, required this.yaDentro});

  final PresenciaCoincidencia? regreso;
  final bool yaDentro;

  @override
  Widget build(BuildContext context) {
    final g = regreso?.grupo;
    final String texto;
    final Color color;
    final IconData icono;
    if (regreso != null) {
      final prov = (g?.proveedor ?? '').trim();
      texto = prov.isEmpty ? 'Regreso' : 'Regreso · $prov';
      color = AppColors.primary;
      icono = Icons.u_turn_left_rounded;
    } else {
      texto = 'Ya figura dentro';
      color = AppColors.warning;
      icono = Icons.info_outline_rounded;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 13, color: color),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// Tarjeta de una visita planificada con su casilla: al marcarla, la persona
/// ingresa por esa visita (puede marcar varias).
class _TarjetaVisitaPlan extends StatelessWidget {
  const _TarjetaVisitaPlan({
    required this.visita,
    required this.marcada,
    required this.personas,
    required this.onCambiar,
    required this.onVerFicha,
  });

  final PlanVisita visita;
  final bool marcada;

  /// Documentos escaneados que figuran en esta visita.
  final List<String> personas;
  final ValueChanged<bool> onCambiar;
  final VoidCallback onVerFicha;

  @override
  Widget build(BuildContext context) {
    final borde = marcada ? AppColors.primaryDark : context.textThemeMuted;
    final razon = visita.razonSocial.trim();
    final proceso = visita.proceso.trim();
    final camp = visita.campania.trim().isNotEmpty
        ? GranjaCampaniaPicker.padCampania(visita.campania)
        : '';
    final detalle = <String>[
      if (razon.isNotEmpty) razon,
      if (proceso.isNotEmpty) proceso,
    ].join(' · ');
    final extra = <String>[
      if (camp.isNotEmpty) 'Campaña $camp',
      if (visita.galpones.isNotEmpty) 'Galpones ${visita.galpones.join(', ')}',
      if (visita.placasTexto.isNotEmpty) 'Placa ${visita.placasTexto}',
    ].join(' · ');
    return Material(
      color: marcada
          ? AppColors.primary.withValues(alpha: 0.08)
          : context.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: borde.withValues(alpha: marcada ? 0.9 : 0.35),
          width: marcada ? 1.6 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onCambiar(!marcada),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 10, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: marcada,
                onChanged: (v) => onCambiar(v ?? false),
                activeColor: AppColors.primaryDark,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        GranjaCampaniaPicker.formatGranjaLabel(
                          visita.granja,
                          visita.nombreGranja,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: context.textThemePrimary,
                        ),
                      ),
                      if (detalle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          detalle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: context.textThemeSecondary,
                          ),
                        ),
                      ],
                      if (extra.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          extra,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textThemeMuted,
                          ),
                        ),
                      ],
                      if (personas.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          personas.length == 1
                              ? 'DNI ${personas.first}'
                              : 'DNI ${personas.join(', ')}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.textThemeMuted,
                          ),
                        ),
                      ],
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: onVerFicha,
                          icon: const Icon(Icons.description_outlined, size: 16),
                          label: const Text('Ver ficha'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primaryDark,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvisoPlan extends StatelessWidget {
  const _AvisoPlan({
    required this.plan,
    required this.sujeto,
    this.etiqueta = '',
    this.chico = false,
  });

  final _PlanInfo plan;
  final String sujeto;
  final String etiqueta;
  final bool chico;

  @override
  Widget build(BuildContext context) {
    final color = plan.planificado ? AppColors.success : AppColors.warning;
    final icono = plan.planificado
        ? Icons.check_circle_rounded
        : Icons.warning_amber_rounded;

    return Padding(
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
    );
  }
}
