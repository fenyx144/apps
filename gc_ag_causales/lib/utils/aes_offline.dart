import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Deriva la clave AES de 16 bytes desde [enom].
/// - Si enom < 16 bytes, rellena con \0 (0x00) a la derecha
/// - Si enom >= 16 bytes, trunca a los primeros 16 bytes
Uint8List _deriveKey(String enom) {
  final keyBytes = utf8.encode(enom);
  if (keyBytes.length >= 16) {
    return Uint8List.fromList(keyBytes.sublist(0, 16));
  }
  return Uint8List.fromList([
    ...keyBytes,
    ...List<int>.filled(16 - keyBytes.length, 0),
  ]);
}

/// Calcula el HEX de los primeros 8 bytes de AES-128-ECB(password, enom)
/// con padding PKCS7, replicando el comportamiento de MySQL AES_ENCRYPT.
/// Mismo resultado que MySQL:
/// HEX(LEFT(AES_ENCRYPT(password, enom), 8))
String computePasswordHex(String password, String enom) {
  final key = _deriveKey(enom);
  final plainBytes = utf8.encode(password);
  const blockSize = 16;

  final padValue = blockSize - (plainBytes.length % blockSize);
  final padded = Uint8List(plainBytes.length + padValue)
    ..setRange(0, plainBytes.length, plainBytes)
    ..fillRange(plainBytes.length, plainBytes.length + padValue, padValue);

  final cipher = ECBBlockCipher(AESEngine())
    ..init(true, KeyParameter(key));

  final encrypted = Uint8List(padded.length);
  for (int i = 0; i < padded.length; i += blockSize) {
    cipher.processBlock(padded, i, encrypted, i);
  }

  final first8 = encrypted.sublist(0, 8 > encrypted.length ? encrypted.length : 8);
  return first8
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}
