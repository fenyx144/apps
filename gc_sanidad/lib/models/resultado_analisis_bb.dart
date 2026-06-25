// models/resultado_analisis_bb.dart
/*class ResultadoAnalisisBB {
  final String codigoEnvio;
  final String idAnalisis;
  final double? gmean;
  final double? cv;
  final double? sd; // desviación estándar
  final int? countMuestras;
  final List<double?> nivelesS; // [s01, s02, ..., s06]

  ResultadoAnalisisBB({
    required this.codigoEnvio,
    required this.idAnalisis,
    this.gmean,
    this.cv,
    this.sd,
    this.countMuestras,
    required this.nivelesS,
  });

  factory ResultadoAnalisisBB.fromJson(Map<String, dynamic> json) {
    List<double?> extraerNiveles() {
      return [
        _toDouble(json['s01']),
        _toDouble(json['s02']),
        _toDouble(json['s03']),
        _toDouble(json['s04']),
        _toDouble(json['s05']),
        _toDouble(json['s06']),
      ];
    }

    return ResultadoAnalisisBB(
      codigoEnvio: json['codigo_envio'] ?? '',
      idAnalisis: json['id_analisis'] ?? '',
      gmean: _toDouble(json['gmean']),
      cv: _toDouble(json['cv']),
      sd: _toDouble(json['desviacion_estandar']),
      countMuestras: json['count_muestras'] is int
          ? json['count_muestras']
          : int.tryParse(json['count_muestras']?.toString() ?? '') ?? null,
      nivelesS: extraerNiveles(),
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null || value == '') return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}*/
class ResultadoAnalisisBB {
  final String codigoEnvio;
  final String idAnalisis;
  final double? gmean;
  final double? cv;
  final double? sd; // ← debe coincidir con el alias en SQL
  final int? countMuestras;
  final List<double?> nivelesS;

  ResultadoAnalisisBB({
    required this.codigoEnvio,
    required this.idAnalisis,
    this.gmean,
    this.cv,
    this.sd,
    this.countMuestras,
    required this.nivelesS,
  });

  factory ResultadoAnalisisBB.fromJson(Map<String, dynamic> json) {
    // Convertir s01–s06 a lista
    final niveles = [
      _toDouble(json['s01']),
      _toDouble(json['s02']),
      _toDouble(json['s03']),
      _toDouble(json['s04']),
      _toDouble(json['s05']),
      _toDouble(json['s06']),
    ];

    return ResultadoAnalisisBB(
      codigoEnvio: json['codigo_envio'] as String? ?? '',
      idAnalisis: json['id_analisis'] as String? ?? '',
      gmean: _toDouble(json['gmean']),
      cv: _toDouble(json['cv']),
      sd: _toDouble(json['sd']),
      countMuestras: json['count_muestras'] is int ? json['count_muestras'] : null,
      nivelesS: niveles,
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed;
    }
    return null;
  }
}