import 'package:flutter_test/flutter_test.dart';
import 'package:gc_verificacion/utils/dni_code_parser.dart';

void main() {
  group('DniCodeParser', () {
    test('acepta ocho dígitos exactos', () {
      expect(DniCodeParser.parse('12345678'), '12345678');
    });

    test('ignora espacios alrededor', () {
      expect(DniCodeParser.parse('  12345678  '), '12345678');
    });

    test('extrae el bloque de un código con separadores', () {
      expect(DniCodeParser.parse('12345678|PEREZ|JUAN'), '12345678');
    });

    test('extrae el bloque al inicio seguido de texto', () {
      expect(DniCodeParser.parse('12345678ABC'), '12345678');
    });

    test('rechaza vacío y nulo', () {
      expect(DniCodeParser.parse(''), isNull);
      expect(DniCodeParser.parse(null), isNull);
    });

    test('rechaza dos bloques distintos', () {
      expect(DniCodeParser.parse('12345678 87654321'), isNull);
    });
  });
}
