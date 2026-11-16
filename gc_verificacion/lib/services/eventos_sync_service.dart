import 'dart:async';

import 'api_service.dart';
import 'storage_service.dart';

class EventosSyncResult {
  const EventosSyncResult({
    required this.hadInternet,
    this.subidos = 0,
    this.fallidos = 0,
    this.errorMessage,
  });

  final bool hadInternet;
  final int subidos;
  final int fallidos;
  final String? errorMessage;
}

class EventosSyncService {
  static bool _enCurso = false;

  static Future<EventosSyncResult> enviar(
    StorageService storage, {
    ApiService? api,
  }) async {
    final pendientes = storage.eventosPendientes();
    if (pendientes.isEmpty) {
      return const EventosSyncResult(hadInternet: true);
    }
    if (_enCurso) {
      return const EventosSyncResult(
        hadInternet: true,
        errorMessage: 'Sincronización en curso',
      );
    }
    _enCurso = true;
    try {
      final svc = api ?? ApiService();
      var ok = 0;
      var fail = 0;
      String? error;
      for (var i = 0; i < pendientes.length; i += 50) {
        final fin =
            i + 50 > pendientes.length ? pendientes.length : i + 50;
        final lote = pendientes.sublist(i, fin);
        Map<String, dynamic> res;
        try {
          res = await svc
              .uploadEventos(lote)
              .timeout(const Duration(seconds: 45));
        } catch (_) {
          fail += lote.length;
          error = 'Error de conexión';
          break;
        }
        final data = res['data'];
        final resultados = data is Map ? data['resultados'] : null;
        if (resultados is! List) {
          if (res['success'] == true) {
            for (final r in lote) {
              await storage.markEventoSynced(r['uuid']?.toString() ?? '');
              ok++;
            }
          } else {
            fail += lote.length;
            error = res['message']?.toString();
          }
          continue;
        }
        final porId = <String, bool>{};
        for (final item in resultados) {
          if (item is! Map) continue;
          final id = item['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          porId[id] = item['ok'] == true;
        }
        for (final r in lote) {
          final id = r['uuid']?.toString() ?? '';
          if (porId[id] == true) {
            await storage.markEventoSynced(id);
            ok++;
          } else {
            fail++;
          }
        }
        if (res['success'] != true && porId.isEmpty) {
          error = res['message']?.toString();
        }
      }
      if (ok > 0) {
        await storage.setLastSyncDate();
        await storage.pruneEventosSubidos();
      }
      return EventosSyncResult(
        hadInternet: true,
        subidos: ok,
        fallidos: fail,
        errorMessage: fail > 0 ? error : null,
      );
    } finally {
      _enCurso = false;
    }
  }
}
