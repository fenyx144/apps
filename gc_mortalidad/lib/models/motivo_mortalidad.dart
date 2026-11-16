class MotivoMortalidad {
  final String codigo;
  final String nombre;
  final String? clase;

  MotivoMortalidad({required this.codigo, required this.nombre, this.clase});

  factory MotivoMortalidad.fromJson(Map<String, dynamic> json) {
    final clase = (json['clase'] ?? '').toString().trim().toUpperCase();
    return MotivoMortalidad(
      codigo: (json['tcod_mort'] ?? json['codigo'] ?? '').toString(),
      nombre: (json['tnom_mort'] ?? json['nombre'] ?? '').toString(),
      clase: clase == 'ME' || clase == 'MN' ? clase : null,
    );
  }
}
