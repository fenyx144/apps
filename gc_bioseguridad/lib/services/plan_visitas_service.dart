import '../utils/documento_persona.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../utils/constants.dart';
import 'api_service.dart';
import 'proveedor_historial_service.dart';
import 'storage_service.dart';

/// Persona programada en una visita del portal web (DNI y nombre; el nombre
/// puede venir vacío si en la web no se registró).
class PlanPersona {
  const PlanPersona({required this.dni, this.nombre = ''});

  final String dni;
  final String nombre;

  factory PlanPersona.fromJson(Map m) => PlanPersona(
    dni: DocumentoPersona.normalizar((m['dni'] ?? '').toString()),
    nombre: (m['nombre'] ?? '').toString().trim(),
  );

  Map<String, dynamic> toJson() => {'dni': dni, 'nombre': nombre};
}

/// Vehículo programado en una visita: la placa y si ingresa a la granja.
/// El switch «Ingresa» lo marca el proveedor al planificar en la web; la app lo
/// muestra en el control de ingreso. En planificaciones viejas —o cuando el
/// servidor no mandó el detalle— la placa sola viaja como un vehículo que
/// ingresa.
class PlanVehiculo {
  const PlanVehiculo({required this.placa, this.ingresa = true});

  final String placa;
  final bool ingresa;

  factory PlanVehiculo.fromJson(Map m) => PlanVehiculo(
    placa: (m['placa'] ?? '').toString().trim(),
    ingresa: boolIngresa(m['ingresa']),
  );

  Map<String, dynamic> toJson() => {'placa': placa, 'ingresa': ingresa};

  /// «1», «si», true y 1 son «ingresa»; «0», «no», false y 0, «no ingresa».
  static bool boolIngresa(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = (v ?? '').toString().trim().toLowerCase();
    return !(s == '0' || s == 'no' || s == 'false' || s == 'n');
  }
}

/// Visita activa de la «Planificación de visitas» (portal web, bioseguridad
/// física), tal como la descarga la app para trabajar sin señal.
class PlanVisita {
  const PlanVisita({
    required this.id,
    required this.fecha,
    required this.granja,
    this.campania = '',
    this.nombreGranja = '',
    this.placa = '',
    this.placas = const [],
    this.vehiculos = const [],
    this.areaProveedor = '',
    this.areaProveedorValor = '',
    this.observacion = '',
    this.registradoPor = '',
    this.ruc = '',
    this.razonSocial = '',
    this.proceso = '',
    this.personas = const [],
    this.galpones = const [],
  });

  final int id;

  /// AAAA-MM-DD.
  final String fecha;
  final String granja;
  final String campania;
  final String nombreGranja;
  final String placa;

  /// Todas las placas de la visita (multi-vehículo). El servidor manda la lista
  /// en `placas`; si no la manda —planificación vieja o web con una sola placa—
  /// queda vacía y vale [placa].
  final List<String> placas;

  /// Los vehículos de la visita con su flag «ingresa a la granja». El servidor
  /// manda `vehiculos`; si no (planificación vieja) se arma de [placas] y todos
  /// ingresan.
  final List<PlanVehiculo> vehiculos;

  /// [TiposVisitante.area] o [TiposVisitante.proveedor]: de cuál de las dos
  /// listas salió [areaProveedorValor]. Vacío en las visitas programadas antes
  /// de que la web pidiera el dato.
  final String areaProveedor;

  /// El área o el proveedor elegido en la planificación, sin el tipo: la opción
  /// de la lista («Retiro de guano») o lo escrito a mano cuando se eligió
  /// «Otro».
  /// Se llama así y no `motivo` porque en la base la columna es `motivo` (igual
  /// que en el control de ingreso, que guarda ahí el área o el proveedor) y el
  /// motivo de la visita —el que se escribe— es [observacion]. Viéndolos juntos
  /// parecían el mismo dato, y no lo son.
  final String areaProveedorValor;

  /// Motivo de visita u observación escrita al programarla (el texto libre, en
  /// la columna `observacion`).
  final String observacion;

