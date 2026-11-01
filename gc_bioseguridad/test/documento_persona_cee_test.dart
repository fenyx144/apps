import 'package:flutter_test/flutter_test.dart';

import 'package:bioseguridad/utils/documento_persona.dart';

void main() {
  test('CEE numérico 10 dígitos (MRZ) → 9 para consulta', () {
    final doc = DocumentoPersona.parse('0038874570');
    expect(doc, isNotNull);
    expect(doc!.tipo, DocumentoPersonaTipo.cee);
    expect(doc.id, '003887457');
  });

  test('CEE 9 dígitos se mantiene', () {
    expect(DocumentoPersona.parse('003887457')?.id, '003887457');
  });
}
