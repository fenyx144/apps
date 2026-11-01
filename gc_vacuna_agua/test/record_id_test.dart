import 'package:flutter_test/flutter_test.dart';
import 'package:vacuna_al_agua/utils/record_id.dart';

void main() {
  group('EvidenciaRecordId.isUuidV4', () {
    test('acepta un uuid v4 en minúsculas', () {
      expect(
        EvidenciaRecordId.isUuidV4('a1b2c3d4-e5f6-4123-8901-abcdef012345'),
        isTrue,
      );
    });

    test('rechaza vacío o formato inválido', () {
      expect(EvidenciaRecordId.isUuidV4(''), isFalse);
      expect(EvidenciaRecordId.isUuidV4('not-a-uuid'), isFalse);
      expect(
        EvidenciaRecordId.isUuidV4('a1b2c3d4-e5f6-4123-8901-abcdef012345'.toUpperCase()),
        isTrue,
      );
    });
  });
}
