/// Resolución offline de galpones (patrón necropsias + fallback por granja 3 dígitos).
class GalponesCatalogIndices {
  const GalponesCatalogIndices({
    required this.cencos,
    required this.galponesPorCenco,
    required this.galponesPorGranja,
    required this.totalGalpones,
  });

  final List<Map<String, dynamic>> cencos;
  final Map<String, List<Map<String, dynamic>>> galponesPorCenco;
  final Map<String, List<Map<String, dynamic>>> galponesPorGranja;
  final int totalGalpones;
}

class GalponesResolver {
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

  static bool tieneGalponesUtiles(Map<String, dynamic>? cenco) {
    if (cenco == null) return false;
    final gps = cenco['galpones'];
    if (gps is! List || gps.isEmpty) return false;
    for (final g in gps) {
      if (g is Map) {
        final tc = (g['tcodint'] ?? g['galpon'] ?? '').toString().trim();
        if (tc.isNotEmpty) return true;
      } else {
        final tc = g.toString().trim();
        if (tc.isNotEmpty) return true;
      }
    }
    return false;
  }

  static List<Map<String, dynamic>> dedupeGalpones(List<Map<String, dynamic>> raw) {
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final g in raw) {
      final tc = (g['tcodint'] ?? g['galpon'] ?? '').toString().trim();
      if (tc.isEmpty || !seen.add(tc)) continue;
      out.add(Map<String, dynamic>.from(g));
    }
    out.sort((a, b) {
      final aa = (a['tcodint'] ?? '').toString();
      final bb = (b['tcodint'] ?? '').toString();
      return aa.compareTo(bb);
    });
    return out;
  }

  static int _cencoRank(String? tcencos) {
    final n = normalizarCodigoCenco((tcencos ?? '').toString());
    if (n.length < 6) return 0;
    return int.tryParse(n) ?? 0;
  }

  /// Por granja: mismo tcodint conservar CENCO más reciente (mayor código).
  static List<Map<String, dynamic>> dedupeGalponesPreferHigherCenco(
    List<Map<String, dynamic>> raw,
  ) {
    final best = <String, Map<String, dynamic>>{};
    for (final g in raw) {
      final tc = (g['tcodint'] ?? g['galpon'] ?? '').toString().trim();
      if (tc.isEmpty) continue;
      final prev = best[tc];
      if (prev == null) {
        best[tc] = Map<String, dynamic>.from(g);
        continue;
      }
      final rNew = _cencoRank(g['tcencos']?.toString());
      final rOld = _cencoRank(prev['tcencos']?.toString());
      if (rNew > rOld) {
        best[tc] = Map<String, dynamic>.from(g);
        continue;
      }
      if (rNew == rOld) {
        final fiNew = (g['fec_ing_min'] ?? '').toString().trim();
        final fiOld = (prev['fec_ing_min'] ?? '').toString().trim();
        if (fiNew.isNotEmpty && fiOld.isEmpty) {
          best[tc] = Map<String, dynamic>.from(g);
        }
      }
    }
    final out = best.values.toList();
    out.sort((a, b) {
      final aa = (a['tcodint'] ?? '').toString();
      final bb = (b['tcodint'] ?? '').toString();
      return aa.compareTo(bb);
    });
    return out;
  }

  static List<Map<String, dynamic>> filterGalponesPorCenco(
    List<Map<String, dynamic>> galpones,
    String norm6,
  ) {
    if (norm6.length < 6 || galpones.isEmpty) {
      return galpones;
    }
    final exact = galpones.where((g) {
      final tc = normalizarCodigoCenco((g['tcencos'] ?? '').toString());
      return tc == norm6;
    }).toList();
    return exact.isNotEmpty ? exact : galpones;
  }

  static List<Map<String, dynamic>> parseGalponesList(dynamic raw, {String? codigoCenco}) {
    if (raw is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final g in raw) {
      if (g is Map) {
        final m = Map<String, dynamic>.from(g);
        if (codigoCenco != null && m['tcencos'] == null) {
          m['tcencos'] = codigoCenco;
        }
        out.add(m);
      }
    }
    return dedupeGalpones(out);
  }

  /// Construye índices offline desde la respuesta de get_cencos_galpones.
  static GalponesCatalogIndices buildIndicesFromApiData(Map<String, dynamic> data) {
    final cencosRaw = (data['cencos'] as List?) ?? [];
    final cencos = <Map<String, dynamic>>[];
    final galponesPorCenco = <String, List<Map<String, dynamic>>>{};
    final galponesPorGranja = <String, List<Map<String, dynamic>>>{};

    for (final item in cencosRaw) {
      if (item is! Map) continue;
      final cenco = Map<String, dynamic>.from(item);
      final cod6 = normalizarCodigoCenco((cenco['codigo'] ?? '').toString());
      if (cod6.length < 6) continue;

      final gps = parseGalponesList(cenco['galpones'], codigoCenco: cod6);
      cenco['galpones'] = gps;
      cencos.add(cenco);
      galponesPorCenco[cod6] = gps;

      final g3 = normGranja(cod6);
      final prev = galponesPorGranja[g3] ?? [];
      galponesPorGranja[g3] =
          dedupeGalponesPreferHigherCenco([...prev, ...gps]);
    }

    var totalGalpones = 0;
    galponesPorGranja.forEach((_, list) => totalGalpones += list.length);

    return GalponesCatalogIndices(
      cencos: cencos,
      galponesPorCenco: galponesPorCenco,
      galponesPorGranja: galponesPorGranja,
      totalGalpones: totalGalpones,
    );
  }

  /// Prioridad: CENCO exacto por granja (3 díg.) mismo prefijo con galpones.
  static List<Map<String, dynamic>> resolveOffline({
    required String granjaCodigo,
    required String campania,
    required Map<String, List<Map<String, dynamic>>> galponesPorGranja,
    required Map<String, List<Map<String, dynamic>>> galponesPorCenco,
    List<Map<String, dynamic>>? cencosLista,
  }) {
    final codSel = granjaCodigo.trim();
    if (codSel.isEmpty) return [];

    final g3 = normGranja(
      normalizarCodigoCenco(codSel).length >= 6
          ? normalizarCodigoCenco(codSel).substring(0, 3)
          : codSel,
    );
    final camp = padCampania(
      campania.isNotEmpty
          ? campania
          : (normalizarCodigoCenco(codSel).length >= 6
              ? normalizarCodigoCenco(codSel).substring(normalizarCodigoCenco(codSel).length - 3)
              : ''),
    );
    final cod6 = normalizarCodigoCenco(codSel).length >= 6
        ? normalizarCodigoCenco(codSel)
        : codigoCenco6(g3, camp);

    final porCenco = galponesPorCenco[cod6] ?? [];
    if (porCenco.isNotEmpty) return List<Map<String, dynamic>>.from(porCenco);

    final porGranja = galponesPorGranja[g3] ?? [];
    if (porGranja.isNotEmpty) return List<Map<String, dynamic>>.from(porGranja);

    if (cencosLista == null || cencosLista.isEmpty) return [];

    Map<String, dynamic>? pick;
    for (final c in cencosLista) {
      final cc = normalizarCodigoCenco((c['codigo'] ?? '').toString());
      if (cc == cod6 && tieneGalponesUtiles(c)) {
        return parseGalponesList(c['galpones'], codigoCenco: cc);
      }
    }

    final camp3 = padCampania(camp);
    final mismaCamp = cencosLista.where((c) {
      final cc = normalizarCodigoCenco((c['codigo'] ?? '').toString());
      return cc.length >= 6 &&
          normGranja(cc) == g3 &&
          cc.substring(cc.length - 3) == camp3 &&
          tieneGalponesUtiles(c);
    }).toList();
    if (mismaCamp.isNotEmpty) {
      return parseGalponesList(mismaCamp.first['galpones'], codigoCenco: mismaCamp.first['codigo']?.toString());
    }

    final mismoPrefijo = cencosLista.where((c) {
      final cc = normalizarCodigoCenco((c['codigo'] ?? '').toString());
      return cc.length >= 6 && normGranja(cc) == g3 && tieneGalponesUtiles(c);
    }).toList()
      ..sort((a, b) => (b['codigo'] ?? '').toString().compareTo((a['codigo'] ?? '').toString()));

    for (final c in mismoPrefijo) {
      pick = c;
      break;
    }
    if (pick != null) {
      return parseGalponesList(pick['galpones'], codigoCenco: pick['codigo']?.toString());
    }

    return [];
  }
}
