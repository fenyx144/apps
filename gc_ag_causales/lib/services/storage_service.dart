import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import '../utils/galpones_resolver.dart';
import '../utils/record_id.dart';

class StorageService with ChangeNotifier {
  final SharedPreferences _prefs;
  StorageService(this._prefs);

  Future<bool> isLoggedIn() async =>
      _prefs.getBool(AppConstants.keyIsLoggedIn) ?? false;

  String? getUserCodeSync() => _prefs.getString(AppConstants.keyUserCode);
  String? getUserName() => _prefs.getString(AppConstants.keyUserName);

  Future<void> saveLoginSession({
    required String userCode,
    required String userName,
    required String deviceId,
  }) async {
    await _prefs.setBool(AppConstants.keyIsLoggedIn, true);
    await _prefs.setString(AppConstants.keyUserCode, userCode);
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

  Future<void> clearAll() async {
    await _prefs.clear();
    notifyListeners();
  }

  Future<void> saveRecord(Map<String, dynamic> data) async {
    final tabla = AppStrings.recordsTable;
    final list = _prefs.getStringList(tabla) ?? [];
    final records = list
        .map((e) => Map<String, dynamic>.from(jsonDecode(e) as Map))
        .toList();
    records.add(EvidenciaRecordId.normalize(Map<String, dynamic>.from(data)));
    await _prefs.setStringList(
      tabla,
      records.map((r) => jsonEncode(r)).toList(),
    );
    notifyListeners();
  }

  Future<void> updateRecord(Map<String, dynamic> target) async {
    final tabla = AppStrings.recordsTable;
    final records = getAllRecords();
    final recordId = EvidenciaRecordId.of(target);
    if (recordId.isEmpty) return;

    for (var i = 0; i < records.length; i++) {
      if (EvidenciaRecordId.of(records[i]) == recordId) {
        records[i] = EvidenciaRecordId.normalize({...records[i], ...target});
        break;
      }
    }
    await _prefs.setStringList(
      tabla,
      records.map((r) => jsonEncode(r)).toList(),
    );
    notifyListeners();
  }

  List<Map<String, dynamic>> getAllRecords() {
    final list = _prefs.getStringList(AppStrings.recordsTable);
    if (list == null) return [];

    var needsPersist = false;
    final records = list.map((e) {
      final raw = Map<String, dynamic>.from(jsonDecode(e) as Map);
      if (EvidenciaRecordId.hadLegacyFields(raw)) {
        needsPersist = true;
      }
      return EvidenciaRecordId.normalize(raw);
    }).toList();

    if (needsPersist) {
      _prefs.setStringList(
        AppStrings.recordsTable,
        records.map((r) => jsonEncode(r)).toList(),
      );
    }

    return records;
  }

  List<Map<String, dynamic>> getRecordsPendientes() {
    return getAllRecords()
        .where((r) => r['synced'] != true && r['synced'] != 'true')
        .toList();
  }

  int getPendingCount() => getRecordsPendientes().length;

  List<Map<String, dynamic>> getRecordsByDate(DateTime date) {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return getAllRecords()
        .where((r) => (r['fecha']?.toString() ?? '').startsWith(dateStr))
        .toList();
  }

  Future<void> markRecordAsSynced(Map<String, dynamic> target) async {
    final recordId = EvidenciaRecordId.of(target);
    if (recordId.isEmpty) return;

    final records = getAllRecords();
    for (var i = 0; i < records.length; i++) {
      if (EvidenciaRecordId.of(records[i]) == recordId) {
        records[i] = EvidenciaRecordId.normalize({
          ...records[i],
          'id': recordId,
          'synced': true,
          'guardado_backend': target['guardado_backend'] ?? true,
        });
        break;
      }
    }
    await _prefs.setStringList(
      AppStrings.recordsTable,
      records.map((r) => jsonEncode(r)).toList(),
    );
    notifyListeners();
  }

  Future<void> setLastSyncDate() async {
    final now = DateTime.now();
    final s =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour}:${now.minute}';
    await _prefs.setString('last_sync_date', s);
    notifyListeners();
  }

  Future<String?> getLastSyncDate() async => _prefs.getString('last_sync_date');

  String? get lastSyncDateSync => _prefs.getString('last_sync_date');

