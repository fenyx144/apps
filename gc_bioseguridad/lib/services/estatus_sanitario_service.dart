import 'package:intl/intl.dart';

import '../utils/documento_persona.dart';
import 'api_service.dart';
import 'plan_visitas_service.dart';

/// Granja con estatus sanitario vigente de la que viene una persona.
/// La produce el portal web (módulo «Estatus Sanitario Granja»): mientras esa
/// granja esté en sospecha o confirmado, quien haya ingresado a ella lleva la
/// etiqueta de situación especial al entrar a otra granja.
class EstatusOrigen {
  const EstatusOrigen({
    required this.granja,
    this.nombreGranja = '',
    this.campania = '',
    this.estado = '',
    this.estadoLabel = '',
    this.fechaIngreso = '',
    this.horaIngreso = '',
    this.fechaFin = '',
    this.ingresa = true,
  });

  final String granja;
  final String nombreGranja;
  final String campania;

  /// `SOSPECHA` o `CONFIRMADO`.
  final String estado;

  /// «Sospecha» o «Confirmado».
  final String estadoLabel;

  /// AAAA-MM-DD del ingreso a esa granja.
  final String fechaIngreso;

  /// HH:MM:SS del ingreso (puede venir vacío).
  final String horaIngreso;

  /// Último día de vigencia del estatus.
  final String fechaFin;

  /// Solo para vehículos: si ese ingreso a la granja en situación especial fue
  /// con el vehículo dentro (lo marca el switch del portal). En personas es
  /// `true` siempre.
  final bool ingresa;

  /// Nombre legible sin el tramo de campaña que a veces trae el servidor
  /// («Granja C=190» «Granja»).
  static String sinCampaniaEnNombre(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return t;
    final m = RegExp(r'\s+C=', caseSensitive: false).firstMatch(t);
    if (m == null) return t;
    final corto = t.substring(0, m.start).trim();
    return corto.isEmpty ? t : corto;
  }

  factory EstatusOrigen.fromJson(Map m) => EstatusOrigen(
    granja: (m['granja'] ?? '').toString().trim(),
    nombreGranja: (m['nombreGranja'] ?? '').toString().trim(),
    campania: (m['campania'] ?? '').toString().trim(),
    estado: (m['estado'] ?? '').toString().trim(),
    estadoLabel: (m['estadoLabel'] ?? '').toString().trim(),
    fechaIngreso: (m['fechaIngreso'] ?? '').toString().trim(),
    horaIngreso: (m['horaIngreso'] ?? '').toString().trim(),
    fechaFin: (m['fechaFin'] ?? '').toString().trim(),
    ingresa: PlanVehiculo.boolIngresa(m['ingresa'] ?? 1),
  );

  String get _nombreGranjaMostrar => sinCampaniaEnNombre(nombreGranja);

  /// «621 SANTA TERESA»: código y nombre, sin el estado.
  String get granjaTexto => [granja, _nombreGranjaMostrar]
      .where((e) => e.trim().isNotEmpty)
      .join(' ');

  /// «Sospecha» o «Confirmado» (el código si el servidor no mandó la etiqueta).
  String get estadoTexto => estadoLabel.isNotEmpty ? estadoLabel : estado;

  /// «121 ALMACEN PJ1 · Sospecha».
  String get etiqueta {
    final partes = <String>[
      granjaTexto,
      estadoLabel.isNotEmpty ? estadoLabel : estado,
    ];
    return partes.where((e) => e.trim().isNotEmpty).join(' · ');
  }

  /// «28/09/2026» del ingreso, o el texto tal cual si no se entiende.
  String get fechaIngresoCorta => _fechaCorta(fechaIngreso);

  String get fechaFinCorta => _fechaCorta(fechaFin);

  /// Días transcurridos desde el ingreso hasta [hoy].
  /// `null` cuando la fecha no se entiende. Un ingreso de hoy da `0`, y una
  /// fecha futura (reloj corrido) también: el aviso nunca muestra días
  /// negativos.
  int? diasDesdeIngreso(DateTime hoy) {
    final f = DateTime.tryParse(fechaIngreso);
    if (f == null) return null;
    final ingreso = DateTime(f.year, f.month, f.day);
    final actual = DateTime(hoy.year, hoy.month, hoy.day);
    final dias = actual.difference(ingreso).inDays;
    return dias < 0 ? 0 : dias;
  }

  /// «hoy» o «hace 3 días», para el aviso de situación especial. Vacío si la
  /// fecha del ingreso no se entiende.
  String haceTexto(DateTime hoy) {
    final dias = diasDesdeIngreso(hoy);
    if (dias == null) return '';
    if (dias == 0) return 'hoy';
    return dias == 1 ? 'hace 1 día' : 'hace $dias días';
  }

