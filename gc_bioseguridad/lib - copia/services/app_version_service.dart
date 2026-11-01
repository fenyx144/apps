import 'package:flutter/material.dart';

import '../utils/constants.dart';
import '../utils/dialog_utils.dart';
import '../utils/theme_colors.dart';
import 'storage_service.dart';

class AppVersionStatus {
  const AppVersionStatus({
    required this.allowed,
    required this.warning,
    required this.upToDate,
    this.needsUpdate = false,
    this.mustUpdate = false,
    this.message = '',
    this.requiredVersion = '',
    this.graceHasta = '',
    this.diasRestantes = 0,
  });

  /// Puede entrar y subir lo que tenga pendiente. Nunca se le corta el acceso
  /// para no dejar datos varados en el equipo.
  final bool allowed;
  final bool warning;
  final bool upToDate;
  final bool needsUpdate;

  /// Fuera de la ventana de gracia: no puede registrar. La subida de lo ya
  /// capturado sigue permitida; solo se le exige actualizar para capturar.
  final bool mustUpdate;
  final String message;
  final String requiredVersion;
  final String graceHasta;
  final int diasRestantes;

  static const ok = AppVersionStatus(
    allowed: true,
    warning: false,
    upToDate: true,
  );
}

class AppVersionService {
  static int compareVersions(String a, String b) {
    final pa = _parts(a);
    final pb = _parts(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  static List<int> _parts(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return [0];
    return s.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  }

  static bool _validYmd(String? raw) {
    final s = (raw ?? '').trim();
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s);
  }

  static String _ymd(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static String _formatDmy(String ymd) {
    final dt = DateTime.tryParse(ymd);
    if (dt == null) return ymd;
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final yy = (dt.year % 100).toString().padLeft(2, '0');
    return '$dd/$mm/$yy';
  }

  static String _graceHastaDesde(String avisoYmd, int graceDias) {
    final base = DateTime.tryParse(avisoYmd);
    if (base == null) return _ymd(DateTime.now());
    return _ymd(base.add(Duration(days: graceDias)));
  }

  static int graceDiasFrom(Map<String, dynamic>? cached) {
    if (cached?['grace_dias'] is int) {
      return cached!['grace_dias'] as int;
    }
    return AppConstants.appVersionGraceDays;
  }

  static AppVersionStatus evaluateLocal({
    required String clientVersion,
    Map<String, dynamic>? cached,
  }) {
    if (cached == null || cached.isEmpty) {
      return AppVersionStatus.ok;
    }

    if (cached['has_g_app'] == false) {
      return AppVersionStatus.ok;
    }

    final required = (cached['required_version'] ?? '').toString().trim();
    if (required.isEmpty) {
      return AppVersionStatus.ok;
    }

    // La version que trae el equipo sigue soportada en campo: nada que avisar,
    // aunque exista una mas nueva publicada.
    if (cached['version_activa'] == true) {
      return AppVersionStatus.ok;
    }

    if (compareVersions(clientVersion, required) >= 0) {
      return AppVersionStatus.ok;
    }

    // Su version quedo inactiva. La ventana se cuenta desde la publicacion de la
    // version activa (dato del servidor), no desde el primer aviso del equipo:
    // asi un equipo que estuvo apagado no puede estirar el plazo solo.
    final graceDias = graceDiasFrom(cached);
    final publicado = (cached['publicado_en'] ?? '').toString().trim();
    final hasta = _validYmd(publicado) ? _graceHastaDesde(publicado, graceDias) : '';
    final hoy = _ymd(DateTime.now());

    // Sin fecha de publicacion no hay plazo que vencer: se avisa y se trabaja.
    if (hasta.isEmpty) {
      return AppVersionStatus(
        allowed: true,
        warning: true,
        upToDate: false,
        needsUpdate: true,
        requiredVersion: required,
        message:
            'Hay una nueva versión ($required). Actualice la app lo antes '
            'posible. Si necesita ayuda, contacte a Administración o Sistemas.',
      );
    }

    final tsHoy = DateTime.tryParse(hoy);
    final tsHasta = DateTime.tryParse(hasta);
    var diasRest = 0;
    if (tsHoy != null && tsHasta != null) {
      diasRest = tsHasta.difference(tsHoy).inDays;
      if (diasRest < 0) diasRest = 0;
    }

    if (hoy.compareTo(hasta) <= 0) {
      return AppVersionStatus(
        allowed: true,
        warning: true,
        upToDate: false,
        needsUpdate: true,
        requiredVersion: required,
        graceHasta: hasta,
        diasRestantes: diasRest,
        message:
            'Hay una nueva versión ($required). Actualice la app antes del '
            '${_formatDmy(hasta)} '
            '(le quedan ${diasRest > 0 ? diasRest : 1} día(s); después de esa '
            'fecha no podrá registrar). '
            'Si necesita ayuda, contacte a Administración o Sistemas.',
      );
    }

    // Fuera de la ventana: entra y sube lo pendiente, pero no registra.
    return AppVersionStatus(
      allowed: true,
      warning: false,
      upToDate: false,
      needsUpdate: true,
      mustUpdate: true,
      requiredVersion: required,
      graceHasta: hasta,
      diasRestantes: 0,
      message:
          'Debe actualizar su app a la versión $required: el plazo venció el '
          '${_formatDmy(hasta)}. Puede seguir subiendo los registros que ya '
          'tiene, pero no registrar nuevos. '
          'Comuníquese con Administración o Sistemas.',
    );
  }

  static AppVersionStatus fromStorage(StorageService storage) {
    return evaluateLocal(
      clientVersion: AppConstants.appVersion,
      cached: storage.getAppInfo(),
    );
  }

  static String? warningDesdeForApi(StorageService storage) {
    final info = storage.getAppInfo();
    if (info == null) return null;
    final desde = (info['version_warning_desde'] ?? '').toString().trim();
    return _validYmd(desde) ? desde : null;
  }

  static Future<void> mergeServerPayload(
    StorageService storage,
    Map<String, dynamic> payload,
  ) async {
    final prev = storage.getAppInfo();
    final merged = Map<String, dynamic>.from(payload);
    merged['has_g_app'] = payload['has_g_app'] == true;

    if (prev != null) {
      for (final k in ['tmejorauser', 'tmejoradev', 'tdescripcion']) {
        if ((merged[k] ?? '').toString().trim().isEmpty &&
            (prev[k] ?? '').toString().trim().isNotEmpty) {
          merged[k] = prev[k];
        }
      }
    }

    await storage.saveAppInfo(merged);
  }

  /// Muestra el aviso de version. Nunca bloquea la entrada ni la subida de lo
  /// pendiente: el corte real ocurre al intentar registrar un dato nuevo.
  static Future<void> notifyIfNeeded(
    BuildContext context,
    StorageService storage, {
    bool barrierDismissible = true,
  }) async {
    final status = fromStorage(storage);
    if (!status.warning && !status.mustUpdate) return;
    if (!context.mounted) return;

    final hoy = _ymd(DateTime.now());
    final info = storage.getAppInfo() ?? const <String, dynamic>{};
    final repetido = (info['version_notice_last'] ?? '').toString() == hoy &&
        (info['version_notice_for'] ?? '').toString() == status.requiredVersion;

    // Dentro de la ventana basta con avisar una vez al día por versión pedida;
    // fuera de ella el aviso es firme y se repite en cada ingreso.
    if (status.warning && !status.mustUpdate && repetido) return;

    await showStatusDialog(
      context,
      status,
      barrierDismissible: barrierDismissible && !status.mustUpdate,
    );

    if (!status.mustUpdate) {
      final updated = Map<String, dynamic>.from(info);
      updated['version_notice_last'] = hoy;
      updated['version_notice_for'] = status.requiredVersion;
      await storage.saveAppInfo(updated);
    }
  }

  static Future<void> showStatusDialog(
    BuildContext context,
    AppVersionStatus status, {
    bool barrierDismissible = true,
  }) async {
    if (status.upToDate || status.message.trim().isEmpty) return;
    await showAppDialog<void>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => AlertDialog(
        title: Text(
          status.mustUpdate
              ? 'Actualización requerida'
              : 'Actualización disponible',
          style: TextStyle(color: ctx.textThemePrimary),
        ),
        content: Text(
          status.message,
          style: TextStyle(color: ctx.textThemeMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(status.mustUpdate ? 'Entendido' : 'Continuar'),
          ),
        ],
      ),
    );
  }

  static List<String> parseMejorasUsuario(Map<String, dynamic>? cached) {
    final raw = (cached?['tmejorauser'] ?? '').toString().trim();
    if (raw.isEmpty) return [];
    return raw
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .map((line) => line.replaceFirst(RegExp(r'^[-•*]\s*'), '').trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  static Map<String, dynamic>? extractPayload(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    if (map['version_check'] is Map) {
      return Map<String, dynamic>.from(map['version_check'] as Map);
    }
    if ((map['required_version'] ?? '').toString().isNotEmpty) {
      return map;
    }
    return null;
  }
}