  /// Código del usuario que planificó en el portal web (`usuarioRegistrador`).
  /// Lo envía el servidor como `registradoPor`; no es el RUC del proveedor.
  final String registradoPor;

  /// RUC del proveedor vinculado a ese usuario (`san_usuario_proveedor.ruc`).
  final String ruc;

  /// Razón social del proveedor del RUC que planificó (`razonsocial` en
  /// `san_usuario_proveedor`). Vacía si el usuario no es proveedor.
  final String razonSocial;

  /// Proceso del proveedor que planificó. Vacío si no es proveedor.
  final String proceso;

  final List<PlanPersona> personas;

  /// Galpones definidos en la planificación web (no se piden en la app).
  final List<String> galpones;

  factory PlanVisita.fromJson(Map m) {
    final ps = m['personas'];
    return PlanVisita(
      id: int.tryParse('${m['id'] ?? 0}') ?? 0,
      fecha: (m['fecha'] ?? '').toString(),
      granja: (m['granja'] ?? '').toString(),
      campania: (m['campania'] ?? '').toString(),
      nombreGranja: (m['nombreGranja'] ?? '').toString(),
      placa: (m['placa'] ?? '').toString(),
      placas: _placasDe(m),
      vehiculos: _vehiculosDe(m),
      areaProveedor: (m['areaproveedor'] ?? '').toString(),
      areaProveedorValor: (m['motivo'] ?? '').toString(),
      observacion: (m['observacion'] ?? '').toString(),
      registradoPor: (m['registradoPor'] ?? '').toString().trim(),
      ruc: _rucNormalizado((m['ruc'] ?? '').toString()),
      razonSocial: (m['razonsocial'] ?? '').toString().trim(),
      proceso: (m['proceso'] ?? '').toString().trim(),
      personas: ps is List
          ? ps
                .whereType<Map>()
                .map(PlanPersona.fromJson)
                .where((p) => p.dni.isNotEmpty)
                .toList()
          : const [],
      galpones: _galponesDe(m),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'fecha': fecha,
    'granja': granja,
    'campania': campania,
    'nombreGranja': nombreGranja,
    'placa': placa,
    'placas': placas,
    'vehiculos': vehiculos.map((v) => v.toJson()).toList(),
    'areaproveedor': areaProveedor,
    'motivo': areaProveedorValor,
    'observacion': observacion,
    'registradoPor': registradoPor,
    'ruc': ruc,
    'razonsocial': razonSocial,
    'proceso': proceso,
    'personas': personas.map((p) => p.toJson()).toList(),
    'galpones': galpones,
  };

  /// Lista `galpones[]` o texto `galpon` separado por comas.
  static List<String> _galponesDe(Map m) {
    final out = <String>[];
    final gs = m['galpones'];
    if (gs is List) {
      for (final g in gs) {
        final s = g.toString().trim();
        if (s.isNotEmpty && !out.contains(s)) out.add(s);
      }
    }
    if (out.isEmpty) {
      final raw = (m['galpon'] ?? '').toString().trim();
      if (raw.isNotEmpty) {
        for (final part in raw.split(',')) {
          final s = part.trim();
          if (s.isNotEmpty && !out.contains(s)) out.add(s);
        }
      }
    }
    return out;
  }

  static final RegExp _rucOnceDigitos = RegExp(r'^\d{11}$');

  static String _rucNormalizado(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    return _rucOnceDigitos.hasMatch(d) ? d : '';
  }

  /// Placas de la visita desde el JSON: la lista `placas` y, si no viene, la
  /// única `placa`. Sin duplicados ni vacíos.
  static List<String> _placasDe(Map m) {
    final out = <String>[];
    final ps = m['placas'];
    if (ps is List) {
      for (final p in ps) {
        final s = p.toString().trim();
        if (s.isNotEmpty && !out.contains(s)) out.add(s);
      }
    }
    if (out.isEmpty) {
      final s = (m['placa'] ?? '').toString().trim();
      if (s.isNotEmpty) out.add(s);
    }
    return out;
  }

  /// Vehículos desde el JSON: `vehiculos` ([{placa, ingresa}]) y, si no viene,
  /// [placas] con todos ingresando. Sin duplicados ni vacíos.
  static List<PlanVehiculo> _vehiculosDe(Map m) {
    final out = <PlanVehiculo>[];
    final vistos = <String>{};
    final vs = m['vehiculos'];
    if (vs is List) {
      for (final v in vs.whereType<Map>()) {
        final veh = PlanVehiculo.fromJson(v);
        if (veh.placa.isEmpty) continue;
        final key = veh.placa.toUpperCase();
        if (vistos.add(key)) out.add(veh);
      }
    }
    if (out.isEmpty) {
      for (final p in _placasDe(m)) {
        if (vistos.add(p.toUpperCase())) out.add(PlanVehiculo(placa: p));
      }
    }
    return out;
  }

  /// Los vehículos a mostrar: [vehiculos] si vienen con el flag, o [placas]
  /// (todos ingresando) cuando el servidor no mandó el detalle.
  List<PlanVehiculo> get vehiculosEfectivos {
    if (vehiculos.isNotEmpty) return vehiculos;
    return [for (final p in _placasDe({'placas': placas, 'placa': placa})) PlanVehiculo(placa: p)];
  }

  /// Las placas a mostrar: la lista, o la placa suelta cuando no hay lista.
  List<String> get placasEfectivas {
    final veh = vehiculosEfectivos;
    if (veh.isNotEmpty) return [for (final v in veh) v.placa];
    final s = placa.trim();
    return s.isEmpty ? const [] : [s];
  }

  /// ¿La placa está programada para esta visita? Compara sin guiones ni espacios.
  PlanVehiculo? vehiculoDe(String placa) {
    final p = PlanDescarga.normPlaca(placa);
    if (p.isEmpty) return null;
    for (final v in vehiculosEfectivos) {
      if (PlanDescarga.normPlaca(v.placa) == p) return v;
    }
    return null;
  }

  /// «AHX-742, BCD-123» (vacío si la visita no lleva vehículo).
  String get placasTexto => placasEfectivas.join(', ');

  /// Identidad de la visita para saber si ya se usó: fecha, granja, campaña,
  /// área/proveedor y motivo. Mismo criterio que el servidor (`pv_clave_plan`):
  /// el vehículo no entra, porque puede cambiar sin ser otra visita.
  String get clave => [
    granja,
    fecha,
    campania,
    areaProveedor.toUpperCase(),
    areaProveedorValor.trim().toLowerCase(),
    observacion.trim().toLowerCase(),
  ].join('|');

  bool tieneDni(String dni) {
    final d = DocumentoPersona.normalizar(dni);
    return personas.any((p) => DocumentoPersona.normalizar(p.dni) == d);
  }

  /// «Área · Producción», o solo el texto si la visita no trae el tipo. Vacío
  /// cuando la planificación no pidió área ni proveedor.
  String get areaProveedorEtiqueta {
    if (areaProveedorValor.trim().isEmpty) return '';
    final tipo = TiposVisitante.etiqueta(areaProveedor);
    return tipo.isEmpty
        ? areaProveedorValor.trim()
        : '$tipo · ${areaProveedorValor.trim()}';
  }

  /// «26/09/2026 · 621 GJA SANTA TERESA · placa AHX-742».
  String get detalle {
    final f = DateTime.tryParse(fecha);
    final partes = <String>[
      f == null ? fecha : DateFormat('dd/MM/yyyy').format(f),
      [granja, nombreGranja].where((e) => e.trim().isNotEmpty).join(' '),
      if (placasTexto.isNotEmpty) 'placa $placasTexto',
    ];
    return partes.where((e) => e.trim().isNotEmpty).join(' · ');
  }
}

/// Resultado de buscar una placa o un DNI en la planificación.
/// [visita] es la coincidencia en la granja del registro; [otraGranja], la
/// visita de ese mismo día en otra granja cuando aquí no hay ninguna.
class PlanCoincidencia {
  const PlanCoincidencia({this.visita, this.otraGranja});