  static String _fechaCorta(String ymd) {
    if (ymd.isEmpty) return '';
    final f = DateTime.tryParse(ymd);
    return f == null ? ymd : DateFormat('dd/MM/yyyy').format(f);
  }

  /// Fecha corta para reusar desde las pantallas (mismo formato que las tarjetas).
  static String fechaCorta(String ymd) => _fechaCorta(ymd);
}

/// Granja visitada hoy con edad mayor que la del registro actual.
class OrdenEdadOrigen {
  const OrdenEdadOrigen({
    required this.granja,
    this.nombreGranja = '',
    this.campania = '',
    this.edad = 0,
    this.horaIngreso = '',
  });

  final String granja;
  final String nombreGranja;
  final String campania;
  final int edad;
  final String horaIngreso;

  factory OrdenEdadOrigen.fromJson(Map m) => OrdenEdadOrigen(
    granja: (m['granja'] ?? '').toString().trim(),
    nombreGranja: (m['nombreGranja'] ?? '').toString().trim(),
    campania: (m['campania'] ?? '').toString().trim(),
    edad: int.tryParse(m['edad']?.toString() ?? '') ?? 0,
    horaIngreso: (m['horaIngreso'] ?? '').toString().trim(),
  );

  String get granjaTexto => [
    granja,
    EstatusOrigen.sinCampaniaEnNombre(nombreGranja),
  ].where((e) => e.trim().isNotEmpty).join(' ');

  String get etiqueta {
    final edadTxt = edad > 0 ? '$edad días' : '';
    return [
      granjaTexto,
      if (edadTxt.isNotEmpty) edadTxt,
    ].where((e) => e.trim().isNotEmpty).join(' · ');
  }
}

/// Aviso de orden de edad (visitar granjas de menor a mayor edad).
class OrdenEdadDni {
  const OrdenEdadDni({required this.enRiesgo, this.origenes = const []});

  final bool enRiesgo;
  final List<OrdenEdadOrigen> origenes;

  static OrdenEdadDni? fromJson(dynamic item) {
    if (item is! Map || item['enRiesgo'] is! bool) return null;
    final lista = item['origenes'];
    return OrdenEdadDni(
      enRiesgo: item['enRiesgo'] == true,
      origenes: lista is List
          ? lista.whereType<Map>().map(OrdenEdadOrigen.fromJson).toList()
          : const [],
    );
  }

  /// Texto corto para la tabla; el detalle va en el diálogo al tocar.
  String avisoIngresoCorto(String sujeto) =>
      '$sujeto visitó una granja de mayor edad';

  String avisoIngreso(String sujeto) {
    if (origenes.isEmpty) {
      return '$sujeto visitó hoy una granja de mayor edad';
    }
    final extra = origenes.length - 1;
    final cola = extra <= 0
        ? ''
        : ' (+$extra ${extra == 1 ? 'granja más' : 'granjas más'})';
    return '$sujeto visitó hoy una granja de mayor edad (${origenes.first.etiqueta})$cola';
  }

  String detalleOrigen(String sujeto, OrdenEdadOrigen o) {
    final hora = o.horaIngreso.length >= 5
        ? o.horaIngreso.substring(0, 5)
        : o.horaIngreso;
    final cuando = hora.isNotEmpty ? ' a las $hora' : '';
    final edadTxt = o.edad > 0 ? ' · ${o.edad} días' : '';
    return '$sujeto ingresó hoy$cuando a ${o.granjaTexto}$edadTxt.';
  }
}

/// Bloque «orden de edad» de la consulta de ingreso.
class OrdenEdadConsulta {
  const OrdenEdadConsulta({
    this.disponible = false,
    this.edadGranja,
    this.dnis = const {},
    this.placas = const {},
  });

  final bool disponible;
  final int? edadGranja;
  final Map<String, OrdenEdadDni> dnis;
  final Map<String, OrdenEdadDni> placas;

  static OrdenEdadConsulta? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final dnis = <String, OrdenEdadDni>{};
    final rawD = raw['dnis'];
    if (rawD is Map) {
      rawD.forEach((k, v) {
        final e = OrdenEdadDni.fromJson(v);
        if (e != null) dnis[k.toString()] = e;
      });
    }
    final placas = <String, OrdenEdadDni>{};
    final rawP = raw['placas'];
    if (rawP is Map) {
      rawP.forEach((k, v) {
        final e = OrdenEdadDni.fromJson(v);
        if (e != null) placas[k.toString()] = e;
      });
    }
    final edad = int.tryParse(raw['edadGranja']?.toString() ?? '');
    return OrdenEdadConsulta(
      disponible: raw['disponible'] == true,
      edadGranja: edad != null && edad > 0 ? edad : null,
      dnis: dnis,
      placas: placas,
    );
  }
}

/// Estatus sanitario que afecta a un DNI en el registro de ingreso.
class EstatusDni {
  const EstatusDni({required this.enRiesgo, this.origenes = const []});

