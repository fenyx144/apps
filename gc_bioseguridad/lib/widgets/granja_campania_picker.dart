import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../utils/dialog_utils.dart';
import '../utils/theme_colors.dart';

/// Selector granja + campaña para bioseguridad.
/// Reutiliza la lógica de resolución de campañas de la app de crianza
/// (intervalo `fecha_inicio`/`fecha_fin` del catálogo ccos) pero sin galpones
/// ni edad, que no aplican a los reportes de bioseguridad.
class GranjaCampaniaPicker {
  static const _excluirGranjas = {'619', '624', '650'};

  static String normGranja(String cod) {
    var s = cod.trim();
    if (s.isEmpty) return '';
    while (s.length < 3) {
      s = '0$s';
    }
    return s.length > 3 ? s.substring(0, 3) : s;
  }

  static String padCampania(String camp) {
    var d = camp.replaceAll(RegExp(r'\D'), '');
    if (d.length >= 3) return d.substring(d.length - 3);
    while (d.length < 3) {
      d = '0$d';
    }
    return d.substring(d.length - 3);
  }

  static String codigoCenco6(String granja, String campania) =>
      normGranja(granja) + padCampania(campania);

  static String padCorrelativo(String camp) {
    var d = padCampania(camp);
    while (d.length < 4) {
      d = '0$d';
    }
    return d.substring(d.length - 4);
  }

  /// Formato correlativo: 621-0001
  static String formatCodigoCorrelativo(String granja, String campania) {
    final g = normGranja(granja);
    if (g.isEmpty) return '';
    return '$g-${padCorrelativo(campania)}';
  }