  final PlanVisita? visita;
  final PlanVisita? otraGranja;

  bool get planificado => visita != null;
}

/// Planificación descargada en el equipo (misma técnica que los catálogos:
/// JSON en SharedPreferences vía [StorageService]).
/// Criterio de coincidencia (igual al del servidor): visitas activas con la
/// misma fecha del registro y la misma granja (sin granja elegida se busca en
/// todas). La placa se compara sin guiones ni espacios; el DNI, por sus dígitos.
/// Todo es informativo: nada de esto bloquea el registro.
class PlanDescarga {
  const PlanDescarga({
    required this.desde,
    required this.hasta,
    required this.visitas,
    this.areaProveedorSoportado = true,
  });

  final String desde;
  final String hasta;
  final List<PlanVisita> visitas;

  /// ¿El servidor guarda y devuelve el área o proveedor de la visita?
  /// Es `false` cuando la base todavía no tiene las columnas `areaproveedor` y
  /// `motivo` (migración pendiente): la visita llega sin ese dato y la app no
  /// puede distinguirlo de una visita sin área registrada. Se conserva para
  /// poder verlo en el log en vez de suponerlo. Con un servidor viejo que no
  /// manda la bandera queda `true` y no se avisa de nada.
  final bool areaProveedorSoportado;

