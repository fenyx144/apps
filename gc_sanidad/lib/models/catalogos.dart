// models/catalogos.dart
class TipoMuestra {
  final String codigo;
  final String nombre;
  final int longitudCodigo;
  final int gri;

  TipoMuestra({
    required this.codigo,
    required this.nombre,
    required this.longitudCodigo,
    this.gri = 0,
  });

  factory TipoMuestra.fromJson(Map<String, dynamic> json) {
    return TipoMuestra(
      codigo: json['codigo'].toString(),
      nombre: json['nombre'].toString(),
      longitudCodigo: int.tryParse('${json['lonCod']}') ?? 0,
      gri: int.tryParse('${json['gri']}') ?? 0,
    );
  }
}

class Analisis {
  final String codigo;
  final String nombre;
  final String? paquete; // null si no pertenece a paquete

  Analisis({required this.codigo, required this.nombre, this.paquete});

  factory Analisis.fromJson(Map<String, dynamic> json) {
    return Analisis(
      codigo: json['codigo'],
      nombre: json['nombre'],
      paquete: json['paquete'],
    );
  }
}

class Paquete {
  final String codigo;
  final String nombre;

  Paquete({required this.codigo, required this.nombre});

  factory Paquete.fromJson(Map<String, dynamic> json) {
    return Paquete(
      codigo: json['codigo'],
      nombre: json['nombre'],
    );
  }
}