  /// Normaliza 621-0001 o 621001 a 621001.
  static String normalizarCodigoCenco(String codigo) {
    final c = codigo.trim();
    if (c.isEmpty) return '';
    final m = RegExp(r'^(\d{3})-(\d{3,4})$').firstMatch(c);
    if (m != null) {
      final camp3 = m.group(2)!.padLeft(3, '0');
      return '${m.group(1)}${camp3.substring(camp3.length - 3)}';
    }
    final digits = c.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 6) {
      return digits.substring(0, 3) + digits.substring(digits.length - 3);
    }
    return c;
  }

  /// Quita sufijos tipo `C=193` del nombre de granja.
  static String cleanNombreGranja(String nombre) {
    var n = nombre.trim();
    if (n.isEmpty) return '';
    n = n.replaceAll(RegExp(r'\s*C\s*=\s*\d+\s*', caseSensitive: false), ' ');
    n = n.replaceAll(RegExp(r'\s*C\s*=\s*\d+\s*$', caseSensitive: false), '');
    n = n.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    return n;
  }

  static String fechaHoyYmd() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  static bool esHoyOFuturo(String fechaYmd) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(fechaYmd)) return false;
    return fechaYmd.compareTo(fechaHoyYmd()) >= 0;
  }

  /// Campaña activa en [refYmd] según intervalo ccos (fecini/fecfin).
  static bool campaniaActivaEnFecha(
    String? fechaInicio,
    String? fechaFin,
    String refYmd,
  ) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(refYmd)) return false;
    final fi = (fechaInicio ?? '').trim();
    if (fi.isEmpty || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(fi)) {
      return false;
    }
    if (fi.compareTo(refYmd) > 0) return false;
    final ff = (fechaFin ?? '').trim();
    if (ff.isEmpty || ff == '0000-00-00') return true;
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(ff)) return true;
    return ff.compareTo(refYmd) >= 0;
  }

  static List<Map<String, String>> _parseCampanias(dynamic raw) {
    if (raw is! List) return [];
    final out = <Map<String, String>>[];
    for (final item in raw) {
      if (item is Map) {
        final camp = padCampania((item['campania'] ?? '').toString());
        if (camp.isEmpty) continue;
        var codCorrel = (item['codigo'] ?? '').toString().trim();
        if (normalizarCodigoCenco(codCorrel).length < 6) {
          codCorrel = formatCodigoCorrelativo(
            normGranja((item['granja'] ?? codCorrel).toString()),
            camp,
          );
        }
        final row = {'campania': camp, 'codigo': codCorrel};
        final fi = _readFechaCampo(item, 'inicio');
        final ff = _readFechaCampo(item, 'fin');
        if (fi.isNotEmpty) row['fecha_inicio'] = fi;
        if (ff.isNotEmpty && ff != '0000-00-00') row['fecha_fin'] = ff;
        out.add(row);
      } else {
        final camp = padCampania(item.toString());
        if (camp.isNotEmpty) {
          out.add({'campania': camp, 'codigo': ''});
        }
      }
    }
    return out;
  }

  static String _readFechaCampo(Map item, String tipo) {
    final keys = tipo == 'inicio'
        ? ['fecha_inicio', 'fec_inicio', 'fecini', 'fechaInicio', 'inicio', 'fi']
        : ['fecha_fin', 'fec_fin', 'fecfin', 'fechaFin', 'fin', 'ff'];
    for (final k in keys) {
      final v = item[k]?.toString().trim() ?? '';
      if (v.isNotEmpty && v != '0000-00-00') return v;
    }
    return '';
  }

  /// Metadatos de campaña desde proyección (campanias_por_granja).
  static List<Map<String, String>> campaniasMetaDeGranja(
    Map<String, dynamic>? proyeccion,
    String granja3,
  ) {
    final g3 = normGranja(granja3);
    if (g3.isEmpty || proyeccion == null) return [];
    final campMap = Map<String, dynamic>.from(
      (proyeccion['campanias_por_granja'] as Map?) ?? {},
    );
    final raw = campMap[g3] ?? campMap[g3.padLeft(3, '0')];
    return _parseCampanias(raw);
  }

  static List<String> _sortCampaniasAsc(List<String> camps) {
    final sorted = camps.map(padCampania).where((c) => c.isNotEmpty).toList();
    sorted.sort((a, b) {
      final na = int.tryParse(a);
      final nb = int.tryParse(b);
      if (na != null && nb != null) return na.compareTo(nb);
      return a.compareTo(b);
    });
    return sorted;
  }

  static String? _campaniaPrimera(List<String> camps) {
    final sorted = _sortCampaniasAsc(camps);
    return sorted.isEmpty ? null : sorted.first;
  }

  static List<String> _activasDesdeMetaEnFecha(
    List<Map<String, String>> meta,
    String fechaYmd,
  ) {
    final conFechas = meta.where((m) {
      final fi = (m['fecha_inicio'] ?? '').trim();
      return fi.isNotEmpty;
    }).toList();
    if (conFechas.isEmpty) return [];

    return conFechas
        .where((m) => campaniaActivaEnFecha(
              m['fecha_inicio'],
              m['fecha_fin'],
              fechaYmd,
            ))
        .map((m) => padCampania(m['campania'] ?? ''))
        .where((c) => c.isNotEmpty)
        .toList();
  }

  static List<String> _activasDesdeBackend(
    Map<String, dynamic>? proyeccion,
    String granja3,
  ) {
    final activasMap = proyeccion?['activas_por_granja'];
    if (activasMap is! Map) return [];
    final g3 = normGranja(granja3);
    final raw = activasMap[g3] ?? activasMap[g3.padLeft(3, '0')];
    if (raw is! List || raw.isEmpty) return [];
    return raw
        .map((e) => padCampania(e.toString()))
        .where((c) => c.isNotEmpty)
        .toList();
  }

  /// Campañas activas en [fechaYmd] para una granja (intervalo ccos).
  static List<String> campaniasActivasEnFecha(
    Map<String, dynamic>? proyeccion,
    String granja3,
    String fechaYmd,
  ) {
    final meta = campaniasMetaDeGranja(proyeccion, granja3);
    final fromMeta = _activasDesdeMetaEnFecha(meta, fechaYmd);
    final proyFecha = (proyeccion?['fecha'] ?? '').toString().trim();
    final fromBackend = (proyFecha.isEmpty || proyFecha == fechaYmd)
        ? _activasDesdeBackend(proyeccion, granja3)
        : <String>[];

    if (fromBackend.isNotEmpty || fromMeta.isNotEmpty) {
      return _sortCampaniasAsc({
        ...fromBackend.map(padCampania),
        ...fromMeta.map(padCampania),
      }.where((c) => c.isNotEmpty).toList());
    }

    if (meta.isEmpty) return [];

    return _sortCampaniasAsc(
      meta
          .map((m) => padCampania(m['campania'] ?? ''))
          .where((c) => c.isNotEmpty)
          .toList(),
    );
  }

  /// Campañas para registrar en [fechaYmd]: activas ese día.
  static List<String> campaniasPoolParaFecha({
    required Map<String, dynamic>? proyeccion,
    required String granja3,
    required String fechaYmd,
    List<String>? campaniasDisponibles,
  }) {
    final pool =
        campaniasDisponibles ?? campaniasDisponiblesGranja(proyeccion, granja3);
    if (pool.isEmpty) return [];

    final poolSet = pool.map(padCampania).toSet();
    final activas = campaniasActivasEnFecha(proyeccion, granja3, fechaYmd);
    if (activas.isNotEmpty) {
      final filtradas =
          activas.where((c) => poolSet.contains(padCampania(c))).toList();
      return _sortCampaniasAsc(filtradas.isNotEmpty ? filtradas : activas);
    }

    final meta = campaniasMetaDeGranja(proyeccion, granja3);
    final tieneFechas = meta.any(
      (m) => (m['fecha_inicio'] ?? '').trim().isNotEmpty,
    );
    if (!tieneFechas) {
      if (esHoyOFuturo(fechaYmd) && pool.length == 1) {
        return _sortCampaniasAsc(pool);
      }
      return [];
    }

    final sug = campaniaSugeridaBackend(proyeccion, granja3);
    if (sug != null) {
      final camp = padCampania(sug);
      if (poolSet.contains(camp)) return [camp];
    }
    return [];
  }

  static String? campaniaSugeridaBackend(
    Map<String, dynamic>? proyeccion,
    String granja3,
  ) {
    final sugMap = proyeccion?['campania_sugerida_por_granja'];
    if (sugMap is! Map) return null;
    final g3 = normGranja(granja3);
    final raw = sugMap[g3] ?? sugMap[g3.padLeft(3, '0')];
    if (raw == null) return null;
    final camp = padCampania(raw.toString());
    return camp.isEmpty ? null : camp;
  }

  static List<String> _campaniasActivasCatalogo(
    String granja3,
    Map<String, dynamic>? cencosGalpones,
    Map<String, dynamic>? proyeccion,
  ) {
    final g3 = normGranja(granja3);
    final out = <String>{};
    final fuentes = <List<dynamic>>[
      (cencosGalpones?['cencos'] as List?) ?? [],
      (proyeccion?['cencos'] as List?) ?? [],
    ];
    for (final lista in fuentes) {
      for (final c in lista) {
        if (c is! Map) continue;
        final cod = normalizarCodigoCenco((c['codigo'] ?? '').toString());
        if (cod.length < 6 || normGranja(cod) != g3) continue;
        out.add(padCampania(cod.substring(cod.length - 3)));
      }
    }
    return out.toList();
  }

  static List<String> campaniasElegiblesEnFecha({
    required Map<String, dynamic>? proyeccion,
    required String granja3,
    required String fechaYmd,
    List<String>? campaniasDisponibles,
    Map<String, dynamic>? cencosGalpones,
  }) {
    final meta = campaniasMetaDeGranja(proyeccion, granja3);
    final pool = (campaniasDisponibles ??
            meta
                .map((m) => padCampania(m['campania'] ?? ''))
                .where((c) => c.isNotEmpty)
                .toList())
        .map(padCampania)
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();

    if (pool.isEmpty) return [];

    final tieneFechas = meta.any(
      (m) => (m['fecha_inicio'] ?? '').trim().isNotEmpty,
    );
    if (tieneFechas) {
      return campaniasPoolParaFecha(
        proyeccion: proyeccion,
        granja3: granja3,
        fechaYmd: fechaYmd,
        campaniasDisponibles: pool,
      );
    }

    if (esHoyOFuturo(fechaYmd)) {
      final activasCat = _campaniasActivasCatalogo(
        granja3,
        cencosGalpones,
        proyeccion,
      );
      final hoy =
          pool.where((c) => activasCat.contains(padCampania(c))).toList();
      if (hoy.isNotEmpty) return _sortCampaniasAsc(hoy);
    }
    return pool.length == 1 ? _sortCampaniasAsc(pool) : [];
  }

  static String? campaniaVigenteEnFecha({
    required List<Map<String, String>> meta,
    required List<String> pool,
    required String fechaYmd,
  }) {
    String? best;
    var bestFi = '';
    var bestN = 1 << 30;
    for (final camp in pool) {
      final campPad = padCampania(camp);
      Map<String, String>? campMeta;
      for (final m in meta) {
        if (padCampania(m['campania'] ?? '') == campPad) {
          campMeta = m;
          break;
        }
      }
      if (campMeta == null) continue;
      final fi = (campMeta['fecha_inicio'] ?? '').trim();
      if (fi.isEmpty) continue;
      if (!campaniaActivaEnFecha(fi, campMeta['fecha_fin'], fechaYmd)) {
        continue;
      }
      if (fi.compareTo(fechaYmd) > 0) continue;
      final n = int.tryParse(campPad) ?? bestN;
      final elige =
          best == null || fi.compareTo(bestFi) < 0 || (fi == bestFi && n < bestN);
      if (elige) {
        bestFi = fi;
        bestN = n;
        best = campPad;
      }
    }
    return best;
  }

  static String? campaniaDesdeCencosActivos({
    required String granja3,
    Map<String, dynamic>? cencosGalpones,
    Map<String, dynamic>? proyeccion,
    List<String>? limitarA,
  }) {
    final g3 = normGranja(granja3);
    final fuentes = <List<dynamic>>[
      (cencosGalpones?['cencos'] as List?) ?? [],
      (proyeccion?['cencos'] as List?) ?? [],
    ];
    String? best;
    var bestN = -1;
    for (final lista in fuentes) {
      for (final c in lista) {
        if (c is! Map) continue;
        final cod = normalizarCodigoCenco((c['codigo'] ?? '').toString());
        if (cod.length < 6 || normGranja(cod) != g3) continue;
        final camp = padCampania(cod.substring(cod.length - 3));
        if (limitarA != null && !limitarA.contains(camp)) continue;
        final n = int.tryParse(camp);
        if (n != null && n >= bestN) {
          bestN = n;
          best = camp;
        }
      }
      if (best != null) return best;
    }
    return best;
  }

  /// Todas las campañas conocidas de una granja (histórico en proyección local).
  static List<String> campaniasDisponiblesGranja(
    Map<String, dynamic>? proyeccion,
    String granja3,
  ) {
    final meta = campaniasMetaDeGranja(proyeccion, granja3);
    final camps = meta
        .map((m) => padCampania(m['campania'] ?? ''))
        .where((c) => c.isNotEmpty)
        .toList();
    return _sortCampaniasAsc(camps);
  }

  /// Campaña por defecto para [fechaYmd] según el catálogo ccos.
  static String? resolveCampaniaDefaultForFecha({
    required Map<String, dynamic>? proyeccion,
    required String granja3,
    required String fechaYmd,
    List<String>? campaniasDisponibles,
    Map<String, dynamic>? cencosGalpones,
  }) {
    final meta = campaniasMetaDeGranja(proyeccion, granja3);
    final pool =
        campaniasDisponibles ?? campaniasDisponiblesGranja(proyeccion, granja3);
    final elegibles = campaniasElegiblesEnFecha(
      proyeccion: proyeccion,
      granja3: granja3,
      fechaYmd: fechaYmd,
      campaniasDisponibles: pool,
      cencosGalpones: cencosGalpones,
    );

    String? pick(String origen, String? camp) {
      if (camp == null || camp.isEmpty) return null;
      debugLogCampaniasGranja(
        granja3: granja3,
        fechaYmd: fechaYmd,
        proyeccion: proyeccion,
        elegibles: pool,
        seleccionada: camp,
        origen: origen,
      );
      return camp;
    }

    final sugeridaBackend = campaniaSugeridaBackend(proyeccion, granja3);
    if (sugeridaBackend != null && elegibles.contains(sugeridaBackend)) {
      return pick('ccos sugerida', sugeridaBackend);
    }

    final tieneFechas = meta.any(
      (m) => (m['fecha_inicio'] ?? '').trim().isNotEmpty,
    );

    if (tieneFechas) {
      final vigente = campaniaVigenteEnFecha(
        meta: meta,
        pool: elegibles.isNotEmpty ? elegibles : pool,
        fechaYmd: fechaYmd,
      );
      if (vigente != null) return pick('ccos vigente', vigente);

      if (!esHoyOFuturo(fechaYmd)) {
        final porInicio = _campaniaConInicioMasAntigua(meta, elegibles, fechaYmd);
        if (porInicio != null) return pick('ccos activa', porInicio);
      }
    }

    if (elegibles.isNotEmpty) {
      return pick('primera campaña', _campaniaPrimera(elegibles));
    }

    final activas = campaniasActivasEnFecha(proyeccion, granja3, fechaYmd);
    if (activas.isNotEmpty) return pick('ccos activa', activas.first);

    if (!tieneFechas) {
      final activa = campaniaDesdeCencosActivos(
        granja3: granja3,
        cencosGalpones: cencosGalpones,
        proyeccion: proyeccion,
      );
      return pick('ccos catálogo', activa);
    }

    return null;
  }

  static String? _campaniaConInicioMasAntigua(
    List<Map<String, String>> meta,
    List<String> camps,
    String fechaYmd,
  ) {
    String? best;
    var bestFi = '';
    var bestN = 1 << 30;
    for (final camp in camps) {
      final campPad = padCampania(camp);
      for (final m in meta) {
        if (padCampania(m['campania'] ?? '') != campPad) continue;
        final fi = (m['fecha_inicio'] ?? '').trim();
        if (fi.isEmpty) continue;
        if (fi.compareTo(fechaYmd) > 0) continue;
        final n = int.tryParse(campPad) ?? bestN;
        final elige = best == null ||
            fi.compareTo(bestFi) < 0 ||
            (fi == bestFi && n < bestN);
        if (elige) {
          bestFi = fi;
          bestN = n;
          best = campPad;
        }
      }
    }
    return best ?? _campaniaPrimera(camps);
  }

  /// Etiqueta visible: `621 GJA. SANTA TERESA`.
  static String formatGranjaLabel(String granjaCodigo, String nombre) {
    final g3 = normGranja(granjaCodigo);
    var nom = cleanNombreGranja(nombre);
    if (g3.isNotEmpty && nom.startsWith(g3)) {
      nom = nom
          .substring(g3.length)
          .replaceFirst(RegExp(r'^[\s\-–—]+'), '')
          .trim();
    }
    if (g3.isEmpty) return nom;
    if (nom.isEmpty) return g3;
    return '$g3 $nom';
  }

  /// Etiqueta de granja: `621 NOMBRE`.
  static String formatGranjaConCampanias(Map<String, dynamic> g) {
    return formatGranjaLabel(
      (g['granja3'] ?? '').toString(),
      (g['granjaNombre'] ?? '').toString(),
    );
  }

  static void debugLogCampaniasGranja({
    required String granja3,
    required String fechaYmd,
    Map<String, dynamic>? proyeccion,
    List<String>? elegibles,
    String? seleccionada,
    String? origen,
  }) {
    if (!kDebugMode) return;
    final meta = campaniasMetaDeGranja(proyeccion, granja3);
    debugPrint(
      '[Campanias] granja=$granja3 fecha=$fechaYmd '
      '→ seleccion=${seleccionada ?? "—"} (${origen ?? "?"})',
    );
    if (meta.isEmpty) {
      debugPrint('[Campanias]   (sin metadatos en proyección)');
    } else {
      for (final m in meta) {
        final fi = (m['fecha_inicio'] ?? '').trim();
        final ff = (m['fecha_fin'] ?? '').trim();
        debugPrint(
          '[Campanias]   camp=${m['campania']} '
          'inicio=${fi.isEmpty ? "—" : fi} fin=${ff.isEmpty ? "—" : ff}',
        );
      }
    }
    if (elegibles != null && elegibles.isNotEmpty) {
      debugPrint('[Campanias]   elegibles: ${elegibles.join(", ")}');
    }
  }

  /// Granjas con sus campañas elegibles para [fechaYmd].
  static List<Map<String, dynamic>> buildGranjasDesdeProyeccion(
    Map<String, dynamic>? proyeccion, {
    Map<String, dynamic>? cencosGalpones,
    String? fechaYmd,
  }) {
    final campMap = Map<String, dynamic>.from(
      (proyeccion?['campanias_por_granja'] as Map?) ?? {},
    );
    final nombres = <String, String>{};

    for (final g in (proyeccion?['granjas'] as List?) ?? []) {
      if (g is! Map) continue;
      final g3 = normGranja((g['granja'] ?? '').toString());
      if (g3.isEmpty || _excluirGranjas.contains(g3)) continue;
      final nom = cleanNombreGranja(
        (g['nombre'] ?? g['nombre_granja'] ?? '').toString(),
      );
      if (nom.isNotEmpty) nombres[g3] = nom;
    }

    for (final c in (cencosGalpones?['cencos'] as List?) ?? []) {
      if (c is! Map) continue;
      final cod = (c['codigo'] ?? '').toString().trim();
      if (cod.length < 3) continue;
      final g3 = normGranja(cod);
      if (_excluirGranjas.contains(g3)) continue;
      final nom = cleanNombreGranja(
        (c['nombre'] ?? c['nombre_granja'] ?? '').toString(),
      );
      if (nom.isNotEmpty && !nombres.containsKey(g3)) nombres[g3] = nom;
    }

    final out = <Map<String, dynamic>>[];
    campMap.forEach((gk, raw) {
      final g3 = normGranja(gk.toString());
      if (g3.isEmpty || _excluirGranjas.contains(g3)) return;
      final meta = _parseCampanias(raw);
      if (meta.isEmpty) return;
      final pool = meta
          .map((m) => padCampania(m['campania'] ?? ''))
          .where((c) => c.isNotEmpty)
          .toList();
      final camps = (fechaYmd != null && fechaYmd.isNotEmpty)
          ? campaniasPoolParaFecha(
              proyeccion: proyeccion,
              granja3: g3,
              fechaYmd: fechaYmd,
              campaniasDisponibles: pool,
            )
          : pool;
      if (camps.isEmpty) return;
      final metaFiltrada = meta
          .where((m) => camps.contains(padCampania(m['campania'] ?? '')))
          .toList();
      out.add({
        'granja3': g3,
        'granjaNombre': nombres[g3] ?? '',
        'campanias': _sortCampaniasAsc(camps),
        'campaniasMeta': metaFiltrada,
      });
    });

    out.sort((a, b) =>
        formatGranjaConCampanias(a).compareTo(formatGranjaConCampanias(b)));
    return out;
  }

  /// Selección que corresponde a [granja3] para [fechaYmd], tal como la
  /// devolvería [show] con la campaña sugerida ya resuelta.
  /// Devuelve `{granja3, granjaNombre, campanias, campania}`, o `null` si la
  /// granja no tiene campañas elegibles esa fecha (así los formularios arrancan
  /// vacíos en vez de quedar con una campaña que no se puede registrar).
  static Map<String, dynamic>? seleccionDeGranja({
    required Map<String, dynamic>? proyeccion,
    required String granja3,
    required String fechaYmd,
    Map<String, dynamic>? cencosGalpones,
  }) {
    final g3 = normGranja(granja3);
    if (g3.isEmpty) return null;

    for (final g in buildGranjasDesdeProyeccion(
      proyeccion,
      cencosGalpones: cencosGalpones,
      fechaYmd: fechaYmd,
    )) {
      if (normGranja((g['granja3'] ?? '').toString()) != g3) continue;
      final lista = ((g['campanias'] as List?) ?? [])
          .map((e) => padCampania(e.toString()))
          .where((c) => c.isNotEmpty)
          .toList();
      var camp = lista.length == 1 ? lista.first : '';
      if (camp.isEmpty) {
        camp = resolveCampaniaDefaultForFecha(
              proyeccion: proyeccion,
              granja3: g3,
              fechaYmd: fechaYmd,
              campaniasDisponibles: lista,
              cencosGalpones: cencosGalpones,
            ) ??
            (lista.isNotEmpty ? lista.first : '');
      }
      if (camp.isEmpty) return null;
      return {
        'granja3': g3,
        'granjaNombre': (g['granjaNombre'] ?? '').toString(),
        'campanias': lista,
        'campania': camp,
      };
    }
    return null;
  }

  /// Nombre de una granja del catálogo local, o '' si no se conoce.
  static String nombreDeGranja(
    Map<String, dynamic>? proyeccion,
    String granja3,
  ) {
    final g3 = normGranja(granja3);
    if (g3.isEmpty) return '';
    for (final g in buildGranjasDesdeProyeccion(proyeccion)) {
      if (normGranja((g['granja3'] ?? '').toString()) == g3) {
        return (g['granjaNombre'] ?? '').toString();
      }
    }
    for (final g in (proyeccion?['granjas'] as List?) ?? []) {
      if (g is! Map) continue;
      if (normGranja((g['granja'] ?? '').toString()) != g3) continue;
      final nom = cleanNombreGranja(
        (g['nombre'] ?? g['nombre_granja'] ?? '').toString(),
      );
      if (nom.isNotEmpty) return nom;
    }
    return '';
  }

  /// Abre el selector de granja. Devuelve `{granja3, granjaNombre, campanias}`.
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required Map<String, dynamic>? proyeccion,
    Map<String, dynamic>? cencosGalpones,
    String? fechaYmd,
    List<String>? granjasPermitidas,
  }) async {
    var granjas = buildGranjasDesdeProyeccion(
      proyeccion,
      cencosGalpones: cencosGalpones,
      fechaYmd: fechaYmd,
    );
    if (granjasPermitidas != null && granjasPermitidas.isNotEmpty) {
      final permitidas = granjasPermitidas
          .map(normGranja)
          .where((g) => g.isNotEmpty)
          .toSet();
      granjas = granjas
          .where(
            (it) => permitidas.contains(
              normGranja((it['granja3'] ?? '').toString()),
            ),
          )
          .toList();
    }
    if (granjas.isEmpty) {
      await showAppDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sin granjas'),
          content: const Text(
            'No hay granjas/campañas disponibles. '
            'Descargue datos desde el menú.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );
      return null;
    }

    return _showSearchList<Map<String, dynamic>>(
      context,
      title: 'Seleccionar Granja',
      items: granjas,
      labelOf: formatGranjaConCampanias,
      filterOf: (it, q) {
        final label = formatGranjaConCampanias(it).toLowerCase();
        if (label.contains(q)) return true;
        if ((it['granja3'] ?? '').toString().contains(q)) return true;
        final camps = (it['campanias'] as List?) ?? [];
        return camps.any((c) => c.toString().contains(q));
      },
    );
  }

  /// Diálogo para elegir una campaña (selección única).
  static Future<String?> showCampania(
    BuildContext context, {
    required List<String> campanias,
    String? selected,
  }) async {
    final items = _sortCampaniasAsc(campanias);

    String current = selected ?? '';
    var filter = '';
    final sel = await showAppDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          final q = filter.toLowerCase();
          final filtered =
              items.where((c) => filter.isEmpty || c.contains(q)).toList();

          return Dialog(
            backgroundColor: context.dialogSurface,
            insetPadding: context.dialogInsetPadding,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: SizedBox(
              width: MediaQuery.of(context).size.width - 24,
              height: MediaQuery.of(context).size.height * 0.58,
              child: Column(
                children: [
                  appDialogHeader(context, title: 'Seleccionar campaña'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      style: TextStyle(color: context.textThemePrimary),
                      decoration: InputDecoration(
                        hintText: 'Buscar campaña...',
                        hintStyle: TextStyle(color: context.textThemeMuted),
                        prefixIcon: Icon(
                          Icons.search,
                          color: context.textThemeMuted,
                        ),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => filter = v),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              'Sin resultados',
                              style: TextStyle(color: context.textThemeMuted),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final code = filtered[i];
                              return RadioListTile<String>(
                                dense: true,
                                value: code,
                                groupValue: current,
                                title: Text(
                                  'Campaña $code',
                                  style: TextStyle(
                                    color: context.textThemePrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() => current = v);
                                  Navigator.pop(context, v);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    return sel;
  }

  static Future<T?> _showSearchList<T>(
    BuildContext context, {
    required String title,
    required List<T> items,
    required String Function(T) labelOf,
    required bool Function(T, String) filterOf,
  }) {
    String filter = '';
    return showAppDialog<T>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          final q = filter.toLowerCase();
          final filtered =
              items.where((it) => filter.isEmpty || filterOf(it, q)).toList();

          return Dialog(
            backgroundColor: context.dialogSurface,
            insetPadding: context.dialogInsetPadding,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: SizedBox(
              width: MediaQuery.of(context).size.width - 24,
              height: MediaQuery.of(context).size.height * 0.58,
              child: Column(
                children: [
                  appDialogHeader(context, title: title),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      style: TextStyle(color: context.textThemePrimary),
                      decoration: InputDecoration(
                        hintText: 'Buscar por código o nombre',
                        hintStyle: TextStyle(color: context.textThemeMuted),
                        prefixIcon: Icon(
                          Icons.search,
                          color: context.textThemeMuted,
                        ),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => filter = v),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              'Sin resultados',
                              style: TextStyle(color: context.textThemeMuted),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final it = filtered[i];
                              return ListTile(
                                title: Text(
                                  labelOf(it),
                                  style: TextStyle(
                                    color: context.textThemePrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                onTap: () => Navigator.pop(context, it),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
