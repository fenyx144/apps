import 'package:bioseguridad/utils/placa_ocr_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extrae ABC-123 del texto OCR', () {
    expect(
      PlacaOcrParser.extraer('PERU ABC-123 TRANSITO'),
      'ABC123',
    );
    expect(
      PlacaOcrParser.formatearLegible('ABC123'),
      'ABC-123',
    );
  });

  test('corrige I por 1 en la parte numérica', () {
    expect(PlacaOcrParser.extraer('ABC-I23'), 'ABC123');
  });

  test('corrige A por 4 en dígitos y 4 por A en letras', () {
    expect(PlacaOcrParser.extraer('ABC-A23'), 'ABC423');
    expect(PlacaOcrParser.extraer('ABC12A'), 'ABC124');
    expect(PlacaOcrParser.extraer('4BC-123'), 'ABC123');
    expect(PlacaOcrParser.extraer('4B-1234'), 'AB1234');
  });

  test('esLecturaConfiable reconoce formatos peruanos', () {
    expect(PlacaOcrParser.esLecturaConfiable('ABC123'), isTrue);
    expect(PlacaOcrParser.esLecturaConfiable('AB12'), isFalse);
  });

  test('elegirPorVotos prioriza lectura repetida', () {
    expect(
      PlacaOcrParser.elegirPorVotos(['ABC423', 'ABC423', 'ABC123']),
      'ABC423',
    );
  });

  test('acepta placa moto A1B-234', () {
    expect(PlacaOcrParser.extraer('A1B-234'), 'A1B234');
  });

  test('corrige OCR moto ATB254 hacia A1B234', () {
    expect(PlacaOcrParser.extraer('ATB254'), 'A1B234');
    expect(PlacaOcrParser.extraer('ATB-254'), 'A1B234');
  });

  test('paraCampo conserva guion en tabla', () {
    expect(PlacaOcrParser.paraCampo('ABC-123'), 'ABC-123');
    expect(PlacaOcrParser.paraCampo('ABC123'), 'ABC-123');
  });

  test('ignora ruido corto', () {
    expect(PlacaOcrParser.extraer('AB 12'), isNull);
    expect(PlacaOcrParser.extraer('RANDOMTEXTONLY'), isNull);
  });
}