  /// `true` cuando el DNI ingresó a otra granja que hoy está en situación
  /// especial: es lo que enciende la etiqueta.
  final bool enRiesgo;

  final List<EstatusOrigen> origenes;

  static EstatusDni? fromJson(dynamic item) {
    if (item is! Map) return null;
    final rawRiesgo = item['enRiesgo'];
    final enRiesgo = rawRiesgo == true ||
        rawRiesgo == 1 ||
        rawRiesgo == '1' ||
        rawRiesgo == 'true';
    final lista = item['origenes'];
    return EstatusDni(
      enRiesgo: enRiesgo,
      origenes: lista is List
          ? lista.whereType<Map>().map(EstatusOrigen.fromJson).toList()
          : const [],
    );
  }

  /// Detalle para el aviso al tocar la etiqueta.
  String mensaje(String sujeto) {
    if (origenes.isEmpty) {
      return '$sujeto viene de una granja en situación especial.';
    }
    final cola = _cola();
    return '${origenes.map((o) => o.etiqueta).join(' / ')}$cola';
  }

  /// La frase del diálogo para un origen concreto:
  /// «Juan Pérez ingresó el día 28/09/2026 a la granja 621 SANTA TERESA, la cual
  /// se encuentra en situación especial de Sospecha.»
  String situacionDe(String sujeto, EstatusOrigen o) =>
      situacionTrozos(sujeto, o).join();

  /// La misma frase partida en tres: lo de antes del estado, el estado y el
  /// cierre con la vigencia. El diálogo resalta el estado con estas piezas.
  List<String> situacionTrozos(String sujeto, EstatusOrigen o) {
    final fecha = o.fechaIngresoCorta;
    final antes = StringBuffer('$sujeto ingresó');
    if (fecha.isNotEmpty) antes.write(' el día $fecha');
    antes.write(' a la granja ${o.granjaTexto}, la cual se encuentra en '
        'situación especial de ');
    final fin = o.fechaFinCorta;
    return [
      antes.toString(),
      o.estadoTexto,
      '.${fin.isNotEmpty ? ' Vigente hasta el $fin.' : ''}',
    ];
  }

  /// «Esta persona ingresó hace 3 días a una granja en situación especial».
  /// El «hace …» sale del ingreso ([EstatusOrigen.haceTexto]): «hoy» si fue el
  /// mismo día y, si no hay fecha entendible, se omite. Con varias granjas se
  /// toma el ingreso más reciente, que es el contacto que ocurrió hace menos.
  String avisoIngreso(String sujeto, {DateTime? ahora}) {
    final hace = _haceDelIngresoMasReciente(ahora ?? DateTime.now());
    return '$sujeto ingresó ${hace.isEmpty ? '' : '$hace '}'
        'a una granja en situación especial';
  }

  /// «hoy» / «hace N días» del ingreso más reciente entre los orígenes.
  String _haceDelIngresoMasReciente(DateTime ahora) {
    int? menor;
    for (final o in origenes) {
      final dias = o.diasDesdeIngreso(ahora);
      if (dias == null) continue;
      if (menor == null || dias < menor) menor = dias;
    }
    if (menor == null) return '';
    if (menor == 0) return 'hoy';
    return menor == 1 ? 'hace 1 día' : 'hace $menor días';
  }

  /// Cuántas granjas más acompañan al primer origen: « (+2 granjas más)».
  String _cola() {
    final extra = origenes.length - 1;
    if (extra <= 0) return '';
    return ' (+$extra ${extra == 1 ? 'granja más' : 'granjas más'})';
  }
}

/// Estatus sanitario de la granja que se está registrando.
class EstatusGranja {
  const EstatusGranja({
    required this.granja,
    this.campania = '',
    this.estado = '',
    this.estadoLabel = '',
    this.fechaInicio = '',
    this.fechaFin = '',
    this.galpones = const [],
  });

  final String granja;
  final String campania;
  final String estado;
  final String estadoLabel;
  final String fechaInicio;
  final String fechaFin;
  final List<String> galpones;

  String get fechaInicioCorta => EstatusOrigen.fechaCorta(fechaInicio);

  String get fechaFinCorta => EstatusOrigen.fechaCorta(fechaFin);

  /// «Desde dd/MM/yyyy Hasta dd/MM/yyyy» para la tarjeta de aviso de la granja.
  String get rangoFechasEtiqueta {
    final i = fechaInicioCorta;
    final f = fechaFinCorta;
    if (i.isNotEmpty && f.isNotEmpty) return 'Desde $i Hasta $f';
    if (i.isNotEmpty) return 'Desde $i';
    if (f.isNotEmpty) return 'Hasta $f';
    return '';
  }

