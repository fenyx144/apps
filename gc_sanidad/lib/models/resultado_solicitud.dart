class ResultadoAnalisisCuali {
  final String codigo;
  final String nombre;
  final String resultado;
  final String observaciones;

  ResultadoAnalisisCuali({
    required this.codigo,
    required this.nombre,
    required this.resultado,
    required this.observaciones,
  });

  factory ResultadoAnalisisCuali.fromJson(Map<String, dynamic> json) {
    final codigoRaw = json['codigo'];
    final nombreRaw = json['nombre'];
    final resultadoRaw = json['resultado'];
    final observacionesRaw = json['observaciones'];

    String toStringValue(dynamic value) {
      if (value == null) return '';
      return value is String ? value : value.toString();
    }

    return ResultadoAnalisisCuali(
      codigo: toStringValue(codigoRaw),
      nombre: toStringValue(nombreRaw),
      resultado: toStringValue(resultadoRaw),
      observaciones: toStringValue(observacionesRaw),
    );
  }
}
class ResultadoAnalisisCuanti {
  final String codigo;
  final String nombre;
  final double? gmean;
  final double? cv;
  final double? sd;
  final int? countMuestras;
  final List<double?> nivelesS; // s01–s06
  final List<double?> nivelesT; // t01–t25 nuevo

  ResultadoAnalisisCuanti({
    required this.codigo,
    required this.nombre,
    this.gmean,
    this.cv,
    this.sd,
    this.countMuestras,
    required this.nivelesS,
    required this.nivelesT, // añadido
  });

  factory ResultadoAnalisisCuanti.fromJson(Map<String, dynamic> json) {
    // Niveles S (s01–s06)
    final nivelesS = [
      _toDouble(json['s01']),
      _toDouble(json['s02']),
      _toDouble(json['s03']),
      _toDouble(json['s04']),
      _toDouble(json['s05']),
      _toDouble(json['s06']),
    ];

    // Niveles T (t01–t25)
    final nivelesT = List.generate(25, (i) {
      final key = 't${(i + 1).toString().padLeft(2, '0')}'; // t01, t02, ..., t25
      return _toDouble(json[key]);
    });

    return ResultadoAnalisisCuanti(
      codigo: json['codigo'] as String? ?? '',
      nombre: json['nombre'] as String? ?? '',
      gmean: _toDouble(json['gmean']),
      cv: _toDouble(json['cv']),
      sd: _toDouble(json['sd']),
      countMuestras: json['count_muestras'] is int ? json['count_muestras'] : null,
      nivelesS: nivelesS,
      nivelesT: nivelesT,
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null || value == 'No ingresado') return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || trimmed == 'No ingresado') return null;
      return double.tryParse(trimmed);
    }
    return null;
  }
}
// models/resultado_solicitud.dart
class DocumentoPdf {
  final String ruta; // Esta es la ruta completa: "uploads/.../archivo.pdf"
  final String nombre;
  DocumentoPdf({required this.ruta, required this.nombre});

  factory DocumentoPdf.fromJson(Map<String, dynamic> json) {
    // Asegúrate de que `archRuta` sea string, incluso si viene como número
    final rutaRaw = json['ruta'];
    final ruta = rutaRaw is String ? rutaRaw : rutaRaw.toString();
    final nombre = ruta.split('/').last;
    print('nombre: $nombre');
    print('ruta: $ruta');
    return DocumentoPdf(ruta: ruta, nombre: nombre);
  }
}
