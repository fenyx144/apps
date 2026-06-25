class Cenco {
  final String codigo;
  final String nombre;
  final String edad;
  final String? fecIngMin; // Fecha de ingreso mínima (YYYY-MM-DD)

  Cenco({
    required this.codigo,
    required this.nombre,
    required this.edad,
    this.fecIngMin,
  });

  /// Código de granja (3 primeros dígitos del CENCO).
  String get granjaCodigo {
    final c = codigo.trim();
    if (c.length >= 3) return c.substring(0, 3);
    return c;
  }

  /// Etiqueta para listas: código de granja primero, luego nombre.
  String get displayLabel {
    final g = granjaCodigo;
    final n = nombre.trim();
    if (g.isEmpty) return n;
    if (n.isEmpty) return g;
    if (n.startsWith(g) || n.startsWith('$g ') || n.startsWith('$g-')) {
      return n;
    }
    return '$g - $n';
  }

  factory Cenco.fromJson(Map<String, dynamic> json) {
    // Convertir edad a String (puede venir como int o String desde el servidor)
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