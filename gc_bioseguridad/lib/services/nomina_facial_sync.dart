import '../utils/constants.dart';
import '../utils/face_constants.dart';
import 'bio_empresa_api.dart';
import 'face_engine.dart';
import 'nomina_store.dart';
import 'storage_service.dart';

/// Arma la nómina de comparación a partir de la foto que el proveedor ya
/// cargó en el alta de personal (`bio_personal.foto_ruta`).
/// No crea ni sube un registro de fotos propio.
class NominaFacialSync {
  NominaFacialSync({BioEmpresaApi? api}) : _api = api ?? BioEmpresaApi();

  final BioEmpresaApi _api;

  static String clavePara(StorageService storage) {
    final enom = (storage.getLoginEnom() ?? '').trim();
    return enom.isEmpty ? AppConstants.offlineSalt : enom;
  }

  Future<bool> sync({
    required StorageService storage,
    required NominaStore store,
    required FaceEngine engine,
  }) async {
    final clave = clavePara(storage);
    await store.load(clave: clave);
    List<Map<String, dynamic>> personas;
    try {
      personas = await _api.listarPersonalActivo();
    } catch (_) {
      return store.total > 0;
    }
    if (personas.isEmpty) return store.total > 0;

    final altas = <Map<String, dynamic>>[];
    for (final p in personas) {
      final dni = (p['dni'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      if (!RegExp(r'^\d{8,15}$').hasMatch(dni)) continue;
      final nombre = [
        (p['nombres'] ?? '').toString().trim(),
        (p['apellidos'] ?? '').toString().trim(),
      ].where((s) => s.isNotEmpty).join(' ');
      if (nombre.isEmpty) continue;
      final foto = (p['foto_ruta'] ?? '').toString().trim();
      if (foto.isEmpty) continue;

      final previa = store.find(dni);
      if (previa != null &&
          previa.updatedAt == foto &&
          previa.vector.length == 512) {
        altas.add(_fila(previa));
        continue;
      }

      final bytes = await _api.descargarArchivo(foto);
      if (bytes == null) {
        if (previa != null) altas.add(_fila(previa));
        continue;
      }
      try {
        final vector = await engine.vectorDeFoto(bytes);
        if (vector == null) {
          if (previa != null) altas.add(_fila(previa));
          continue;
        }
        altas.add({
          'dni': dni,
          'nombre': nombre,
          'plantilla': {
            'modelo': FaceConstants.faceModel,
            'vector': vector.toList(),
            'miniatura': '',
            'updated_at': foto,
          },
        });
      } catch (_) {
        if (previa != null) altas.add(_fila(previa));
      }
    }
    if (altas.isEmpty) return store.total > 0;
    await store.applyFull(altas, clave: clave);
    return store.total > 0;
  }

  Map<String, dynamic> _fila(PersonaFace p) => {
        'dni': p.dni,
        'nombre': p.nombre,
        'plantilla': {
          'modelo': FaceConstants.faceModel,
          'vector': p.vector.toList(),
          'miniatura': '',
          'updated_at': p.updatedAt,
        },
      };
}
