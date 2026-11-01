import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../utils/dialog_utils.dart';
import '../utils/theme_colors.dart';

/// Selector granja + campaña (misma lógica que dashboard-evidencias-fotograficas.php).
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

  static String codigoCenco6(String granja, String campania) {
    return normGranja(granja) + padCampania(campania);
  }

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

  static bool codigoEquivalente(String a, String b) {
    return normalizarCodigoCenco(a) == normalizarCodigoCenco(b);
  }

  /// Últimos 3 dígitos del código CENCO (respaldo si no hay campaña en proyección).
  static String campaniaFromCodigo(String codigo) {
    final n = normalizarCodigoCenco(codigo);
    if (n.length >= 6) return n.substring(n.length - 3);
    final c = codigo.trim();
    if (c.length >= 3) return c.substring(c.length - 3);
    return padCampania(c);
  }

  /// Quita sufijos tipo `C=193` / `C=0193` del nombre de granja.
  static String cleanNombreGranja(String nombre) {
    var n = nombre.trim();
    if (n.isEmpty) return '';
    n = n.replaceAll(RegExp(r'\s*C\s*=\s*\d+\s*', caseSensitive: false), ' ');
    n = n.replaceAll(RegExp(r'\s*C\s*=\s*\d+\s*$', caseSensitive: false), '');
    n = n.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    return n;
  }

  /// Fecha local de hoy en formato YYYY-MM-DD.
  static String fechaHoyYmd() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  /// True si [fechaYmd] es hoy o una fecha futura.
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

  /// Estado offline de campaña (fechas ccos; edad solo vía API cargaproduccion00).
  static ({
    bool activa,
    int? edad,
    String? fechaInicio,
    String? fechaFin,
  }) edadCampaniaEnFecha({
    required Map<String, dynamic>? proyeccion,
    required String granja3,
    required String campania,
    required String fechaYmd,
  }) {
    final campPad = padCampania(campania);
    Map<String, String>? campMeta;
    for (final m in campaniasMetaDeGranja(proyeccion, granja3)) {
      if (padCampania(m['campania'] ?? '') == campPad) {
        campMeta = m;
        break;
      }
    }
    final fi = campMeta?['fecha_inicio']?.trim();
    final ff = campMeta?['fecha_fin']?.trim();
    final activa = campaniasActivasEnFecha(proyeccion, granja3, fechaYmd)
            .contains(campPad) ||
        campaniaActivaEnFecha(fi, ff, fechaYmd);
    return (
      activa: activa,
      edad: null,
      fechaInicio: fi,
      fechaFin: ff,
    );
  }

  static bool galponCodigoCoincide(String a, String b) {
    final ta = a.trim();
    final tb = b.trim();
    if (ta.isEmpty || tb.isEmpty) return false;
    if (ta == tb) return true;
    final ia = int.tryParse(ta);
    final ib = int.tryParse(tb);
    if (ia != null && ib != null) return ia == ib;
    return false;
  }

  /// Edad promedio offline solo desde `fec_ing_min` (entrada real de aves en maes_zonas).
  static int? edadPromedioGalponesEnFecha({
    required List<Map<String, dynamic>> galponesMeta,
    required List<String> galponesSel,
    required String fechaYmd,
  }) {
    if (galponesSel.isEmpty || galponesMeta.isEmpty) return null;
    final edades = <int>[];
    for (final cod in galponesSel) {
      final gal = cod.trim();
      if (gal.isEmpty) continue;
      int? edadGalpon;
      for (final g in galponesMeta) {
        final gc = (g['tcodint'] ?? g['galpon'] ?? '').toString().trim();
        if (!galponCodigoCoincide(gc, gal)) {
          continue;
        }
        final fi =
            (g['fec_ing_min'] ?? g['fecIngMin'] ?? '').toString().trim();
        final edad = calcularEdadEnFecha(fechaYmd, fi);
        if (edad != null) {
          edadGalpon = edad;
          break;
        }
      }
      if (edadGalpon != null) edades.add(edadGalpon);
    }
    if (edades.isEmpty) return null;
    return (edades.reduce((a, b) => a + b) / edades.length).round();
  }

  /// Día de pollo: días(fecha − fec_ing) + 1; null si aún no hay ingreso de aves.
  static int? calcularEdadEnFecha(String fechaYmd, String fechaInicioYmd) {
    final a = DateTime.tryParse(fechaYmd);
    final b = DateTime.tryParse(fechaInicioYmd);
    if (a == null || b == null) return null;
    final edad = DateTime(a.year, a.month, a.day)
            .difference(DateTime(b.year, b.month, b.day))
            .inDays +
        1;
    if (edad <= 0 || edad > 2000) return null;
    return edad;
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

  /// Campañas para registro en [fechaYmd]: activas ese día (1 o varias si paralelas).
  static List<String> campaniasPoolParaFecha({
    required Map<String, dynamic>? proyeccion,
    required String granja3,
    required String fechaYmd,
    List<String>? campaniasDisponibles,
  }) {
    final pool = campaniasDisponibles ??
        campaniasDisponiblesGranja(proyeccion, granja3);
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

  /// Campaña sugerida por el backend para [granja3] en [fechaYmd], si existe.
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

  /// Campañas elegibles en [fechaYmd]: activas en la fecha; si no hay, las ya
  /// iniciadas (fecha_inicio ≤ fecha), excluyendo campañas futuras.
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
      final hoy = pool
          .where((c) => activasCat.contains(padCampania(c)))
          .toList();
      if (hoy.isNotEmpty) return _sortCampaniasAsc(hoy);
    }
    return pool.length == 1 ? _sortCampaniasAsc(pool) : [];
  }

  /// Campaña vigente en [fechaYmd]: la primera activa (menor `fecha_inicio`;
  /// desempate por número de campaña más bajo).
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
      final elige = best == null ||
          fi.compareTo(bestFi) < 0 ||
          (fi == bestFi && n < bestN);
      if (elige) {
        bestFi = fi;
        bestN = n;
        best = campPad;
      }
    }
    return best;
  }

  /// Campaña activa en catálogo ccos (proyección/cencos) para [granja3].
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

  /// Imprime en consola las campañas de una granja (diagnóstico).
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

  /// Campaña por defecto para [fechaYmd]: vigente según ccos (`fecha_inicio` / `fecha_fin`).
  static String? resolveCampaniaDefaultForFecha({
    required Map<String, dynamic>? proyeccion,
    required String granja3,
    required String fechaYmd,
    List<String>? campaniasDisponibles,
    Map<String, dynamic>? cencosGalpones,
  }) {
    final meta = campaniasMetaDeGranja(proyeccion, granja3);
    final pool = campaniasDisponibles ??
        campaniasDisponiblesGranja(proyeccion, granja3);
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
        final porInicio =
            _campaniaConInicioMasAntigua(meta, elegibles, fechaYmd);
        if (porInicio != null) {
          return pick('ccos activa', porInicio);
        }
      }
    }

    if (elegibles.isNotEmpty) {
      return pick('primera campaña', _campaniaPrimera(elegibles));
    }

    final activas = campaniasActivasEnFecha(proyeccion, granja3, fechaYmd);
    if (activas.isNotEmpty) {
      return pick('ccos activa', activas.first);
    }

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

  /// Entre campañas elegibles, la de menor fecha_inicio ≤ [fechaYmd].
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

  /// Campaña numéricamente más baja (p. ej. 025 < 026).
  static String? _campaniaPrimera(List<String> camps) {
    final sorted = _sortCampaniasAsc(camps);
    return sorted.isEmpty ? null : sorted.first;
  }

  /// Etiqueta visible: `621 GJA. SANTA TERESA` (sin correlativo ni C=).
  static String formatGranjaLabel(String granjaCodigo, String nombre) {
    final g3 = normGranja(granjaCodigo);
    var nom = cleanNombreGranja(nombre);
    if (g3.isNotEmpty && nom.startsWith(g3)) {
      nom = nom.substring(g3.length).replaceFirst(RegExp(r'^[\s\-–—]+'), '').trim();
    }
    if (g3.isEmpty) return nom;
    if (nom.isEmpty) return g3;
    return '$g3 $nom';
  }

  /// Lista: granja limpia + campaña al final solo para distinguir filas iguales.
  static String formatListaOpcion(Map<String, String> it) {
    final base = formatGranjaLabel(
      it['granja3'] ?? it['granja'] ?? '',
      it['granjaNombre'] ?? '',
    );
    final camp = padCampania(it['campania'] ?? '');
    if (camp.isEmpty) return base;
    return '$base  ·  $camp';
  }

  /// @deprecated Prefer [formatGranjaLabel]; se mantiene por compatibilidad.
  static String formatEtiqueta({
    required String codigo6,
    required String nombre,
    required String campania,
  }) {
    final g3 = normGranja(
      normalizarCodigoCenco(codigo6).length >= 3
          ? normalizarCodigoCenco(codigo6).substring(0, 3)
          : codigo6,
    );
    return formatGranjaLabel(g3, nombre);
  }

  static String formatEtiquetaFromSeleccion(Map<String, String> sel) {
    return formatGranjaLabel(
      sel['granja3'] ?? sel['granja'] ?? '',
      sel['granjaNombre'] ?? '',
    );
  }

  static String _readFechaCampo(Map item, String tipo) {
    final keys = tipo == 'inicio'
        ? [
            'fecha_inicio',
            'fec_inicio',
            'fecini',
            'fechaInicio',
            'inicio',
            'fi',
          ]
        : [
            'fecha_fin',
            'fec_fin',
            'fecfin',
            'fechaFin',
            'fin',
            'ff',
          ];
    for (final k in keys) {
      final v = item[k]?.toString().trim() ?? '';
      if (v.isNotEmpty && v != '0000-00-00') return v;
    }
    return '';
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

  /// Opciones combinadas granja+campaña desde proyección (granjas + campanias_por_granja).
  /// Si la proyección viene vacía o nula, usa [cencosGalpones] como respaldo (catálogo descargado).
  static List<Map<String, String>> buildOpciones(
    Map<String, dynamic>? proyeccion, {
    Map<String, dynamic>? cencosGalpones,
    String? fechaYmd,
  }) {
    final granjas = (proyeccion?['granjas'] as List?) ?? [];
    final campMap = Map<String, dynamic>.from(
      (proyeccion?['campanias_por_granja'] as Map?) ?? {},
    );
    final cencos = (proyeccion?['cencos'] as List?) ?? [];

    final nombres = <String, String>{};
    for (final g in granjas) {
      if (g is! Map) continue;
      final g3 = normGranja((g['granja'] ?? '').toString());
      if (g3.isEmpty || _excluirGranjas.contains(g3)) continue;
      final nom = cleanNombreGranja(
        (g['nombre'] ?? g['nombre_granja'] ?? '').toString(),
      );
      if (nom.isNotEmpty) nombres[g3] = nom;
    }

    for (final c in cencos) {
      if (c is! Map) continue;
      final cod = (c['codigo'] ?? '').toString().trim();
      if (cod.length < 3) continue;
      final g3 = normGranja(cod);
      if (_excluirGranjas.contains(g3)) continue;
      final nom = cleanNombreGranja(
        (c['nombre'] ?? c['nombre_granja'] ?? '').toString(),
      );
      if (nom.isNotEmpty && !nombres.containsKey(g3)) {
        nombres[g3] = nom;
      }
    }

    final opciones = <Map<String, String>>[];
    final seen = <String>{};

    void addOpcion(String g3, Map<String, String> row) {
      final campP = padCampania(row['campania'] ?? '');
      if (g3.isEmpty || campP.isEmpty) return;
      var codCorrel = (row['codigo'] ?? '').trim();
      if (normalizarCodigoCenco(codCorrel).length < 6) {
        codCorrel = formatCodigoCorrelativo(g3, campP);
      }
      if (!seen.add(normalizarCodigoCenco(codCorrel))) return;
      final opt = <String, String>{
        'codigo': codCorrel,
        'granja': codCorrel,
        'granja3': g3,
        'campania': campP,
        'granjaNombre': nombres[g3] ?? '',
      };
      final fi = (row['fecha_inicio'] ?? '').trim();
      final ff = (row['fecha_fin'] ?? '').trim();
      if (fi.isNotEmpty) opt['fecha_inicio'] = fi;
      if (ff.isNotEmpty && ff != '0000-00-00') opt['fecha_fin'] = ff;
      opciones.add(opt);
    }

    campMap.forEach((gk, raw) {
      final g3 = normGranja(gk.toString());
      if (_excluirGranjas.contains(g3)) return;
      for (final row in _parseCampanias(raw)) {
        addOpcion(g3, row);
      }
    });

    if (opciones.isEmpty) {
      for (final g in granjas) {
        if (g is! Map) continue;
        final g3 = normGranja((g['granja'] ?? '').toString());
        if (g3.isEmpty || _excluirGranjas.contains(g3)) continue;
        final camps = _parseCampanias(
          campMap[g3] ?? campMap[g['granja']] ?? campMap[g3.padLeft(3, '0')],
        );
        if (camps.isEmpty) continue;
        for (final row in camps) {
          addOpcion(g3, row);
        }
      }
    }

    if (opciones.isEmpty) {
      for (final c in cencos) {
        if (c is! Map) continue;
        final cod6 = (c['codigo'] ?? '').toString().trim();
        if (cod6.length < 6) continue;
        final g3 = normGranja(cod6);
        if (_excluirGranjas.contains(g3)) continue;
        final camp = padCampania(cod6.substring(cod6.length - 3));
        addOpcion(g3, {'campania': camp, 'codigo': cod6});
      }
    }

    if (cencosGalpones != null) {
      final cg = (cencosGalpones['cencos'] as List?) ?? [];
      for (final c in cg) {
        if (c is! Map) continue;
        final cod6 = (c['codigo'] ?? '').toString().trim();
        if (cod6.length < 6) continue;
        final g3 = normGranja(cod6);
        if (_excluirGranjas.contains(g3)) continue;
        final nom = cleanNombreGranja(
          (c['nombre'] ?? c['nombre_granja'] ?? '').toString(),
        );
        if (nom.isNotEmpty && !nombres.containsKey(g3)) {
          nombres[g3] = nom;
        }
        final camp = padCampania(cod6.substring(cod6.length - 3));
        addOpcion(g3, {'campania': camp, 'codigo': cod6});
      }
    }

    final out = opciones;
    out.sort((a, b) {
      final la = formatListaOpcion(a);
      final lb = formatListaOpcion(b);
      return la.compareTo(lb);
    });

    return out;
  }

  /// Lista de granjas para el modal (rápido, sin reconstruir opciones planas).
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

    out.sort((a, b) {
      final la = formatGranjaConCampanias(a);
      final lb = formatGranjaConCampanias(b);
      return la.compareTo(lb);
    });
    return out;
  }

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required Map<String, dynamic>? proyeccion,
    Map<String, dynamic>? cencosGalpones,
    String? fechaYmd,
  }) async {
    var granjas = buildGranjasDesdeProyeccion(
      proyeccion,
      cencosGalpones: cencosGalpones,
      fechaYmd: fechaYmd,
    );
    if (granjas.isEmpty) {
      final opciones = buildOpciones(
        proyeccion,
        cencosGalpones: cencosGalpones,
        fechaYmd: fechaYmd,
      );
      granjas = agruparGranjas(opciones);
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

    final sel = await _showSearchList<Map<String, dynamic>>(
      context,
      title: 'Seleccionar Granja',
      hint: 'Buscar por código o nombre',
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

    return sel;
  }

  /// Agrupa las opciones planas (granja+campaña) por granja (3 dígitos),
  /// conservando la lista de campañas ordenadas.
  static List<Map<String, dynamic>> agruparGranjas(
    List<Map<String, String>> opciones,
  ) {
    final map = <String, Map<String, dynamic>>{};
    for (final o in opciones) {
      final g3 = o['granja3'] ?? '';
      if (g3.isEmpty) continue;
      if (!map.containsKey(g3)) {
        map[g3] = {
          'granja3': g3,
          'granjaNombre': o['granjaNombre'] ?? '',
          'campanias': <String>[],
          'campaniasMeta': <Map<String, String>>[],
        };
      }
      final camp = padCampania(o['campania'] ?? '');
      if (camp.isNotEmpty) {
        final list = map[g3]!['campanias'] as List<String>;
        if (!list.contains(camp)) list.add(camp);
        final metaList = map[g3]!['campaniasMeta'] as List<Map<String, String>>;
        if (!metaList.any((m) => padCampania(m['campania'] ?? '') == camp)) {
          final meta = <String, String>{'campania': camp};
          final fi = (o['fecha_inicio'] ?? '').trim();
          final ff = (o['fecha_fin'] ?? '').trim();
          if (fi.isNotEmpty) meta['fecha_inicio'] = fi;
          if (ff.isNotEmpty && ff != '0000-00-00') meta['fecha_fin'] = ff;
          metaList.add(meta);
        }
      }
      final nombreActual = map[g3]!['granjaNombre'] as String;
      if (nombreActual.isEmpty) {
        map[g3]!['granjaNombre'] = o['granjaNombre'] ?? '';
      }
    }

    final out = map.values.map((m) {
      final camps = List<String>.from(m['campanias'] as List);
      camps.sort((a, b) {
        final na = int.tryParse(a);
        final nb = int.tryParse(b);
        if (na != null && nb != null) return na.compareTo(nb);
        return a.compareTo(b);
      });
      return {
        'granja3': m['granja3'],
        'granjaNombre': m['granjaNombre'],
        'campanias': camps,
      };
    }).toList();

    out.sort((a, b) {
      final la = formatGranjaConCampanias(a);
      final lb = formatGranjaConCampanias(b);
      return la.compareTo(lb);
    });
    return out;
  }

  /// Etiqueta de granja: `621 NOMBRE` (sin conteo de campañas).
  static String formatGranjaConCampanias(Map<String, dynamic> g) {
    return formatGranjaLabel(
      (g['granja3'] ?? '').toString(),
      (g['granjaNombre'] ?? '').toString(),
    );
  }

  /// Texto legible de galpones para resumen/reportes.
  static String formatGalpones(Map<String, dynamic> r) {
    if (r['galpones_todos'] == true) return 'Todos';
    final list = (r['galpones'] as List?) ?? [];
    final parts =
        list.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    if (parts.isNotEmpty) return parts.join(', ');
    final g = (r['galpon'] ?? '').toString();
    return g.isEmpty ? '—' : g;
  }

  /// Diálogo para elegir una campaña (selección única) cuando una granja tiene varias.
  static Future<String?> showCampania(
    BuildContext context, {
    required List<String> campanias,
    String? selected,
  }) async {
    final items = campanias.map((c) => padCampania(c)).toList();
    items.sort((a, b) {
      final na = int.tryParse(a);
      final nb = int.tryParse(b);
      if (na != null && nb != null) return na.compareTo(nb);
      return a.compareTo(b);
    });

    var current = selected ?? '';
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
    required String hint,
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
          final filtered = items
              .where((it) => filter.isEmpty || filterOf(it, q))
              .toList();

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
                        hintText: 'Buscar...',
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
