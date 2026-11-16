import 'dart:convert';

import '../utils/constants.dart';
import '../utils/face_constants.dart';
import 'api_service.dart';
import 'face_engine.dart';
import 'nomina_store.dart';
import 'storage_service.dart';

/// Persona que puede llegar a la granja. La foto, si existe, es la de su alta
/// (`bio_personal.foto_ruta` o la del proveedor). No se crea otra foto.
class PersonaReferencia {
  const PersonaReferencia({
    required this.dni,
    required this.nombre,
    required this.tieneFoto,
  });

  final String dni;
  final String nombre;
  final bool tieneFoto;

  Map<String, dynamic> toJson() => {
        'dni': dni,
        'nombre': nombre,
        'tiene_foto': tieneFoto,
      };

  static PersonaReferencia? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final dni = (raw['dni'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^\d{6,15}$').hasMatch(dni)) return null;
    final nombre = (raw['nombre'] ?? '').toString().trim();
    final foto = raw['tiene_foto'] == true ||
        raw['tiene_foto'] == 1 ||
        (raw['foto_ruta'] ?? '').toString().trim().isNotEmpty;
    return PersonaReferencia(
      dni: dni,
      nombre: nombre.isEmpty ? dni : nombre,
      tieneFoto: foto,
    );
  }
}

class NominaFacialSync {
  NominaFacialSync({ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;

  static String clavePara(StorageService storage) {
    final enom = (storage.getLoginEnom() ?? '').trim();
    return enom.isEmpty ? AppConstants.offlineSalt : enom;
  }

  List<PersonaReferencia> locales(StorageService storage) {
    final raw = storage.getPersonalReferenciaJson();
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final e in decoded)
          if (PersonaReferencia.fromJson(e) != null)
            PersonaReferencia.fromJson(e)!,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Lista unificada para uso offline. No exige foto.
  Future<bool> descargarLista(StorageService storage) async {
    final res = await _api.downloadPersonalReferencia();
    if (res['success'] != true || res['data'] is! Map) return false;
    final data = Map<String, dynamic>.from(res['data'] as Map);
    final raw = data['personas'];
    if (raw is! List) return false;
    final personas = [
      for (final e in raw)
        if (PersonaReferencia.fromJson(e) != null) PersonaReferencia.fromJson(e)!,
    ];
    await storage.savePersonalReferenciaJson(
      jsonEncode([for (final p in personas) p.toJson()]),
    );
    return true;
  }

  /// Vector de la foto ya registrada. Null si no hay foto utilizable.
  Future<bool> prepararRostro({
    required StorageService storage,
    required NominaStore store,
    required FaceEngine engine,
    required PersonaReferencia persona,
  }) async {
    if (!persona.tieneFoto) return false;
    final clave = clavePara(storage);
    await store.load(clave: clave);
    final previa = store.find(persona.dni);
    if (previa != null && previa.vector.length == 512) return true;
    final bytes = await _api.downloadFotoPersonal(persona.dni);
    if (bytes == null) return false;
    final vector = await engine.vectorDeFoto(bytes);
    if (vector == null) return false;
    await store.applyDelta(
      altas: [
        {
          'dni': persona.dni,
          'nombre': persona.nombre,
          'plantilla': {
            'modelo': FaceConstants.faceModel,
            'vector': vector.toList(),
            'miniatura': '',
            'updated_at': persona.dni,
          },
        },
      ],
      bajas: const [],
      clave: clave,
    );
    return true;
  }
}
