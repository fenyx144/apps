import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:mrz_parser/mrz_parser.dart';

import 'documento_persona.dart';

/// Extrae MRZ TD2 (2×36, carné PE) o TD1 (3×30) desde OCR.
abstract final class MrzOcrParser {
  MrzOcrParser._();

  static const int _td1Len = 30;
  static const int _td1Count = 3;
  static const int _td2Len = 36;
  static const int _td2Count = 2;

  static final RegExp _mrzCharset = RegExp(r'^[A-Z0-9<]+$');
  static final RegExp _ruido = RegExp(r'[^A-Z0-9<]');
  static final RegExp _ceeEnLinea2 = RegExp(r'^(\d{6,15})[A-Z]{3}');

  /// Desde reconocimiento ML Kit (foto o frame).
  static DocumentoPersona? documentoDesdeReconocimiento(RecognizedText recognized) {
    final lineas = <String>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final n = _normalizarLinea(line.text);
        if (n != null) lineas.add(n);
      }
    }
    final desdeLineas = _documentoDesdeLineasCandidatas(lineas);
    if (desdeLineas != null) return desdeLineas;
    return documentoDesdeTexto(recognized.text);
  }

  static DocumentoPersona? documentoDesdeTexto(String raw) {
    final lineas = raw
        .split(RegExp(r'[\r\n]+'))
        .map(_normalizarLinea)
        .whereType<String>()
        .toList();
    var doc = _documentoDesdeLineasCandidatas(lineas);
    if (doc != null) return doc;

    final compacto = _normalizarLinea(raw.replaceAll(RegExp(r'\s+'), ''));
    if (compacto != null) {
      doc = _documentoDesdeBloqueContinuo(compacto, _td2Len, _td2Count, _td2Len);
      doc ??= _documentoDesdeBloqueContinuo(compacto, _td1Len, _td1Count, _td1Len);
    }
    return doc;
  }

  static DocumentoPersona? _documentoDesdeLineasCandidatas(List<String> lineas) {
    if (lineas.length >= _td2Count) {
      for (var i = 0; i <= lineas.length - _td2Count; i++) {
        final doc = _parseGrupo(lineas.sublist(i, i + _td2Count), _td2Len);
        if (doc != null) return doc;
      }
    }
    if (lineas.length >= _td1Count) {
      for (var i = 0; i <= lineas.length - _td1Count; i++) {
        final doc = _parseGrupo(lineas.sublist(i, i + _td1Count), _td1Len);
        if (doc != null) return doc;
      }
    }
    return null;
  }

  static DocumentoPersona? _documentoDesdeBloqueContinuo(
    String s,
    int lineLen,
    int count,
    int padLen,
  ) {
    final minLen = lineLen * count - 8;
    if (s.length < minLen) return null;
    for (var start = 0; start <= s.length - lineLen * count; start++) {
      final grupo = <String>[];
      for (var k = 0; k < count; k++) {
        final end = start + (k + 1) * lineLen;
        if (end > s.length) return null;
        grupo.add(_ajustarLongitud(s.substring(start + k * lineLen, end), padLen));
      }
      final doc = _parseGrupoExacto(grupo, padLen);
      if (doc != null) return doc;
    }
    return null;
  }

  static DocumentoPersona? _parseGrupo(List<String> rawLines, int padLen) {
    final lines = rawLines.map((l) => _ajustarLongitud(l, padLen)).toList();
    return _parseGrupoExacto(lines, padLen);
  }

  static DocumentoPersona? _parseGrupoExacto(List<String> lines, int padLen) {
    if (lines.isEmpty) return null;
    if (!lines.every((l) => l.length == padLen && _mrzCharset.hasMatch(l))) {
      return null;
    }
    if (lines.where((l) => l.contains('<')).length < 1) return null;

    final result = MRZParser.tryParse(lines);
    if (result != null) {
      return _documentoDesdeResultado(result, linea2: lines.length >= 2 ? lines[1] : '');
    }

    // OCR acorta líneas: reintento con padding a TD2/TD1 estándar.
    if (lines.length == _td2Count && padLen != _td2Len) {
      final padded = lines.map((l) => _ajustarLongitud(l, _td2Len)).toList();
      final r2 = MRZParser.tryParse(padded);
      if (r2 != null) {
        return _documentoDesdeResultado(r2, linea2: padded[1]);
      }
    }
    if (lines.length == _td1Count && padLen != _td1Len) {
      final padded = lines.map((l) => _ajustarLongitud(l, _td1Len)).toList();
      final r1 = MRZParser.tryParse(padded);
      if (r1 != null) {
        return _documentoDesdeResultado(r1, linea2: padded.length >= 2 ? padded[1] : '');
      }
    }
    return null;
  }

  static DocumentoPersona? _documentoDesdeResultado(
    MRZResult result, {
    required String linea2,
  }) {
    // En carnés PE la 2.ª línea suele traer el CEE completo antes del país (VEN).
    final m = _ceeEnLinea2.firstMatch(linea2);
    if (m != null) {
      final p = DocumentoPersona.parseSoloCee(m.group(1)!);
      if (p != null) return p;
    }

    return DocumentoPersona.desdeMrz(
      documentNumber: result.documentNumber,
      personalNumber: result.personalNumber,
    );
  }

  static String? _normalizarLinea(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    var s = raw.toUpperCase().trim();
    s = s
        .replaceAll('«', '<')
        .replaceAll('‹', '<')
        .replaceAll('>', '<')
        .replaceAll('|', 'I')
        .replaceAll(' ', '')
        .replaceAll(_ruido, '');
    if (s.length < 18) return null;
    if (!s.contains('<') && !RegExp(r'^[A-Z0-9]{6,}').hasMatch(s)) return null;
    return s;
  }

  static String _ajustarLongitud(String line, int targetLen) {
    if (line.length == targetLen) return line;
    if (line.length > targetLen) return line.substring(0, targetLen);
    return line.padRight(targetLen, '<');
  }
}
