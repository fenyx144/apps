import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../utils/dialog_helper.dart';
import '../utils/record_id.dart';
import '../utils/toast_helper.dart';

/// Guardado común de los reportes de bioseguridad: siempre persiste en local y,
/// si hay conexión, intenta subir de inmediato (con manejo de 409 → actualizar).
class BioRecordSaver {
  /// Comprueba conexión al servidor (no basta con tener red local).
  static Future<bool> hasServerReachable() async {
    try {
      final r = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 4));
      return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Guarda [record] en el dispositivo y, si hay red, intenta enviarlo.
  ///
  /// Devuelve `true` si quedó sincronizado con el backend.
  static Future<bool> save(
    BuildContext context,
    Map<String, dynamic> record,
  ) async {
    final storage = context.read<StorageService>();
    await storage.saveRecord(record);
    record['synced'] = false;
    if (!await hasServerReachable()) return false;
    if (!context.mounted) return false;

    final close = showChickenLoadingDialog(context, 'Enviando registro…');
    var sincronizado = false;
    try {
      final result = await ApiService().uploadBioseguridad(
        record,
        timeout: const Duration(seconds: 45),
      );
      debugPrint(
        '[guardar_bioseguridad] respuesta: $result '
        '(id=${EvidenciaRecordId.of(record)})',
      );
      if (ApiService.subidaCompleta(result)) {
        await storage.markRecordAsSynced({
          ...record,
          'synced': true,
          'guardado_backend': true,
        });
        await storage.setLastSyncDate();
        record['synced'] = true;
        record['guardado_backend'] = true;
        sincronizado = true;
      } else if (context.mounted) {
        final msg = (result['message'] ?? '').toString().trim();
        showWarningToast(
          context,
          msg.isNotEmpty
              ? 'Guardado local. Servidor: $msg'
              : 'Guardado local. No se pudo confirmar en el servidor.',
        );
      }
    } catch (e) {
      if (context.mounted) {
        showWarningToast(
          context,
          'Guardado local. Error al enviar: $e',
        );
      }
    } finally {
      close();
    }
    return sincronizado;
  }
}
