class Cenco {
  final String codigo;
  final String nombre;
  final String edad;
  final String? fecIngMin;

  Cenco({
    required this.codigo,
    required this.nombre,
    required this.edad,
    this.fecIngMin,
  });

  String get granjaCodigo {
    final c = codigo.trim();
    if (c.length >= 3) return c.substring(0, 3);
    return c;
  }

  String get campaniaCodigo {
    final c = codigo.trim();
    if (c.length >= 6) return c.substring(3, 6);
    if (c.length > 3) return c.substring(3);
    return '';
  }

  String get displayLabel {
    final g = granjaCodigo;
    final n = nombre.trim();
    final e = edad.trim();
    if (g.isEmpty && n.isEmpty) return codigo;
    String base;
    if (g.isEmpty) {
      base = n;
    } else if (n.isEmpty) {
      base = g;
    } else {
      base = '$g - $n';
    }
    if (e.isNotEmpty && e != '0') {
      base += ' ($e d\u00edas)';
    }
    return base;
  }

  /// Solo codigo (3 chars) + nombre, sin campania ni edad
  String get labelShort {
    final g = granjaCodigo;
    final n = nombre.trim();
    if (g.isEmpty && n.isEmpty) return codigo;
    if (g.isEmpty) return n;
    if (n.isEmpty) return g;
    return '$g - $n';
  }

  /// Para registro mortalidad: labelShort + "Edad: X"
  String get labelMortality => labelShort;

  /// Subtitulo con edad para dialogo de seleccion
  String get subtitleAge {
    final e = edad.trim();
    final edadStr = e.isNotEmpty ? e : '0';
    return 'Edad: $edadStr d\u00edas';
  }

  /// Para liquidacion/auditoria: labelShort sin edad
  String get labelFilter => labelShort;

  factory Cenco.fromJson(Map<String, dynamic> json) {
    final edadValue = json['edad'];
    final edadString = edadValue is int
        ? edadValue.toString()
        : (edadValue?.toString() ?? '0');

    return Cenco(
      codigo: json['codigo']?.toString() ?? '',
      nombre: json['nombre']?.toString() ?? '',
      edad: edadString,
      fecIngMin: json['fec_ing_min']?.toString(),
    );
  }
}
