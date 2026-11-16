import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

Uint8List deriveOfflineKey(String material) {
  final keyBytes = utf8.encode(material);
  if (keyBytes.length >= 16) {
    return Uint8List.fromList(keyBytes.sublist(0, 16));
  }
  return Uint8List.fromList([
    ...keyBytes,
    ...List<int>.filled(16 - keyBytes.length, 0),
  ]);
}

Uint8List _deriveKey(String enom) => deriveOfflineKey(enom);

String computePasswordHex(String password, String enom) {
  final key = _deriveKey(enom);
  final plainBytes = utf8.encode(password);
  const blockSize = 16;

  final padValue = blockSize - (plainBytes.length % blockSize);
  final padded = Uint8List(plainBytes.length + padValue)
    ..setRange(0, plainBytes.length, plainBytes)
    ..fillRange(plainBytes.length, plainBytes.length + padValue, padValue);

  final cipher = ECBBlockCipher(AESEngine())..init(true, KeyParameter(key));

  final encrypted = Uint8List(padded.length);
  for (int i = 0; i < padded.length; i += blockSize) {
    cipher.processBlock(padded, i, encrypted, i);
  }

  final first8 =
      encrypted.sublist(0, 8 > encrypted.length ? encrypted.length : 8);
  return first8
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}
