import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../services/plan_visitas_service.dart';

/// Extrae candidatos de placa peruana desde texto OCR (ej. ABC-123).
class PlacaOcrParser {
  PlacaOcrParser._();

  static const int minNorm = 5;

  static final RegExp _abc123 = RegExp(r'^[A-Z]{3}[0-9]{3}$');
  static final RegExp _ab1234 = RegExp(r'^[A-Z]{2}[0-9]{4}$');
  static final RegExp _mix6 = RegExp(r'^[A-Z0-9]{6}$');
  /// Moto / mixta peruana: letra–dígito–letra + 3 dígitos (A1B234).
  static final RegExp _motoLdl = RegExp(r'^[A-Z][0-9][A-Z][0-9]{3}$');

  static final List<RegExp> _patronesEnTexto = [
    // Separador: evita «ERU ABC» en «PERU ABC-123». Al menos un dígito en la cola.
    RegExp(
      r'[A-Z0-9]{3}[-\s]+(?=[A-Z0-9]*[0-9])[A-Z0-9]{3}(?![0-9A-Z])',
    ),
    RegExp(r'[A-Z0-9]{3}(?=[A-Z0-9]*[0-9])[A-Z0-9]{3}(?![0-9A-Z])'),
    RegExp(
      r'[A-Z0-9]{2}[-\s]+(?=[A-Z0-9]*[0-9])[A-Z0-9]{4}(?![0-9A-Z])',
    ),
    RegExp(r'[A-Z0-9]{2}(?=[A-Z0-9]*[0-9])[A-Z0-9]{4}(?![0-9A-Z])'),
  ];

  /// Prioriza líneas del OCR (más fiable que el bloque completo).
  static String? extraerDeReconocimiento(RecognizedText recognized) {
    final candidatos = <String>[];
    for (final block in recognized.blocks) {
      final unido = block.lines.map((l) => l.text).join(' ');
      final delBloque = extraer(unido);
      if (delBloque != null) candidatos.add(delBloque);
      for (final line in block.lines) {
        final p = extraer(line.text);
        if (p != null) candidatos.add(p);
      }
    }
    if (candidatos.isNotEmpty) {
      return _mejorEntre(candidatos);
    }
    return extraer(recognized.text);
  }

  /// Compara candidatos OCR (mayor = más confiable).
  static int puntajeCandidato(String norm) => _puntaje(norm);

  /// Formato peruano claro (ABC123, AB1234, moto): basta una variante de imagen.
  static bool esLecturaConfiable(String norm) => _puntaje(norm) >= 21;

  /// Elige placa cuando varias variantes de imagen coinciden parcialmente.
  static String? elegirPorVotos(List<String> candidatos) {
    if (candidatos.isEmpty) return null;
    final freq = <String, int>{};
    final puntos = <String, int>{};
    for (final raw in candidatos) {
      final norm = PlanDescarga.normPlaca(raw);
      if (norm.length < minNorm) continue;
      freq[norm] = (freq[norm] ?? 0) + 1;
      final p = _puntaje(norm);
      if (p > (puntos[norm] ?? 0)) puntos[norm] = p;
    }
    if (freq.isEmpty) return null;
    String? mejor;
    var votos = 0;
    var puntaje = 0;
    for (final e in freq.entries) {
      final p = puntos[e.key] ?? 0;
      if (e.value > votos || (e.value == votos && p > puntaje)) {
        votos = e.value;
        puntaje = p;
        mejor = e.key;
      }
    }
    return mejor;
  }

  static String? _mejorEntre(List<String> lista) {
    String? mejor;
    var puntaje = 0;
    for (final norm in lista) {
      final p = _puntaje(norm);
      if (p > puntaje) {
        puntaje = p;
        mejor = norm;
      }
    }
    return mejor;
  }

  static int _puntaje(String norm) {
    var p = norm.length;
    if (_abc123.hasMatch(norm)) return p + 20;
    if (_ab1234.hasMatch(norm)) return p + 15;
    if (_motoLdl.hasMatch(norm)) return p + 18;
    if (_esPlacaPeruana(norm)) return p + 10;
    return p;
  }

  /// Auto clásica, moto (A1B234), etc.: 6–7 alfanum con letras y dígitos.
  static bool _esPlacaPeruana(String norm) {
    if (norm.length == 6 && _motoLdl.hasMatch(norm)) return true;
    if (norm.length == 6 && _mix6.hasMatch(norm)) {
      return _tieneLetrasYDigitos(norm);
    }
    if (norm.length == 7 && _ab1234.hasMatch(norm)) return true;
    return false;
  }