  static EstatusGranja? fromJson(dynamic item) {
    if (item is! Map) return null;
    final gps = item['galpones'];
    return EstatusGranja(
      granja: (item['granja'] ?? '').toString().trim(),
      campania: (item['campania'] ?? '').toString().trim(),
      estado: (item['estado'] ?? '').toString().trim(),
      estadoLabel: (item['estadoLabel'] ?? '').toString().trim(),
      fechaInicio: (item['fechaInicio'] ?? '').toString().trim(),
      fechaFin: (item['fechaFin'] ?? '').toString().trim(),
      galpones: gps is List ? gps.map((e) => e.toString()).toList() : const [],
    );
  }
}

/// Respuesta completa de la consulta del estatus sanitario.
class EstatusConsulta {
  const EstatusConsulta({
    this.granjaEnEstatus,
    this.dnis = const {},
    this.placas = const {},
    this.ordenEdad,
  });

  /// Estatus de la granja del registro (`null` si no tiene ninguno vigente).
  final EstatusGranja? granjaEnEstatus;

  /// Estatus por DNI; un DNI sin novedad llega con `enRiesgo == false`.
  final Map<String, EstatusDni> dnis;

  /// Estatus por placa normalizada (mayúsculas, sin guiones ni espacios); una
  /// placa sin novedad llega con `enRiesgo == false`.
  final Map<String, EstatusDni> placas;

  final OrdenEdadConsulta? ordenEdad;

  static EstatusConsulta fromJson(Map m) {
    final dnis = <String, EstatusDni>{};
    final raw = m['dnis'];
    if (raw is Map) {
      raw.forEach((k, v) {
        final e = EstatusDni.fromJson(v);
        if (e == null) return;
        final digits = k.toString().replaceAll(RegExp(r'\D'), '');
        if (digits.isEmpty) return;
        final dni = digits.length > 8
            ? digits.substring(digits.length - 8)
            : digits.padLeft(8, '0');
        dnis[dni] = e;
      });
    }
    final placas = <String, EstatusDni>{};
    final rawP = m['placas'];
    if (rawP is Map) {
      rawP.forEach((k, v) {
        final e = EstatusDni.fromJson(v);
        if (e != null) placas[k.toString()] = e;
      });
    }
    return EstatusConsulta(
      granjaEnEstatus: EstatusGranja.fromJson(m['granjaEnEstatus']),
      dnis: dnis,
      placas: placas,
      ordenEdad: OrdenEdadConsulta.fromJson(m['ordenEdad']),
    );
  }
}

/// Busca el estatus de un documento en el mapa devuelto por el servidor.
EstatusDni? estatusSanitarioDeDocumento(
  Map<String, EstatusDni> map,
  String documento,
) {
  if (map.isEmpty) return null;
  final norm = DocumentoPersona.normalizar(documento);
  if (norm.isNotEmpty && map.containsKey(norm)) {
    return map[norm];
  }
  for (final e in map.entries) {
    if (DocumentoPersona.normalizar(e.key) == norm) {
      return e.value;
    }
  }
  final digits = documento.replaceAll(RegExp(r'\D'), '');
  if (digits.length >= 8) {
    final d8 = digits.length > 8
        ? digits.substring(digits.length - 8)
        : digits.padLeft(8, '0');
    return map[d8];
  }
  return null;
}

OrdenEdadDni? ordenEdadDeDocumento(
  Map<String, OrdenEdadDni> map,
  String documento,
) {
  if (map.isEmpty) return null;
  final norm = DocumentoPersona.normalizar(documento);
  if (norm.isNotEmpty && map.containsKey(norm)) {
    return map[norm];
  }
  for (final e in map.entries) {
    if (DocumentoPersona.normalizar(e.key) == norm) {
      return e.value;
    }
  }
  return map[documento.replaceAll(RegExp(r'\D'), '')];
}

/// Consulta al portal web del estatus sanitario de la granja y de los DNIs.
/// Es solo informativa: la app muestra la etiqueta de situación especial y
/// guarda el ingreso igual. Si no hay red, el servidor no tiene las tablas o la
/// respuesta no se entiende, devuelve `null` y la pantalla queda en estado
/// neutro, sin avisos.
class EstatusSanitarioService {
  EstatusSanitarioService({ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;

  Future<EstatusConsulta?> consultar({
    required String fechaYmd,
    String granja = '',
    String campania = '',
    List<String> dnis = const [],
    List<String> placas = const [],
  }) async {
    if (granja.isEmpty && dnis.isEmpty && placas.isEmpty) return null;
    final data = await _api.consultarEstatusSanitario(
      fechaYmd: fechaYmd,
      granja: granja,
      campania: campania,
      dnis: dnis,
      placas: placas,
    );
    if (data == null) return null;
    try {
      return EstatusConsulta.fromJson(data);
    } catch (_) {
      return null;
    }
  }
}
