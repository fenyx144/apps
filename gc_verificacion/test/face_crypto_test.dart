import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gc_verificacion/utils/aes_offline.dart';
import 'package:gc_verificacion/utils/face_crypto.dart';

void main() {
  group('face crypto', () {
    test('cifra y descifra', () {
      final key = deriveOfflineKey('enom-prueba');
      final plain = Uint8List.fromList(
        List.generate(100, (i) => i % 256),
      );
      final packed = faceEncryptBytes(plain, key);
      expect(packed.length % 16, 0);
      expect(faceDecryptBytes(packed, key), plain);
    });

    test('iv distinto en cada cifrado', () {
      final key = deriveOfflineKey('enom-prueba');
      final plain = Uint8List.fromList([1, 2, 3]);
      final a = faceEncryptBytes(plain, key);
      final b = faceEncryptBytes(plain, key);
      expect(a.sublist(0, 16), isNot(equals(b.sublist(0, 16))));
      expect(faceDecryptBytes(a, key), plain);
      expect(faceDecryptBytes(b, key), plain);
    });

    test('clave incorrecta no recupera el original', () {
      final plain = Uint8List.fromList([9, 9, 9]);
      final packed =
          faceEncryptBytes(plain, deriveOfflineKey('uno'));
      var recupera = false;
      try {
        final dec = faceDecryptBytes(packed, deriveOfflineKey('dos'));
        recupera = dec.length == 3 && dec[0] == 9 && dec[1] == 9;
      } catch (_) {
        recupera = false;
      }
      expect(recupera, false);
    });

    test('paquete corto se rechaza', () {
      expect(
        () => faceDecryptBytes(
          Uint8List.fromList([1, 2, 3]),
          deriveOfflineKey('uno'),
        ),
        throwsFormatException,
      );
    });
  });
}