  static bool _tieneLetrasYDigitos(String s) {
    return RegExp(r'[A-Z]').hasMatch(s) && RegExp(r'[0-9]').hasMatch(s);
  }

  /// Si el parser estricto falla, propone la mejor línea alfanumérica (diálogo).
  static String? sugerirDesdeReconocimiento(RecognizedText recognized) {
    String? mejor;
    var len = 0;
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final norm = PlanDescarga.normPlaca(line.text);
        if (norm.length < minNorm) continue;
        if (!_tieneLetrasYDigitos(norm)) continue;
        if (norm.length > len) {
          len = norm.length;
          mejor = norm.length <= 7 ? norm : norm.substring(0, 7);
        }
      }
    }
    return mejor;
  }

  /// Mejor placa en [textoOcr], normalizada (sin guiones).
  static String? extraer(String? textoOcr) {
    if (textoOcr == null || textoOcr.trim().isEmpty) return null;
    final upper = textoOcr.toUpperCase().replaceAll('\n', ' ');
    String? mejor;
    var mejorPuntaje = 0;

    void evaluar(String crudo) {
      final norm = _normalizarCrudo(crudo);
      if (norm == null) return;
      void considerar(String candidato, {int extra = 0}) {
        final puntaje = _puntaje(candidato) + extra;
        if (puntaje > mejorPuntaje) {
          mejorPuntaje = puntaje;
          mejor = candidato;
        }
      }

      considerar(norm);
      if (_motoLdl.hasMatch(norm)) {
        for (final v in variantesMotoDigitos(norm)) {
          considerar(v, extra: 1);
        }
      }
    }

    for (final re in _patronesEnTexto) {
      for (final m in re.allMatches(upper)) {
        evaluar(m.group(0) ?? '');
      }
    }

    for (final token in upper.split(RegExp(r'[^A-Z0-9]+'))) {
      evaluar(token);
    }
    return mejor;
  }

  /// Corrige confusiones típicas del OCR en formato ABC123 / AB1234.
  static String? _normalizarCrudo(String crudo) {
    var norm = PlanDescarga.normPlaca(crudo);
    if (norm.length < minNorm) return null;

    norm = _corregirFormatoPeruano(norm);
    if (_abc123.hasMatch(norm) ||
        _ab1234.hasMatch(norm) ||
        _esPlacaPeruana(norm)) {
      return norm;
    }
    return null;
  }

  static bool _caracterPareceDigitoOcr(String c) {
    return RegExp(r'^[0-9IOATLSBZGA4]$').hasMatch(c);
  }

  static String _corregirFormatoPeruano(String norm) {
    if (norm.length == 6) {
      if (_pareceMotoOcr(norm)) {
        final moto = _corregirMotoLdl(norm);
        if (_motoLdl.hasMatch(moto)) return moto;
      }
      final ab = _fijarLetrasDigitos(norm, 2, 4);
      final abc = _fijarLetrasDigitos(norm, 3, 3);
      if (_caracterPareceDigitoOcr(norm[2])) {
        if (_ab1234.hasMatch(ab)) return ab;
        if (_abc123.hasMatch(abc)) return abc;
      } else {
        if (_abc123.hasMatch(abc)) return abc;
        if (_ab1234.hasMatch(ab)) return ab;
      }
      final mix = _corregirMixto6(norm);
      if (_esPlacaPeruana(mix)) return mix;
      return norm;
    }
    if (norm.length == 7) {
      final six = norm.substring(0, 6);
      final ab = _fijarLetrasDigitos(six, 2, 4);
      if (_ab1234.hasMatch(ab)) return ab;
      final abc = _fijarLetrasDigitos(six, 3, 3);
      if (_abc123.hasMatch(abc)) return abc;
    }
    return norm;
  }

  static String _fijarLetrasDigitos(String s, int letras, int digitos) {
    if (s.length != letras + digitos) return s;
    final buf = StringBuffer();
    for (var i = 0; i < letras; i++) {
      buf.write(_comoLetra(s[i]));
    }
    for (var i = letras; i < s.length; i++) {
      buf.write(_comoDigito(s[i]));
    }
    return buf.toString();
  }

  static String _comoLetra(String c) {
    const map = {'0': 'O', '1': 'I', '4': 'A', '5': 'S', '8': 'B'};
    return map[c] ?? c;
  }

  static String _comoDigito(String c) {
    const map = {
      'O': '0',
      'Q': '0',
      'D': '0',
      'I': '1',
      'L': '1',
      'T': '1',
      'A': '4',
      'S': '5',
      'B': '8',
      'G': '6',
      'Z': '2',
    };
    return map[c] ?? c;
  }

  static String _comoLetraPlaca(String c) {
    const map = {
      '0': 'O',
      '1': 'I',
      '4': 'A',
      '5': 'S',
      '8': 'B',
      '6': 'G',
      '2': 'Z',
    };
    return map[c] ?? c;
  }

  /// Formato moto A1B234: OCR suele leer el «1» central como T/I.
  static String _corregirMotoLdl(String norm) {
    if (norm.length != 6) return norm;
    final out = StringBuffer()
      ..write(_comoLetraPlaca(norm[0]))
      ..write(_comoDigito(norm[1]))
      ..write(_comoLetraPlaca(norm[2]));
    for (var i = 3; i < 6; i++) {
      out.write(_comoDigito(norm[i]));
    }
    final s = out.toString();
    return _motoLdl.hasMatch(s) ? s : norm;
  }

  /// Centro «dígito» (1/T/I…), no letras como B de ABC123.
  static bool _centroPareceDigitoMoto(String c) {
    return RegExp(r'^[0-9ILOTGSZA]$').hasMatch(c);
  }

  static bool _pareceMotoOcr(String norm) {
    if (norm.length != 6) return false;
    if (!RegExp(r'^[A-Z]$').hasMatch(norm[0])) return false;
    if (!_centroPareceDigitoMoto(norm[1])) return false;
    if (!RegExp(r'^[A-Z]$').hasMatch(norm[2])) return false;
    return RegExp(r'^[0-9ILOTGSZBZGA]{3}$').hasMatch(norm.substring(3));
  }

  /// Moto / mixta (A1B234): corrige por posición; variantes 3↔5 en la cola numérica.
  static String _corregirMixto6(String norm) {
    if (_pareceMotoOcr(norm)) {
      final base = _corregirMotoLdl(norm);
      if (_motoLdl.hasMatch(base)) return base;
    }
    final buf = StringBuffer();
    for (var i = 0; i < 3; i++) {
      buf.write(norm[i]);
    }
    for (var i = 3; i < 6; i++) {
      buf.write(_comoDigito(norm[i]));
    }
    final out = buf.toString();
    return _tieneLetrasYDigitos(out) ? out : norm;
  }

  @visibleForTesting
  static List<String> variantesMotoDigitos(String normMotoLdl) {
    if (!_motoLdl.hasMatch(normMotoLdl)) return const [];
    final out = <String>[];
    for (var i = 3; i < 6; i++) {
      final c = normMotoLdl[i];
      final alt = switch (c) {
        '5' => '3',
        '8' => '3',
        _ => null,
      };
      if (alt != null) {
        out.add(
          normMotoLdl.substring(0, i) + alt + normMotoLdl.substring(i + 1),
        );
      }
    }
    return out;
  }

  static String formatearLegible(String norm) {
    final n = norm.trim().toUpperCase();
    if (n.length == 6 && _motoLdl.hasMatch(n)) {
      return '${n.substring(0, 3)}-${n.substring(3)}';
    }
    if (n.length == 6 && _abc123.hasMatch(n)) {
      return '${n.substring(0, 3)}-${n.substring(3)}';
    }
    if (n.length == 7 && _ab1234.hasMatch(n)) {
      return '${n.substring(0, 2)}-${n.substring(2)}';
    }
    if (n.length == 6) {
      return '${n.substring(0, 3)}-${n.substring(3)}';
    }
    return n;
  }

  /// Mayoría simple entre lecturas normalizadas (varios frames).
  static String? votarNormalizadas(List<String> normalizadas) {
    final freq = <String, int>{};
    for (final raw in normalizadas) {
      final n = PlanDescarga.normPlaca(raw);
      if (n.length < minNorm) continue;
      freq[n] = (freq[n] ?? 0) + 1;
    }
    if (freq.isEmpty) return null;
    var mejor = '';
    var votos = 0;
    for (final e in freq.entries) {
      if (e.value > votos || (e.value == votos && e.key.length > mejor.length)) {
        votos = e.value;
        mejor = e.key;
      }
    }
    return mejor.isEmpty ? null : formatearLegible(mejor);
  }

  /// Texto que se muestra en la tabla tras escanear o confirmar.
  static String paraCampo(String raw) {
    final t = raw.trim().toUpperCase();
    if (t.isEmpty) return t;
    if (RegExp(r'[- ]').hasMatch(t)) return t.replaceAll(' ', '');
    final norm = PlanDescarga.normPlaca(t);
    return formatearLegible(norm);
  }
}
