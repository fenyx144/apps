import 'dart:async';

import 'api_service.dart';
import 'storage_service.dart';

/// Envía al servidor los borrados pendientes (cola offline). No lanza.
class BorradosSync {
  static bool _enCurso = false;

  /// Devuelve cuántos quedan pendientes.
  static Future<int> enviar(StorageService storage) async {
    final cola = storage.getBorradosPendientes();
    if (cola.isEmpty || _enCurso) return cola.length;
    _enCurso = true;
    try {
      for (var i = 0; i < cola.length; i += 50) {
        final lote = cola.sublist(i, i + 50 > cola.length ? cola.length : i + 50);
        final res = await ApiService()
            .borrarMarcaciones(lote)
            .timeout(const Duration(seconds: 15));
        final data = res['data'];
        final resultados = data is Map ? data['resultados'] : null;
        if (resultados is! List) break;
        final ok = <String>{
          for (final it in resultados)
            if (it is Map && it['ok'] == true) '${it['id']}',
        };
        await storage.quitarBorradosPorId(ok);
      }
    } catch (_) {
    } finally {
      _enCurso = false;
    }
    return storage.getBorradosPendientes().length;
  }
}