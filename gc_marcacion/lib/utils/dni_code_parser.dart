/// Extrae el DNI de 8 dígitos de un código de barras o QR.
class DniCodeParser {
  static final RegExp _soloOcho = RegExp(r'^\d{8}$');
  static final RegExp _separadores = RegExp(r'[|,;/\s]+');
  static final RegExp _inicio = RegExp(r'^(\d{8})\D');
  static final RegExp _ochoDigitos = RegExp(r'\d{8}');

  static String? parse(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return null;
    if (_soloOcho.hasMatch(s)) return s;

    for (final token in s.split(_separadores)) {
      final t = token.trim();
      if (_soloOcho.hasMatch(t)) return t;
    }

    final alInicio = _inicio.firstMatch(s);
    if (alInicio != null) return alInicio.group(1);

    final bloques = _ochoDigitos.allMatches(s).map((m) => m.group(0)!).toSet();
    return bloques.length == 1 ? bloques.first : null;
  }
}
