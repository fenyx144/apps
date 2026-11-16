import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../utils/constants.dart';

class StorageService with ChangeNotifier {
  final SharedPreferences _prefs;
  String? _lastDownloadDateCache;
  String? _lastSyncDateCache;

  static String normUsuario(String? raw) =>
      (raw ?? '').trim().toUpperCase();

  StorageService(this._prefs) {
    _lastDownloadDateCache =
        _prefs.getString(AppConstants.keyLastDownloadDate);
    _lastSyncDateCache = _prefs.getString(AppConstants.keyLastSyncDate);
  }

  Future<bool> isLoggedIn() async =>
      _prefs.getBool(AppConstants.keyIsLoggedIn) ?? false;

  bool get isLoggedInSync =>
      _prefs.getBool(AppConstants.keyIsLoggedIn) ?? false;

  String? getUserCodeSync() => _prefs.getString(AppConstants.keyUserCode);
  String? getUserName() => _prefs.getString(AppConstants.keyUserName);
  String? getDeviceId() => _prefs.getString(AppConstants.keyDeviceId);

  bool isDeviceAuthorized() =>
      _prefs.getBool(AppConstants.keyDeviceAuthorized) ?? false;

  Future<void> saveLoginSession({
    required String userCode,
    required String userName,
    required String deviceId,
  }) async {
    await _prefs.setBool(AppConstants.keyIsLoggedIn, true);
    await _prefs.setString(
      AppConstants.keyUserCode,
      normUsuario(userCode).isEmpty ? userCode.trim() : normUsuario(userCode),
    );
    await _prefs.setString(AppConstants.keyUserName, userName);
    await _prefs.setString(AppConstants.keyDeviceId, deviceId);
    await _prefs.setBool(AppConstants.keyDeviceAuthorized, true);
    notifyListeners();
  }

  Future<void> saveOfflineHash(String hash) async {
    await _prefs.setString(AppConstants.keyOfflineHash, hash);
  }

  String? getOfflineHash() => _prefs.getString(AppConstants.keyOfflineHash);

  Future<void> saveLoginEnom(String enom) async {
    await _prefs.setString(AppConstants.keyLoginEnom, enom);
  }

  String? getLoginEnom() => _prefs.getString(AppConstants.keyLoginEnom);

  bool getPuedeEnrolar() =>
      _prefs.getBool(AppConstants.keyPuedeEnrolar) ?? false;

  Future<void> savePuedeEnrolar(bool v) async {
    await _prefs.setBool(AppConstants.keyPuedeEnrolar, v);
    notifyListeners();
  }

  List<String> getPlantillasPendientes() =>
      _prefs.getStringList(AppConstants.keyPlantillasPendientes) ?? [];

  Future<void> addPlantillaPendiente(String dni) async {
    if (dni.isEmpty) return;
    final l = getPlantillasPendientes();
    if (!l.contains(dni)) l.add(dni);
    await _prefs.setStringList(AppConstants.keyPlantillasPendientes, l);
    notifyListeners();
  }

  Future<void> removePlantillaPendiente(String dni) async {
    final l = getPlantillasPendientes()..remove(dni);
    await _prefs.setStringList(AppConstants.keyPlantillasPendientes, l);
    notifyListeners();
  }

  Future<void> clearAll() async {
    await _prefs.clear();
    _lastDownloadDateCache = null;
    _lastSyncDateCache = null;
    notifyListeners();
  }

  Future<void> clearSession() async {
    await _prefs.setBool(AppConstants.keyIsLoggedIn, false);
    notifyListeners();
  }

  Future<void> saveCatalogos(Map<String, dynamic> catalogos) async {
    await _prefs.setString(
      AppConstants.keyCatalogos,
      jsonEncode(catalogos),
    );
    notifyListeners();
  }

