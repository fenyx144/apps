// models/solicitud_model.dart
class SolicitudCabecera {
  final String codEnvio;
  final String fecEnvio;
  final String horaEnvio;
  final String codLab;
  final String nomLab;
  final String codEmpTrans;
  final String nomEmpTrans;
  final String usuarioRegistrador;
  final String usuarioResponsable;
  final String autorizadoPor;
  final DateTime fechaHoraRegistro;

  SolicitudCabecera({
    required this.codEnvio,
    required this.fecEnvio,
    required this.horaEnvio,
    required this.codLab,
    required this.nomLab,
    required this.codEmpTrans,
    required this.nomEmpTrans,
    required this.usuarioRegistrador,
    required this.usuarioResponsable,
    required this.autorizadoPor,
    required this.fechaHoraRegistro,
  });

  factory SolicitudCabecera.fromMap(Map<String, dynamic> map) {
    return SolicitudCabecera(
      codEnvio: map['codEnvio'] as String,
      fecEnvio: map['fecEnvio'] as String,
      horaEnvio: map['horaEnvio'] as String,
      codLab: map['codLab'] as String,
      nomLab: map['nomLab'] as String,
      codEmpTrans: map['codEmpTrans'] as String,
      nomEmpTrans: map['nomEmpTrans'] as String,
      usuarioRegistrador: map['usuarioRegistrador'] as String,
      usuarioResponsable: map['usuarioResponsable'] as String,
      autorizadoPor: map['autorizadoPor'] as String,
      fechaHoraRegistro: DateTime.parse(map['fechaHoraRegistro'] as String),
    );
  }
}

class SolicitudDetalle {
  final String codEnvio;
  final int posSolicitud;
  final String codRef;
  final String fecToma;
  final int numMuestras;
  final String codMuestra;
  final String nomMuestra;
  final String codAnalisis;
  final String nomAnalisis;
  final String obs;
  final String id;

  SolicitudDetalle({
    required this.codEnvio,
    required this.posSolicitud,
    required this.codRef,
    required this.fecToma,
    required this.numMuestras,
    required this.codMuestra,
    required this.nomMuestra,
    required this.codAnalisis,
    required this.nomAnalisis,
    required this.obs,
    required this.id,
  });

  factory SolicitudDetalle.fromMap(Map<String, dynamic> map) {
    return SolicitudDetalle(
      codEnvio: map['codEnvio'] as String,
      posSolicitud: int.tryParse(map['posSolicitud'].toString()) ?? 0,
      codRef: map['codRef'] as String,
      fecToma: map['fecToma'] as String,
      numMuestras: int.tryParse(map['numMuestras'].toString()) ?? 0,
      codMuestra: map['codMuestra'] as String,
      nomMuestra: map['nomMuestra'] as String,
      codAnalisis: map['codAnalisis'] as String,
      nomAnalisis: map['nomAnalisis'] as String,
      obs: map['obs'] as String,
      id: map['id'] as String,
    );
  }

  // Helper: nombre completo del análisis
  String get displayName => '$nomAnalisis ($codAnalisis)';
}
