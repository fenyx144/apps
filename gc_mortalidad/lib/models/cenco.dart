import '../utils/text_utils.dart';
import 'galpon.dart';

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

  int get edadDias =>
      computeEdadInDias(fecIngMin) ?? (int.tryParse(edad.trim()) ?? 0);

  /// Promedio de edades de galpones (misma lógica que get_cencos_galpones.php).
  static int edadPromedioFromGalpones(List<Galpon> galpones) {
    final edades =
        galpones.map((g) => g.edadDias).where((e) => e > 0).toList();
    if (edades.isEmpty) return 0;
    return (edades.reduce((a, b) => a + b) / edades.length).round();
  }

  Cenco withEdadFromGalpones(List<Galpon> galpones) {
    final promedio = edadPromedioFromGalpones(galpones);
    if (promedio <= 0) return this;
    return Cenco(
      codigo: codigo,
      nombre: nombre,
      edad: promedio.toString(),
      fecIngMin: fecIngMin,
    );
  }

  String get displayLabel {
    final g = granjaCodigo;
    final n = nombre.trim();
    final e = edadDias;
    if (g.isEmpty && n.isEmpty) return codigo;
    String base;
    if (g.isEmpty) {
      base = n;
    } else if (n.isEmpty) {
      base = g;
    } else {
      base = '$g - $n';
    }
    if (e > 0) {
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
  String get subtitleAge => 'Edad: ${edadDias > 0 ? edadDias : 0} d\u00edas';

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
