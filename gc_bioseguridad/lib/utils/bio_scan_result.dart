/// Qué modo usa la pantalla de escaneo.
enum BioScanModo {
  /// Solo acepta códigos con DNI de 8 dígitos.
  dni,

  /// Placa física (teclado); no usa escáner de códigos.
  placa,

  /// DNI si el código lo trae; si no, placa.
  auto,
}

/// Resultado de escanear un código (DNI y/o placa).
class BioScanResult {
  const BioScanResult._({this.dni, this.placa});

  final String? dni;
  final String? placa;

  factory BioScanResult.dni(String value) =>
      BioScanResult._(dni: value.trim());

  factory BioScanResult.placa(String value) =>
      BioScanResult._(placa: value.trim());

  bool get isEmpty =>
      (dni == null || dni!.isEmpty) && (placa == null || placa!.isEmpty);
}