  Map<String, dynamic> getCatalogos() {
    final raw = _prefs.getString(AppConstants.keyCatalogos);
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> saveAppInfo(Map<String, dynamic> info) async {
    await _prefs.setString(AppConstants.keyAppInfo, jsonEncode(info));
    notifyListeners();
  }

  Map<String, dynamic>? getAppInfo() {
    final raw = _prefs.getString(AppConstants.keyAppInfo);
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  String getNominaVersion() =>
      _prefs.getString(AppConstants.keyNominaVersion) ?? '';

  Future<void> saveNominaVersion(String version) async {
    await _prefs.setString(AppConstants.keyNominaVersion, version.trim());
    notifyListeners();
  }

  int getNominaTotal() => _prefs.getInt(AppConstants.keyNominaTotal) ?? 0;

  Future<void> saveNominaTotal(int total) async {
    await _prefs.setInt(AppConstants.keyNominaTotal, total);
    notifyListeners();
  }

  double getUmbral() =>
      _prefs.getDouble(AppConstants.keyUmbral) ??
      AppConstants.umbralDefecto;

  Future<void> saveUmbral(double umbral) async {
    await _prefs.setDouble(AppConstants.keyUmbral, umbral);
    notifyListeners();
  }

  double getMargen() =>
      _prefs.getDouble(AppConstants.keyMargen) ??
      AppConstants.margenDefecto;

  Future<void> saveMargen(double margen) async {
    await _prefs.setDouble(AppConstants.keyMargen, margen);
    notifyListeners();
  }

  bool getSonido() => _prefs.getBool(AppConstants.keySonido) ?? true;

  Future<void> saveSonido(bool value) async {
    await _prefs.setBool(AppConstants.keySonido, value);
    notifyListeners();
  }

  bool getVoz() => _prefs.getBool(AppConstants.keyVoz) ?? false;

  Future<void> saveVoz(bool value) async {
    await _prefs.setBool(AppConstants.keyVoz, value);
    notifyListeners();
  }

  bool getVibracion() =>
      _prefs.getBool(AppConstants.keyVibracion) ?? true;

  Future<void> saveVibracion(bool value) async {
    await _prefs.setBool(AppConstants.keyVibracion, value);
    notifyListeners();
  }

  List<Map<String, dynamic>> getEventos() {
    final list = _prefs.getStringList(AppConstants.keyEventos) ?? [];
    final eventos = <Map<String, dynamic>>[];
    for (final e in list) {
      try {
        eventos.add(Map<String, dynamic>.from(jsonDecode(e) as Map));
      } catch (_) {
        continue;
      }
    }
    return eventos;
  }

  Future<Map<String, dynamic>> addEvento(Map<String, dynamic> data) async {
    final eventos = getEventos();
    final copy = Map<String, dynamic>.from(data);
    final id = copy['uuid']?.toString().trim() ?? '';
    if (id.isEmpty) copy['uuid'] = const Uuid().v4();
    final created = copy['created_at']?.toString().trim() ?? '';
    if (created.isEmpty) {
      copy['created_at'] = DateTime.now().toIso8601String();
    }
    copy['synced'] = false;
    final u = normUsuario(copy['usuario']?.toString());
    final mi = normUsuario(getUserCodeSync());
    if (u.isNotEmpty) {
      copy['usuario'] = u;
    } else if (mi.isNotEmpty) {
      copy['usuario'] = mi;
    }
    eventos.add(copy);
    await _prefs.setStringList(
      AppConstants.keyEventos,
      eventos.map((r) => jsonEncode(r)).toList(),
    );
    notifyListeners();
    return copy;
  }

  Future<void> markEventoSynced(String uuid) async {
    if (uuid.isEmpty) return;
    final eventos = getEventos();
    for (var i = 0; i < eventos.length; i++) {
      if (eventos[i]['uuid']?.toString() == uuid) {
        eventos[i] = {...eventos[i], 'uuid': uuid, 'synced': true};
      }
    }
    await _prefs.setStringList(
      AppConstants.keyEventos,
      eventos.map((r) => jsonEncode(r)).toList(),
    );
    notifyListeners();
  }

  List<Map<String, dynamic>> eventosPendientes() {
    return getEventos()
        .where((r) => r['synced'] != true && r['synced'] != 'true')
        .toList();
  }

  int eventosPendientesCount() => eventosPendientes().length;

  List<Map<String, dynamic>> eventosDelDia(DateTime date) {
    final dia =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return getEventos()
        .where((r) => (r['fecha']?.toString() ?? '').startsWith(dia))
        .toList();
  }

  Future<int> pruneEventosSubidos({int dias = 7}) async {
    final limite = DateTime.now().subtract(Duration(days: dias));
    final eventos = getEventos();
    final antes = eventos.length;
    eventos.removeWhere((r) {
      if (r['synced'] != true && r['synced'] != 'true') return false;
      final creado = DateTime.tryParse(r['created_at']?.toString() ?? '');
      return creado != null && creado.isBefore(limite);
    });
    if (eventos.length != antes) {
      await _prefs.setStringList(
        AppConstants.keyEventos,
        eventos.map((r) => jsonEncode(r)).toList(),
      );
      notifyListeners();
    }
    return antes - eventos.length;
  }

  static String _formatSyncTimestamp(DateTime now) =>
      '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

  Future<void> setLastSyncDate() async {
    final s = _formatSyncTimestamp(DateTime.now());
    _lastSyncDateCache = s;
    notifyListeners();
    await _prefs.setString(AppConstants.keyLastSyncDate, s);
  }

  Future<String?> getLastSyncDate() async =>
      _prefs.getString(AppConstants.keyLastSyncDate);

  String get lastSyncDateDisplay {
    final p = _prefs.getString(AppConstants.keyLastSyncDate);
    if (p != null && p.isNotEmpty) return p;
    return _lastSyncDateCache ?? '--/--/--';
  }

  Future<void> setLastDownloadDate() async {
    final s = _formatSyncTimestamp(DateTime.now());
    _lastDownloadDateCache = s;
    notifyListeners();
    await _prefs.setString(AppConstants.keyLastDownloadDate, s);
  }

  Future<String?> getLastDownloadDate() async =>
      _prefs.getString(AppConstants.keyLastDownloadDate);

  String get lastDownloadDateDisplay {
    final p = _prefs.getString(AppConstants.keyLastDownloadDate);
    if (p != null && p.isNotEmpty) return p;
    return _lastDownloadDateCache ?? '--/--/--';
  }

  static DateTime? _parseSyncTimestamp(String? raw) {
    if (raw == null || raw.isEmpty || raw == '--/--/--') return null;
    try {
      final partes = raw.trim().split(RegExp(r'\s+'));
      final fecha = partes.first.split('/');
      if (fecha.length != 3) return null;
      var hora = 0;
      var minuto = 0;
      if (partes.length > 1) {
        final h = partes[1].split(':');
        if (h.length >= 2) {
          hora = int.parse(h[0]);
          minuto = int.parse(h[1]);
        }
      }
      return DateTime(
        int.parse(fecha[2]),
        int.parse(fecha[1]),
        int.parse(fecha[0]),
        hora,
        minuto,
      );
    } catch (_) {
      return null;
    }
  }

  DateTime? get lastDownloadDateTime =>
      _parseSyncTimestamp(lastDownloadDateDisplay);

  bool get needsNominaUpdate {
    final ultima = lastDownloadDateTime;
    if (ultima == null) return true;
    final dias = DateTime.now().difference(ultima).inDays;
    return dias >= AppConstants.staleNominaDays;
  }
}
