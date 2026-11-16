import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

const int _block = 16;

Uint8List faceEncryptBytes(Uint8List plain, Uint8List key) {
  final iv = Uint8List(_block);
  final rnd = Random.secure();
  for (var i = 0; i < iv.length; i++) {
    iv[i] = rnd.nextInt(256);
  }
  final padValue = _block - (plain.length % _block);
  final padded = Uint8List(plain.length + padValue)
    ..setRange(0, plain.length, plain)
    ..fillRange(plain.length, plain.length + padValue, padValue);
  final cipher = CBCBlockCipher(AESEngine())
    ..init(true, ParametersWithIV(KeyParameter(key), iv));
  final encrypted = Uint8List(padded.length);
  for (var i = 0; i < padded.length; i += _block) {
    cipher.processBlock(padded, i, encrypted, i);
  }
  return Uint8List(16 + encrypted.length)
    ..setRange(0, 16, iv)
    ..setRange(16, 16 + encrypted.length, encrypted);
}

Uint8List faceDecryptBytes(Uint8List packed, Uint8List key) {
  if (packed.length < 32 || packed.length % _block != 0) {
    throw const FormatException('paquete inválido');
  }
  final iv = packed.sublist(0, 16);
  final data = packed.sublist(16);
  final cipher = CBCBlockCipher(AESEngine())
    ..init(false, ParametersWithIV(KeyParameter(key), iv));
  final padded = Uint8List(data.length);
  for (var i = 0; i < data.length; i += _block) {
    cipher.processBlock(data, i, padded, i);
  }
  final padValue = padded.last;
  if (padValue < 1 || padValue > _block || padded.length < padValue) {
    throw const FormatException('relleno inválido');
  }
  for (var i = padded.length - padValue; i < padded.length; i++) {
    if (padded[i] != padValue) {
      throw const FormatException('relleno inválido');
    }
  }
  return padded.sublist(0, padded.length - padValue);
}
