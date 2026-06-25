import 'dart:convert';

enum OrigenNecropsia { grs, externo, traspatio }

class NecropsiasOrigen {
  static OrigenNecropsia inferirDesdeGranja(String codigo) {
    final c = codigo.trim().toUpperCase();
    if (c.isEmpty) return OrigenNecropsia.grs;
    if (c.startsWith('E')) return OrigenNecropsia.externo;
    if (c.startsWith('T')) return OrigenNecropsia.traspatio;
    return OrigenNecropsia.grs;
  }

  static String origenToDespliegue(OrigenNecropsia o) {
    switch (o) {
      case OrigenNecropsia.externo:
        return 'EXTERNO';
      case OrigenNecropsia.traspatio:
        return 'TRASPATIO';
      case OrigenNecropsia.grs:
        return 'GRS';
    }
  }

  static OrigenNecropsia despliegueToOrigen(String d) {
    final u = d.trim().toUpperCase();
    if (u == 'EXTERNO') return OrigenNecropsia.externo;
    if (u == 'TRASPATIO') return OrigenNecropsia.traspatio;
    return OrigenNecropsia.grs;
  }

  static String origenLabel(OrigenNecropsia o) {
    switch (o) {
      case OrigenNecropsia.externo:
        return 'EXTERNO';
      case OrigenNecropsia.traspatio:
        return 'TRASPATIO';
      case OrigenNecropsia.grs:
        return 'GRS';
    }
  }

  static Map<String, String> cabeceraFromForm({
    required OrigenNecropsia origen,
    String? codigoGranja,
    String? campania,
    String? galpon,
    String? edad,
    String? fectra,
    String? tcencos,
    String? codigoOrigenExt,
  }) {
    final esExt = origen == OrigenNecropsia.externo || origen == OrigenNecropsia.traspatio;
    if (esExt) {
      final cod = (codigoOrigenExt ?? '').trim();
      return {
        'origen': origenLabel(origen),
        'granja': cod,
        'campania': '000',
        'galpon': '0',
        'edad': (edad ?? '').trim(),
        'fectra': (fectra ?? '').trim(),
        'tcencos': cod,
      };
    }
    final g = (codigoGranja ?? '').trim();
    return {
      'origen': 'GRS',
      'granja': g,
      'campania': (campania ?? '').trim().isNotEmpty
          ? campania!.trim()
          : (g.length >= 3 ? g.substring(g.length - 3) : ''),
      'galpon': (galpon ?? '').trim(),
      'edad': (edad ?? '').trim(),
      'fectra': (fectra ?? '').trim(),
      'tcencos': (tcencos ?? '').trim(),
    };
  }

  static String huellaCabeceraJson(Map<String, String> cab) {
    return jsonEncode({
      'origen': cab['origen'] ?? 'GRS',
      'granja': cab['granja'] ?? '',
      'campania': cab['campania'] ?? '',
      'galpon': cab['galpon'] ?? '',
      'edad': cab['edad'] ?? '',
      'fectra': cab['fectra'] ?? '',
    });
  }

  static String idDesarrollado({
    required String granja,
    required String galpon,
    required String fectra,
    required String numreg,
  }) {
    if (granja.isEmpty || fectra.isEmpty || numreg.isEmpty) return '';
    final gp = galpon.isNotEmpty ? galpon : '0';
    return '$granja|$gp|$fectra|$numreg';
  }

  static bool esOrigenExtTp(String granja) {
    final g = granja.trim().toUpperCase();
    if (g.isEmpty) return false;
    return g.startsWith('E') || g.startsWith('T');
  }
}
