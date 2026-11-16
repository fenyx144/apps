import 'dart:convert';

import 'package:intl/intl.dart';

import '../utils/dni_utils.dart';
import 'api_service.dart';
import 'estatus_sanitario_service.dart';
import 'ingreso_presencia_service.dart';
import 'plan_visitas_service.dart';
import 'storage_service.dart';

/// Catálogo de avisos del ingreso descargado para trabajar sin señal.
/// Con él la app calcula en el equipo lo mismo que la consulta en línea
/// (`consultar_estatus_sanitario_*`): granja en situación especial, persona o
/// vehículo que ingresó a una granja en situación especial y visita previa
/// (hoy) a una granja de mayor edad. Se completa con los ingresos guardados en
/// este equipo, que todavía pueden no estar en el servidor.
class AvisosIngresoCatalogo {
  const AvisosIngresoCatalogo({
    this.fecha = '',
    this.estatusDisponible = false,
    this.granjasEstatus = const {},
    this.riesgoDnis = const {},
    this.riesgoPlacas = const {},
    this.edades = const {},
    this.nombresGranja = const {},
    this.visitasHoyDnis = const {},
    this.visitasHoyPlacas = const {},
  });

  static const vacio = AvisosIngresoCatalogo();

  /// Día de la descarga (AAAA-MM-DD): las visitas de hoy y las edades solo
  /// valen para ese día.
  final String fecha;
  final bool estatusDisponible;
  final Map<String, Map<String, dynamic>> granjasEstatus;
  final Map<String, List<Map<String, dynamic>>> riesgoDnis;
  final Map<String, List<Map<String, dynamic>>> riesgoPlacas;

  /// «granja|campaña» edad en días.
  final Map<String, int> edades;
  final Map<String, String> nombresGranja;
  final Map<String, List<Map<String, dynamic>>> visitasHoyDnis;
  final Map<String, List<Map<String, dynamic>>> visitasHoyPlacas;

  bool get estaVacio => fecha.isEmpty;

  static Map<String, List<Map<String, dynamic>>> _listas(dynamic raw) {
    final out = <String, List<Map<String, dynamic>>>{};
    if (raw is! Map) return out;
    raw.forEach((k, v) {
      if (v is! List) return;
      out[k.toString()] = [
        for (final e in v)
          if (e is Map) Map<String, dynamic>.from(e),
      ];
    });
    return out;
  }

  factory AvisosIngresoCatalogo.fromJson(Map m) {
    final granjas = <String, Map<String, dynamic>>{};
    final rawG = m['granjasEstatus'];
    if (rawG is Map) {
      rawG.forEach((k, v) {
        if (v is Map) granjas[k.toString()] = Map<String, dynamic>.from(v);
      });
    }
    final edades = <String, int>{};
    final rawE = m['edades'];
    if (rawE is Map) {
      rawE.forEach((k, v) {
        final n = int.tryParse(v.toString());
        if (n != null && n > 0) edades[k.toString()] = n;
      });
    }
    final nombres = <String, String>{};
    final rawN = m['nombresGranja'];
    if (rawN is Map) {
      rawN.forEach((k, v) => nombres[k.toString()] = v.toString());
    }
    return AvisosIngresoCatalogo(
      fecha: (m['fecha'] ?? '').toString(),
      estatusDisponible: m['estatusDisponible'] == true,
      granjasEstatus: granjas,
      riesgoDnis: _listas(m['riesgoDnis']),
      riesgoPlacas: _listas(m['riesgoPlacas']),
      edades: edades,
      nombresGranja: nombres,
      visitasHoyDnis: _listas(m['visitasHoyDnis']),
      visitasHoyPlacas: _listas(m['visitasHoyPlacas']),
    );
  }

  Map<String, dynamic> toJson() => {
    'fecha': fecha,
    'estatusDisponible': estatusDisponible,
    'granjasEstatus': granjasEstatus,
    'riesgoDnis': riesgoDnis,
    'riesgoPlacas': riesgoPlacas,
    'edades': edades,
    'nombresGranja': nombresGranja,
    'visitasHoyDnis': visitasHoyDnis,
    'visitasHoyPlacas': visitasHoyPlacas,
  };
}

