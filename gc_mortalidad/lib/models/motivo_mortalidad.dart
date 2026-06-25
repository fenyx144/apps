class MotivoMortalidad {
  final String codigo;
  final String nombre;

  MotivoMortalidad({required this.codigo, required this.nombre});

  factory MotivoMortalidad.fromJson(Map<String, dynamic> json) {
    return MotivoMortalidad(
      codigo: (json['tcod_mort'] ?? json['codigo'] ?? '').toString(),
      nombre: (json['tnom_mort'] ?? json['nombre'] ?? '').toString(),
    );
  }
}