  static const vacia = PlanDescarga(desde: '', hasta: '', visitas: []);

  /// ¿Se descargó alguna vez desde el menú lateral? Con `false` la app no puede
  /// saber si hay visitas ni decir que no hay ninguna: solo pedir la descarga.
  bool get descargada => desde.isNotEmpty && hasta.isNotEmpty;

  /// ¿Lo descargado incluye esa fecha? Si no, la app no puede afirmar «no
  /// planificado» sin consultar en línea.
  bool cubre(String fechaYmd) =>
      desde.isNotEmpty &&
      hasta.isNotEmpty &&
      fechaYmd.compareTo(desde) >= 0 &&
      fechaYmd.compareTo(hasta) <= 0;

  factory PlanDescarga.fromJson(Map m) {
    final vs = m['visitas'];
    return PlanDescarga(
      desde: (m['desde'] ?? '').toString(),
      hasta: (m['hasta'] ?? '').toString(),
      // Solo se marca `false` cuando el servidor lo dice explícitamente.
      areaProveedorSoportado: m['conAreaproveedor'] != false,
      visitas: vs is List
          ? vs.whereType<Map>().map(PlanVisita.fromJson).toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'desde': desde,
    'hasta': hasta,
    'conAreaproveedor': areaProveedorSoportado,
    'visitas': visitas.map((v) => v.toJson()).toList(),
  };

  /// Visitas de lo descargado que sí traen el área o el proveedor.
  int get conAreaProveedor =>
      visitas.where((v) => v.areaProveedorValor.trim().isNotEmpty).length;

  static String normPlaca(String placa) =>
      placa.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  PlanCoincidencia _buscar(
    bool Function(PlanVisita v) coincide, {
    required String granja,
    required String fechaYmd,
  }) {
    PlanVisita? aqui;
    PlanVisita? otra;
    for (final v in visitas) {
      if (v.fecha != fechaYmd || !coincide(v)) continue;
      if (granja.isEmpty || v.granja == granja) {
        aqui ??= v;
      } else {
        otra ??= v;
      }
    }
    return PlanCoincidencia(visita: aqui, otraGranja: aqui == null ? otra : null);
  }

  PlanCoincidencia buscarPlaca(
    String placa, {
    required String granja,
    required String fechaYmd,
  }) {
    final p = normPlaca(placa);
    if (p.isEmpty) return const PlanCoincidencia();
    return _buscar(
      (v) => v.placasEfectivas.any((x) => normPlaca(x) == p),
      granja: granja,
      fechaYmd: fechaYmd,
    );
  }

  PlanCoincidencia buscarDni(
    String dni, {
    required String granja,
    required String fechaYmd,
  }) {
    final d = DocumentoPersona.normalizar(dni);
    if (d.isEmpty) return const PlanCoincidencia();
    return _buscar((v) => v.tieneDni(d), granja: granja, fechaYmd: fechaYmd);
  }

  /// Todas las visitas del día/granja donde figura el DNI (puede haber varias).
  List<PlanVisita> visitasPorDni(
    String dni, {
    required String granja,
    required String fechaYmd,
  }) {
    final d = DocumentoPersona.normalizar(dni);
    if (d.isEmpty) return const [];
    return _visitasQueCoinciden(
      (v) => v.tieneDni(d),
      granja: granja,
      fechaYmd: fechaYmd,
    );
  }

  /// Todas las visitas del día/granja con esa placa.
  List<PlanVisita> visitasPorPlaca(
    String placa, {
    required String granja,
    required String fechaYmd,
  }) {
    final p = normPlaca(placa);
    if (p.isEmpty) return const [];
    return _visitasQueCoinciden(
      (v) => v.placasEfectivas.any((x) => normPlaca(x) == p),
      granja: granja,
      fechaYmd: fechaYmd,
    );
  }

  List<PlanVisita> _visitasQueCoinciden(
    bool Function(PlanVisita v) coincide, {
    required String granja,
    required String fechaYmd,
  }) {
    final out = <PlanVisita>[];
    for (final v in visitas) {
      if (v.fecha != fechaYmd || !coincide(v)) continue;
      if (granja.isNotEmpty && v.granja != granja) continue;
      out.add(v);
    }
    return out;
  }

  /// Visitas de un día, para ofrecérselas a quien está en la garita.
  /// Con [granja] vacía se devuelven las de todas las granjas: es el caso de
  /// quien todavía no eligió granja. Se conserva el orden en que llegaron del
  /// servidor, que es el de la visita. [excluir] deja fuera las que ya se
  /// registraron (sus ids).
  /// Visita descargada por su id (al refrescar la planificación en pantalla).
  PlanVisita? visitaPorId(int? id) {
    if (id == null) return null;
    for (final v in visitas) {
      if (v.id == id) return v;
    }
    return null;
  }

  List<PlanVisita> delDia({
    required String fechaYmd,
    required String granja,
    Set<String>? excluir,
  }) {
    return [
      for (final v in visitas)
        if (v.fecha == fechaYmd &&
            (granja.isEmpty || v.granja == granja) &&
            !(excluir?.contains(v.id.toString()) ?? false))
          v,
    ];
  }
}

class PlanVisitasService {
  PlanVisitasService({ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;

  /// Días que se descargan desde hoy (hoy incluido).
  static const int diasDescarga = 7;

  /// Lo descargado en el equipo (vacío si nunca se descargó o no se entiende).
  static PlanDescarga local(StorageService storage) {
    final s = storage.getPlanVisitasJson();
    if (s == null || s.isEmpty) return PlanDescarga.vacia;
    try {
      final m = jsonDecode(s);
      return m is Map ? PlanDescarga.fromJson(m) : PlanDescarga.vacia;
    } catch (_) {
      return PlanDescarga.vacia;
    }
  }

  /// Descarga las visitas activas de hoy y los próximos días y las guarda.
  /// Devuelve `false` sin tocar lo guardado si no hay red, el servidor no
  /// responde o la planificación aún no está instalada en el servidor.
  Future<bool> descargar(StorageService storage) async {
    final hoy = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final data = await _api.descargarPlanificacion(
      desde: hoy,
      dias: diasDescarga,
    );
    if (data == null) return false;
    final descarga = PlanDescarga.fromJson(data);
    await storage.savePlanVisitas(jsonEncode(descarga.toJson()));
    await ProveedorHistorialService(storage).ingestarDesdePlan(descarga);
    // Rastro para diagnosticar sin adivinar: si el área o el proveedor no
    // aparecen en la pantalla, esto dice si el servidor los está mandando.
    debugPrint(
      '[planificación] ${descarga.visitas.length} visita(s) del '
      '${descarga.desde} al ${descarga.hasta}; con área/proveedor: '
      '${descarga.conAreaProveedor}; servidor con las columnas: '
      '${descarga.areaProveedorSoportado}',
    );
    if (!descarga.areaProveedorSoportado) {
      debugPrint(
        '[planificación] el servidor no tiene las columnas areaproveedor/'
        'motivo: las visitas llegan sin área ni proveedor. Falta correr la '
        'migración en esa base.',
      );
    }
    return true;
  }
}
