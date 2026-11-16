import 'dart:async';

import 'package:flutter/foundation.dart';

import '../utils/constants.dart';
import 'nomina_store.dart';
import 'nomina_sync_service.dart';
import 'storage_service.dart';

class SyncScheduler {
  static Timer? _timer;
  static bool _enCurso = false;

  static void start({
    required StorageService storage,
    required NominaStore store,
  }) {
    stop();
    _timer = Timer.periodic(
      const Duration(minutes: AppConstants.syncIntervalMinutes),
      (_) => syncOnce(storage: storage, store: store),
    );
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  static Future<void> syncOnce({
    required StorageService storage,
    required NominaStore store,
    ValueChanged<NominaSyncResult>? onResult,
  }) async {
    if (_enCurso) return;
    _enCurso = true;
    try {
      final r = await NominaSyncService().syncAll(
        storage: storage,
        store: store,
      );
      onResult?.call(r);
    } catch (e) {
      onResult?.call(
        NominaSyncResult(hadInternet: true, errorMessage: e.toString()),
      );
    } finally {
      _enCurso = false;
    }
  }
}
