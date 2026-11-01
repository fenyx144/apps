/// DNI peruano (8 dígitos) y carné de extranjería (CEE, MRZ TD1 / Factiliza).
library;

import 'dni_utils.dart';

enum DocumentoPersonaTipo { dni, cee }

class DocumentoPersona {
  const DocumentoPersona({required this.id, required this.tipo});

  final String id;
  final DocumentoPersonaTipo tipo;

  static const int maxLength = 15;
  static const int minCeeLength = 6;
  /// CEE numérico peruano (Factiliza / MRZ TD2): 9 dígitos; la MRZ suele añadir un dígito de control al final.
  static const int ceeNumericoLen = 9;

  static String normalizar(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    final soloDigitos = t.replaceAll(RegExp(r'\D'), '');
    if (RegExp(r'^\d{8}$').hasMatch(soloDigitos) &&
        (t.replaceAll(RegExp(r'\D'), '').length == t.replaceAll(RegExp(r'\s'), '').length ||
            soloDigitos.length == 8)) {
      return soloDigitos;
    }
    return t.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  static DocumentoPersona? parse(String? raw) {
    final cee = parseSoloCee(raw);
    if (cee != null) return cee;
    final dni = DniCodeParser.parse(raw);
    if (dni != null) {
      return DocumentoPersona(id: dni, tipo: DocumentoPersonaTipo.dni);
    }
    return null;
  }

  /// Quita el dígito de control MRZ si el CEE numérico viene con 10 dígitos.
  static String normalizarCeeConsulta(String raw) {
    final cee = normalizar(raw);
    if (RegExp(r'^\d{10}$').hasMatch(cee)) {
      return cee.substring(0, ceeNumericoLen);
    }
    return cee;
  }

  /// Carné (CEE) sin interpretar bloques de 8 dígitos como DNI (p. ej. MRZ).
  static DocumentoPersona? parseSoloCee(String? raw) {
    final cee = normalizarCeeConsulta(normalizar(raw ?? ''));
    if (_ceeValido(cee)) {
      return DocumentoPersona(id: cee, tipo: DocumentoPersonaTipo.cee);
    }
    return null;
  }

  static bool _ceeValido(String cee) {
    if (cee.length < minCeeLength || cee.length > maxLength) return false;
    if (RegExp(r'^\d{8}$').hasMatch(cee)) return false;
    return RegExp(r'^[A-Z0-9]+$').hasMatch(cee);
  }

  static bool esCompleto(String raw) => parse(raw) != null;

  /// Número de documento desde MRZ (carné extranjería TD1).
  static DocumentoPersona? desdeMrz({
    required String documentNumber,
    String personalNumber = '',
  }) {
    for (final candidato in [
      documentNumber,
      personalNumber,
    ]) {
      final p = parse(candidato);
      if (p != null && p.tipo == DocumentoPersonaTipo.cee) return p;
      if (p != null) return p;
    }
    final doc = normalizar(documentNumber);
    if (_ceeValido(doc)) {
      return DocumentoPersona(id: doc, tipo: DocumentoPersonaTipo.cee);
    }
    return null;
  }
}