class AvisosIngresoOfflineService {
  AvisosIngresoOfflineService({ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;

  /// Días hacia atrás en que un ingreso a una granja en situación especial
  /// sigue contando (igual que `BIO_ES_DIAS_VENTANA` en el servidor).
  static const int diasVentana = 30;

  static String normGranja(String g) {
    final t = g.trim();
    if (t.isEmpty) return '';
    final p = t.padLeft(3, '0');
    return p.substring(0, 3);
  }

  static String normCampania(String c) {
    final t = c.replaceAll(RegExp(r'\s+'), '');
    if (t.isEmpty) return '';
    final p = t.padLeft(3, '0');
    return p.substring(p.length - 3);
  }

  /// Clave de 8 dígitos (la misma que usa el servidor para el estatus).
  static String dni8(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return '';
    return d.length > 8 ? d.substring(d.length - 8) : d.padLeft(8, '0');
  }

  static AvisosIngresoCatalogo local(StorageService storage) {
    final s = storage.getAvisosIngresoJson();
    if (s == null || s.isEmpty) return AvisosIngresoCatalogo.vacio;
    try {
      final m = jsonDecode(s);
      return m is Map
          ? AvisosIngresoCatalogo.fromJson(m)
          : AvisosIngresoCatalogo.vacio;
    } catch (_) {
      return AvisosIngresoCatalogo.vacio;
    }
  }

  /// «granja|campaña» de las granjas de trabajo del equipo, para que el
  /// servidor calcule su edad aunque hoy no tengan visitas planificadas.
  static List<String> destinosDe(StorageService storage) {
    final granjas = storage.getGranjasTrabajo().map(normGranja).toSet();
    if (granjas.isEmpty) return const [];
    final out = <String>{};
    for (final c in storage.getCencosListaLocal()) {
      final cod = (c['codigo'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      if (cod.length < 6) continue;
      final g = cod.substring(0, 3);
      if (!granjas.contains(g)) continue;
      out.add('$g|${cod.substring(3, 6)}');
    }
    return out.take(60).toList();
  }

  /// Descarga el catálogo del día y lo guarda. `false` sin tocar lo guardado
  /// si no hay red o el servidor no lo tiene.
  Future<bool> descargar(StorageService storage) async {
    final hoy = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final data = await _api.descargarAvisosIngreso(
      fechaYmd: hoy,
      destinos: destinosDe(storage),
    );
    if (data == null) return false;
    final cat = AvisosIngresoCatalogo.fromJson(data);
    await storage.saveAvisosIngresoJson(jsonEncode(cat.toJson()));
    return true;
  }

  /// Avisos calculados en el equipo, con la misma forma que la respuesta en
  /// línea. `null` si no hay catálogo ni ingresos locales con qué calcular.
  static EstatusConsulta? calcular({
    required StorageService storage,
    required String fechaYmd,
    String granja = '',
    String campania = '',
    List<String> dnis = const [],
    List<String> placas = const [],
  }) {
    final cat = local(storage);
    final g3 = normGranja(granja);
    final camp = normCampania(campania);
    final hoy = DateTime.tryParse(fechaYmd) ?? DateTime.now();
    final desde = DateFormat(
      'yyyy-MM-dd',
    ).format(hoy.subtract(const Duration(days: diasVentana - 1)));

    final locales = _ingresosLocales(storage, desde, fechaYmd);

    EstatusGranja? granjaEstatus;
    if (g3.isNotEmpty && cat.granjasEstatus[g3] != null) {
      granjaEstatus = EstatusGranja.fromJson(cat.granjasEstatus[g3]);
    }

    final porDni = <String, EstatusDni>{};
    final porPlaca = <String, EstatusDni>{};
    if (cat.estatusDisponible) {
      for (final doc in dnis) {
        final clave = dni8(doc);
        final origenes = <EstatusOrigen>[];
        final vistos = <String>{};
        for (final o in cat.riesgoDnis[clave] ?? const []) {
          final og = normGranja((o['granja'] ?? '').toString());
          if (og == g3 || !vistos.add(og)) continue;
          origenes.add(EstatusOrigen.fromJson(o));
        }
        for (final r in locales) {
          if (r.granja == g3 || vistos.contains(r.granja)) continue;
          if (!r.dnis.contains(clave)) continue;
          final o = _origenLocal(cat, r);
          if (o == null) continue;
          vistos.add(r.granja);
          origenes.add(o);
        }
        porDni[clave] = EstatusDni(
          enRiesgo: origenes.isNotEmpty,
          origenes: origenes,
        );
      }
      for (final p in placas) {
        final clave = PlanDescarga.normPlaca(p);
        if (clave.isEmpty) continue;
        final origenes = <EstatusOrigen>[];
        final vistos = <String>{};
        for (final o in cat.riesgoPlacas[clave] ?? const []) {
          final og = normGranja((o['granja'] ?? '').toString());
          if (og == g3 || !vistos.add(og)) continue;
          origenes.add(EstatusOrigen.fromJson(o));
        }
        for (final r in locales) {
          if (r.granja == g3 || vistos.contains(r.granja)) continue;
          if (!r.placas.contains(clave)) continue;
          final o = _origenLocal(cat, r);
          if (o == null) continue;
          vistos.add(r.granja);
          origenes.add(o);
        }
        porPlaca[clave] = EstatusDni(
          enRiesgo: origenes.isNotEmpty,
          origenes: origenes,
        );
      }
    }

    final orden = _ordenEdad(
      cat: cat,
      locales: locales,
      fechaYmd: fechaYmd,
      granja: g3,
      campania: camp,
      dnis: dnis,
      placas: placas,
    );

    if (cat.estaVacio && locales.isEmpty) return null;
    return EstatusConsulta(
      granjaEnEstatus: granjaEstatus,
      dnis: porDni,
      placas: porPlaca,
      ordenEdad: orden,
    );
  }

  static EstatusOrigen? _origenLocal(
    AvisosIngresoCatalogo cat,
    _IngresoLocal r,
  ) {
    final e = cat.granjasEstatus[r.granja];
    if (e == null) return null;
    final inicio = (e['fechaInicio'] ?? '').toString();
    if (inicio.isNotEmpty && r.fecha.compareTo(inicio) < 0) return null;
    return EstatusOrigen(
      granja: r.granja,
      nombreGranja: (e['nombreGranja'] ?? cat.nombresGranja[r.granja] ?? '')
          .toString(),
      campania: r.campania,
      estado: (e['estado'] ?? '').toString(),
      estadoLabel: (e['estadoLabel'] ?? '').toString(),
      fechaIngreso: r.fecha,
      horaIngreso: r.hora,
      fechaFin: (e['fechaFin'] ?? '').toString(),
    );
  }

  static OrdenEdadConsulta _ordenEdad({
    required AvisosIngresoCatalogo cat,
    required List<_IngresoLocal> locales,
    required String fechaYmd,
    required String granja,
    required String campania,
    required List<String> dnis,
    required List<String> placas,
  }) {
    final edadDest = cat.edades['$granja|$campania'];
    if (granja.isEmpty ||
        campania.isEmpty ||
        edadDest == null ||
        cat.fecha != fechaYmd) {
      return const OrdenEdadConsulta();
    }
    final deHoy = [
      for (final r in locales)
        if (r.fecha == fechaYmd) r,
    ];

    List<OrdenEdadOrigen> mayores(List<Map<String, dynamic>> visitas) {
      final out = <OrdenEdadOrigen>[];
      final vistos = <String>{};
      for (final v in visitas) {
        final g = normGranja((v['granja'] ?? '').toString());
        final c = normCampania((v['campania'] ?? '').toString());
        if (g.isEmpty || g == granja || !vistos.add('$g|$c')) continue;
        final edad = cat.edades['$g|$c'];
        if (edad == null || edad <= edadDest) continue;
        out.add(
          OrdenEdadOrigen(
            granja: g,
            nombreGranja: cat.nombresGranja[g] ?? '',
            campania: c,
            edad: edad,
            horaIngreso: (v['hora'] ?? '').toString(),
          ),
        );
      }
      return out;
    }

    final porDni = <String, OrdenEdadDni>{};
    for (final doc in dnis) {
      final digits = doc.replaceAll(RegExp(r'\D'), '');
      final clave8 = dni8(doc);
      final visitas = [
        ...?cat.visitasHoyDnis[digits],
        if (clave8 != digits) ...?cat.visitasHoyDnis[clave8],
        for (final r in deHoy)
          if (r.dnis.contains(clave8))
            {'granja': r.granja, 'campania': r.campania, 'hora': r.hora},
      ];
      final lista = mayores(visitas);
      porDni[digits.isEmpty ? doc : digits] = OrdenEdadDni(
        enRiesgo: lista.isNotEmpty,
        origenes: lista,
      );
    }
    final porPlaca = <String, OrdenEdadDni>{};
    for (final p in placas) {
      final clave = PlanDescarga.normPlaca(p);
      if (clave.isEmpty) continue;
      final visitas = [
        ...?cat.visitasHoyPlacas[clave],
        for (final r in deHoy)
          if (r.placas.contains(clave))
            {'granja': r.granja, 'campania': r.campania, 'hora': r.hora},
      ];
      final lista = mayores(visitas);
      porPlaca[clave] = OrdenEdadDni(
        enRiesgo: lista.isNotEmpty,
        origenes: lista,
      );
    }
    return OrdenEdadConsulta(
      disponible: true,
      edadGranja: edadDest,
      dnis: porDni,
      placas: porPlaca,
    );
  }

  static List<_IngresoLocal> _ingresosLocales(
    StorageService storage,
    String desde,
    String hasta,
  ) {
    final out = <_IngresoLocal>[];
    for (final r in storage.getMyRecords()) {
      if ((r['reporte'] ?? '').toString() != 'ingreso') continue;
      final fecha = (r['fecha'] ?? '').toString();
      if (fecha.compareTo(desde) < 0 || fecha.compareTo(hasta) > 0) continue;
      final g = normGranja((r['granja'] ?? '').toString());
      if (g.isEmpty) continue;
      final reg = Map<String, dynamic>.from((r['registro'] as Map?) ?? {});
      out.add(
        _IngresoLocal(
          granja: g,
          campania: normCampania((r['campania'] ?? '').toString()),
          fecha: fecha,
          hora: (reg['hora'] ?? '').toString(),
          dnis: {
            for (final p in parseDnisEntradas(reg['dnis'])) dni8(p.dni),
          }..remove(''),
          placas: {
            for (final v in IngresoPresenciaService.vehiculosIngresadosDe(reg))
              v.clave,
          },
        ),
      );
    }
    return out;
  }
}

class _IngresoLocal {
  const _IngresoLocal({
    required this.granja,
    required this.campania,
    required this.fecha,
    required this.hora,
    required this.dnis,
    required this.placas,
  });

  final String granja;
  final String campania;
  final String fecha;
  final String hora;
  final Set<String> dnis;
  final Set<String> placas;
}