  Future<void> setLastDownloadDate() async {
    final now = DateTime.now();
    final s =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour}:${now.minute}';
    await _prefs.setString('last_download_date', s);
    notifyListeners();
  }

  Future<String?> getLastDownloadDate() async =>
      _prefs.getString('last_download_date');

  String? get lastDownloadDateSync => _prefs.getString('last_download_date');

  DateTime? get lastDownloadDateTime {
    final s = lastDownloadDateSync;
    if (s == null || s.isEmpty || s == '--/--/--') return null;
    try {
      final parts = s.split(' ');
      final dateParts = parts.first.split('/');
      if (dateParts.length != 3) return null;
      final day = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final year = int.parse(dateParts[2]);
      var hour = 0;
      var minute = 0;
      if (parts.length > 1) {
        final timeParts = parts[1].split(':');
        if (timeParts.length >= 2) {
          hour = int.parse(timeParts[0]);
          minute = int.parse(timeParts[1]);
        }
      }
      return DateTime(year, month, day, hour, minute);
    } catch (_) {
      return null;
    }
  }

  /// true si nunca descargó o lleva [AppConstants.staleCatalogDays] días sin actualizar.
  bool get needsCatalogUpdate {
    final last = lastDownloadDateTime;
    if (last == null) return true;
    final days = DateTime.now().difference(last).inDays;
    return days >= AppConstants.staleCatalogDays;
  }

  Future<void> saveCencosGalpones(Map<String, dynamic> data) async {
    final indices = GalponesResolver.buildIndicesFromApiData(data);
    await saveCencosGalponesIndexed(indices);
  }

  Future<void> saveCencosGalponesIndexed(GalponesCatalogIndices indices) async {
    await _prefs.setString(
      AppConstants.keyCencosGalpones,
      jsonEncode({
        'cencos': indices.cencos,
        'total': indices.cencos.length,
      }),
    );
    await _prefs.setString(
      AppConstants.keyCencosLista,
      jsonEncode(indices.cencos),
    );
    await _prefs.setString(
      AppConstants.keyGalponesPorCenco,
      jsonEncode(indices.galponesPorCenco),
    );
    await _prefs.setString(
      AppConstants.keyGalponesPorGranja,
      jsonEncode(indices.galponesPorGranja),
    );
    debugPrint(
      'StorageService: CENCOS=${indices.cencos.length}, '
      'granjas con galpones=${indices.galponesPorGranja.length}, '
      'total galpones=${indices.totalGalpones}',
    );
    notifyListeners();
  }

  Map<String, dynamic>? getCencosGalpones() {
    _ensureGalponesIndicesMigrated();
    final s = _prefs.getString(AppConstants.keyCencosGalpones);
    if (s == null) return null;
    return Map<String, dynamic>.from(jsonDecode(s) as Map);
  }

  bool hasCencosGalponesLocal() {
    _ensureGalponesIndicesMigrated();
    final porGranja = _prefs.getString(AppConstants.keyGalponesPorGranja);
    if (porGranja != null && porGranja.isNotEmpty) {
      final decoded = jsonDecode(porGranja) as Map;
      if (decoded.isNotEmpty) return true;
    }
    final legacy = _prefs.getString(AppConstants.keyCencosGalpones);
    return legacy != null && legacy.isNotEmpty;
  }

  List<Map<String, dynamic>> getCencosListaLocal() {
    _ensureGalponesIndicesMigrated();
    final s = _prefs.getString(AppConstants.keyCencosLista);
    if (s != null && s.isNotEmpty) {
      return _decodeCencosList(s);
    }
    final legacy = getCencosGalpones();
    if (legacy == null) return [];
    return ((legacy['cencos'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Map<String, List<Map<String, dynamic>>> getGalponesPorCencoLocal() {
    _ensureGalponesIndicesMigrated();
    final s = _prefs.getString(AppConstants.keyGalponesPorCenco);
    if (s == null || s.isEmpty) return {};
    return _decodeGalponesMap(s);
  }

  Map<String, List<Map<String, dynamic>>> getGalponesPorGranjaMapLocal() {
    _ensureGalponesIndicesMigrated();
    final s = _prefs.getString(AppConstants.keyGalponesPorGranja);
    if (s == null || s.isEmpty) return {};
    return _decodeGalponesMap(s);
  }

  List<Map<String, dynamic>> getGalponesForGranja(String granja3) {
    final g3 = GalponesResolver.normGranja(granja3);
    if (g3.isEmpty) return [];
    return List<Map<String, dynamic>>.from(
      getGalponesPorGranjaMapLocal()[g3] ?? [],
    );
  }

  void _ensureGalponesIndicesMigrated() {
    final hasIndexed = _prefs.getString(AppConstants.keyGalponesPorGranja);
    if (hasIndexed != null && hasIndexed.isNotEmpty) return;

    final legacy = _prefs.getString(AppConstants.keyCencosGalpones);
    if (legacy == null || legacy.isEmpty) return;

    try {
      final data = Map<String, dynamic>.from(jsonDecode(legacy) as Map);
      if ((data['cencos'] as List?)?.isEmpty ?? true) return;
      final indices = GalponesResolver.buildIndicesFromApiData(data);
      _prefs.setString(AppConstants.keyCencosLista, jsonEncode(indices.cencos));
      _prefs.setString(
        AppConstants.keyGalponesPorCenco,
        jsonEncode(indices.galponesPorCenco),
      );
      _prefs.setString(
        AppConstants.keyGalponesPorGranja,
        jsonEncode(indices.galponesPorGranja),
      );
    } catch (e) {
      debugPrint('StorageService: migración galpones falló: $e');
    }
  }

  List<Map<String, dynamic>> _decodeCencosList(String jsonStr) {
    final decoded = jsonDecode(jsonStr) as List;
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Map<String, List<Map<String, dynamic>>> _decodeGalponesMap(String jsonStr) {
    final decoded = Map<String, dynamic>.from(jsonDecode(jsonStr) as Map);
    final out = <String, List<Map<String, dynamic>>>{};
    decoded.forEach((key, value) {
      if (value is List) {
        out[key] = value
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    });
    return out;
  }

  Future<void> saveProyeccion(Map<String, dynamic> data) async {
    await _prefs.setString(AppConstants.keyProyeccion, jsonEncode(data));
    notifyListeners();
  }

  Map<String, dynamic>? getProyeccion() {
    final s = _prefs.getString(AppConstants.keyProyeccion);
    if (s == null) return null;
    return Map<String, dynamic>.from(jsonDecode(s) as Map);
  }

  Future<void> saveArbolProcesos(Map<String, dynamic> data) async {
    await _prefs.setString(AppConstants.keyArbolProcesos, jsonEncode(data));
    notifyListeners();
  }

  Map<String, dynamic>? getArbolProcesos() {
    final s = _prefs.getString(AppConstants.keyArbolProcesos);
    if (s == null) return null;
    return Map<String, dynamic>.from(jsonDecode(s) as Map);
  }
}
