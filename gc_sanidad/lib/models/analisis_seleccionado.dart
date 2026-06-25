// models/analisis_seleccionado.dart
class AnalisisSeleccionado {
  final String id;
  final String analisisCodigo;
  final String analisisNombre;
  final String paqueteCodigo;
  final String paqueteNombre;
  
  AnalisisSeleccionado({
    required this.id,
    required this.analisisCodigo,
    required this.analisisNombre,
    required this.paqueteCodigo,
    required this.paqueteNombre,
  });

  @override
  bool operator ==(Object other) =>
      other is AnalisisSeleccionado &&
      analisisCodigo == other.analisisCodigo
      &&
      paqueteCodigo == other.paqueteCodigo;

  @override
  int get hashCode => analisisCodigo.hashCode;

  Map<String, dynamic> toJson() {
    return {
      'analisis_id': id,
      'analisis_codigo': analisisCodigo,
      'analisis_nombre': analisisNombre,
      'paquete_codigo': paqueteCodigo,
      'paquete_nombre': paqueteNombre,
    };
  }

  static AnalisisSeleccionado fromJson(Map<String, dynamic> json) {
    return AnalisisSeleccionado(
      id: json['analisis_id'] ?? '',
      analisisCodigo: json['analisis_codigo'] ?? '',
      analisisNombre: json['analisis_nombre'] ?? '',
      paqueteCodigo: json['paquete_codigo'] ?? '',
      paqueteNombre: json['paquete_nombre'] ?? '',
    );
  }
}