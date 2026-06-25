
class EnvioGrupo {
  final String codEnvio;
  final int posSolicitud;
  final String estadoCualitativo;
  final String estadoCuantitativo;

  EnvioGrupo({
    required this.codEnvio,
    required this.posSolicitud,
    required this.estadoCualitativo,
    required this.estadoCuantitativo,
  });

  bool get estaCompleto =>
      estadoCualitativo == 'completado' && estadoCuantitativo == 'completado';

  factory EnvioGrupo.fromJson(Map<String, dynamic> json) {
    return EnvioGrupo(
      codEnvio: json['codigoEnvio'] as String? ?? '',
      posSolicitud: _toInt(json['posSolicitud']),
      estadoCualitativo: json['estadoCualitativo'] as String? ?? 'pendiente',
      estadoCuantitativo: json['estadoCuantitativo'] as String? ?? 'pendiente',
    );
  }

  static int _toInt(dynamic value, {int defaultValue = 0}) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is double && value == value.toInt().toDouble()) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? defaultValue;
    }
    return defaultValue;
  }
}