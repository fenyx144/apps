import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/face_constants.dart';
import '../utils/face_crypto.dart';

class PersonaFace {
  const PersonaFace({
    required this.dni,
    required this.nombre,
    required this.vector,
    this.miniatura = '',
    this.updatedAt = '',
  });

  final String dni;
  final String nombre;
  final Float32List vector;
  final String miniatura;
  final String updatedAt;
}

class NominaStore with ChangeNotifier {
  final _personas = <String, PersonaFace>{};
  bool _cargado = false;
  bool _integro = false;

  bool get cargado => _cargado;
  bool get integro => _integro;
  int get total => _personas.length;
  List<PersonaFace> get personas => List.unmodifiable(_personas.values);
  PersonaFace? find(String dni) => _personas[dni];

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/nomina.enc');
  }

  Uint8List _key(String clave) {
    final keyBytes = utf8.encode(clave);
    if (keyBytes.length >= 16) {
      return Uint8List.fromList(keyBytes.sublist(0, 16));
    }
    return Uint8List.fromList([
      ...keyBytes,
      ...List<int>.filled(16 - keyBytes.length, 0),
    ]);
  }

  Future<void> load({required String clave}) async {
    try {
      final f = await _file();
      if (!await f.exists()) {
        _personas.clear();
        _cargado = true;
        _integro = true;
        notifyListeners();
        return;
      }
      final packed = await f.readAsBytes();
      final plain = faceDecryptBytes(packed, _key(clave));
      final decoded = jsonDecode(utf8.decode(plain));
      final list = decoded is Map ? decoded['personas'] : null;
      _personas.clear();
      if (list is List) {
        for (final e in list) {
          final p = _parseGuardada(e);
          if (p != null) _personas[p.dni] = p;
        }
      }
      _cargado = true;
      _integro = true;
      notifyListeners();
    } catch (_) {
      _personas.clear();
      _cargado = true;
      _integro = false;
      notifyListeners();
    }
  }

  PersonaFace? _parseGuardada(dynamic e) {
    if (e is! Map) return null;
    final dni = (e['dni']?.toString() ?? '').trim();
    if (!RegExp(r'^\d{8,15}$').hasMatch(dni)) return null;
    final nombre = (e['nombre']?.toString() ?? '').trim();
    if (nombre.isEmpty) return null;
    final vector = _parseVector(e['vector']);
    if (vector == null) return null;
    return PersonaFace(
      dni: dni,
      nombre: nombre,
      vector: vector,
      miniatura: e['miniatura']?.toString() ?? '',
      updatedAt: e['updated_at']?.toString() ?? '',
    );
  }

  PersonaFace? _parseAlta(dynamic e) {
    if (e is! Map) return null;
    final dni = (e['dni']?.toString() ?? '').trim();
    if (!RegExp(r'^\d{8,15}$').hasMatch(dni)) return null;
    final nombre = (e['nombre']?.toString() ?? '').trim();
    if (nombre.isEmpty) return null;
    final plantilla = e['plantilla'];
    if (plantilla is! Map) return null;
    if ((plantilla['modelo']?.toString() ?? '') != FaceConstants.faceModel) {
      return null;
    }
    final vector = _parseVector(plantilla['vector']);
    if (vector == null) return null;
    return PersonaFace(
      dni: dni,
      nombre: nombre,
      vector: vector,
      miniatura: plantilla['miniatura']?.toString() ?? '',
      updatedAt: plantilla['updated_at']?.toString() ?? '',
    );
  }

  Float32List? _parseVector(dynamic raw) {
    if (raw is! List || raw.length != 512) return null;
    final out = Float32List(512);
    for (var i = 0; i < 512; i++) {
      final v = raw[i];
      if (v is! num || !v.isFinite) return null;
      out[i] = v.toDouble();
    }
    return out;
  }

  Future<void> _persist(String clave) async {
    final data = {
      'personas': [
        for (final p in _personas.values)
          {
            'dni': p.dni,
            'nombre': p.nombre,
            'vector': p.vector.toList(),
            'miniatura': p.miniatura,
            'updated_at': p.updatedAt,
          },
      ],
    };
    final plain = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    final packed = faceEncryptBytes(plain, _key(clave));
    await (await _file()).writeAsBytes(packed, flush: true);
  }

  Future<({int altas, int omitidos})> applyFull(
    List altas, {
    required String clave,
  }) async {
    _personas.clear();
    var omitidos = 0;
    for (final e in altas) {
      final p = _parseAlta(e);
      if (p == null) {
        omitidos++;
        continue;
      }
      _personas[p.dni] = p;
    }
    _integro = true;
    _cargado = true;
    await _persist(clave);
    notifyListeners();
    return (altas: _personas.length, omitidos: omitidos);
  }

  Future<({int altas, int bajas, int omitidos})> applyDelta({
    required List altas,
    required List bajas,
    required String clave,
  }) async {
    if (!_integro) {
      throw StateError('nomina no integra');
    }
    var aplicadas = 0;
    var omitidos = 0;
    for (final e in altas) {
      final p = _parseAlta(e);
      if (p == null) {
        omitidos++;
        continue;
      }
      _personas[p.dni] = p;
      aplicadas++;
    }
    var eliminadas = 0;
    for (final b in bajas) {
      final dni = b?.toString() ?? '';
      if (dni.isEmpty) continue;
      if (_personas.remove(dni) != null) eliminadas++;
    }
    await _persist(clave);
    notifyListeners();
    return (altas: aplicadas, bajas: eliminadas, omitidos: omitidos);
  }

  Future<void> upsert(PersonaFace persona, {required String clave}) async {
    _personas[persona.dni] = persona;
    await _persist(clave);
    notifyListeners();
  }

  Future<bool> remove(String dni, {required String clave}) async {
    if (_personas.remove(dni) == null) return false;
    await _persist(clave);
    notifyListeners();
    return true;
  }
}
