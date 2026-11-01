import 'package:flutter_test/flutter_test.dart';

import 'package:bioseguridad/utils/mrz_ocr_parser.dart';

void main() {
  test('MRZ TD1 de ejemplo (especimen)', () {
    const raw = '''
I<SWE59000002<8198703142391<<<
8703145M1701027SWE<<<<<<<<<<<8
SPECIMEN<<SVEN<<<<<<<<<<<<<<<<
''';
    final doc = MrzOcrParser.documentoDesdeTexto(raw);
    expect(doc, isNotNull);
    expect(doc!.id, '59000002');
  });

  test('Carné PE: MRZ TD2 (2 líneas × 36)', () {
    const raw = '''
C<VENRIVAS<BARRIOS<<JOEL<DAVID<<<<<<<
0038874570VEN9006072M2409308<<<<<<<8
''';
    final doc = MrzOcrParser.documentoDesdeTexto(raw);
    expect(doc, isNotNull);
    expect(doc!.id, '003887457');
  });

  test('Ignora ruido alrededor de las líneas', () {
    const raw = '''
PERU
I<SWE59000002<8198703142391<<<
8703145M1701027SWE<<<<<<<<<<<8
SPECIMEN<<SVEN<<<<<<<<<<<<<<<<
fin
''';
    expect(MrzOcrParser.documentoDesdeTexto(raw), isNotNull);
  });
}
