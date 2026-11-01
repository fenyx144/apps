import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cenco.dart';
import '../models/galpon.dart';
import '../utils/constants.dart';

class StorageService with ChangeNotifier {
  StorageService(this._prefs);

  final SharedPreferences _prefs;

  Future<bool> isLoggedIn() async =>
      _prefs.getBool(AppConstants.keyIsLoggedIn) ?? false;

  Future<void> setLoggedIn(bool value) async {
    await _prefs.setBool(AppConstants.keyIsLoggedIn, value);
  }

  String? getUserCodeSync() => _prefs.getString(AppConstants.keyUserCode);

  Future<void> setUserCode(String code) async {
    await _prefs.setString(AppConstants.keyUserCode, code);
  }

  String? getUserName() => _prefs.getString(AppConstants.keyUserName);

  Future<void> setUserName(String name) async {
    await _prefs.setString(AppConstants.keyUserName, name);
  }

  String? getDeviceIdSync() => _prefs.getString(AppConstants.keyDeviceId);

  Future<String?> getDeviceId() async =>
      _prefs.getString(AppConstants.keyDeviceId);

  Future<void> setDeviceId(String id) async {
    await _prefs.setString(AppConstants.keyDeviceId, id);
  }

  Future<void> clearAll() async => _prefs.clear();

  /// Limpia solo los datos de sesion, preservando el cache offline
  /// (cencos, galpones, catalogos, bloques, auditorias, cantidad pollos, etc.)
  Future<void> clearSession() async {
    final code = getUserCodeSync();
    // Eliminar keys de sesion
    await _prefs.remove(AppConstants.keyIsLoggedIn);
    await _prefs.remove(AppConstants.keyUserCode);
    await _prefs.remove(AppConstants.keyUserName);
    await _prefs.remove(AppConstants.keyDeviceId);
    await _prefs.remove(AppConstants.keyMortalityVisibility);
    await _prefs.remove(AppConstants.keyUsuarioCodigoSanidad);
    await _prefs.remove(AppConstants.keyDeviceAuthorized);
    // Eliminar datos de formularios del usuario actual
    if (code != null && code.isNotEmpty) {
      await _prefs.remove(_userKey(AppStrings.formTypeMortalidad));
      await _prefs.remove(_userKey(AppStrings.formTypeAuditoria));
    }
    notifyListeners();
  }

  Future<void> saveLoginSession({
    required String userCode,
    required String userName,
    required String deviceId,
    String? usuarioCodigoSanidad,
    Map<String, dynamic>? mortalityVisibility,
    Map<String, dynamic>? permisos,
  }) async {
    await setLoggedIn(true);
    await setUserCode(userCode);
    await setUserName(userName);
    await setDeviceId(deviceId);
    if (usuarioCodigoSanidad != null && usuarioCodigoSanidad.trim().isNotEmpty) {
      await setUsuarioCodigoSanidad(usuarioCodigoSanidad.trim());
    }
    if (mortalityVisibility != null) {
      await setMortalityVisibility(mortalityVisibility);
    }
    if (permisos != null) {
      await savePermisos(permisos);
    }
    await migrateUserData();
    notifyListeners();
  }

  Future<void> setUsuarioCodigoSanidad(String codigo) async {
    await _prefs.setString(AppConstants.keyUsuarioCodigoSanidad, codigo);
    notifyListeners();
  }

  String? getUsuarioCodigoSanidad() {
    final v = _prefs.getString(AppConstants.keyUsuarioCodigoSanidad);
    if (v == null || v.trim().isEmpty) return null;
    return v.trim();
  }

  Future<void> setMortalityVisibility(Map<String, dynamic> vis) async {
    await _prefs.setString(
      AppConstants.keyMortalityVisibility,
      jsonEncode(vis),
    );
    notifyListeners();
  }

  Map<String, dynamic> getMortalityVisibility() {
    final raw = _prefs.getString(AppConstants.keyMortalityVisibility);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  bool canSeeMortalityType(String tipoKey) {
    final vis = getMortalityVisibility();
    if (vis.isEmpty) return true;
    if (vis['todos'] == true || vis['todos'] == 1 || vis['todos'] == '1') {
      return true;
    }
    final v = vis[tipoKey];
    if (v == true || v == 1 || v == '1') return true;
    return false;
  }

  // ── Permisos ACL (san_mortalidad_acceso_app) ──

  Future<void> savePermisos(Map<String, dynamic> permisos) async {
    final map = permisos.map((k, v) => MapEntry(k, v == true || v == 1 || v == '1'));
    await _prefs.setString('permisos_app', jsonEncode(map));
    notifyListeners();
  }

  Map<String, dynamic> getPermisos() {
    final json = _prefs.getString('permisos_app');
    if (json == null || json.isEmpty) return _defaultPermisos();
    return Map<String, dynamic>.from(jsonDecode(json) as Map);
  }

  Map<String, dynamic> _defaultPermisos() => {
    'verDashboard': true,
    'verRegMortalidad': true,
    'verAuditoria': true,
    'verReportes': true,
    'verLiquidacion': true,
    'verLiquidacionTodos': true,
    'verCausasIncubacion': true,
    'verCausasTransporte': true,
    'verCausasProduccion': true,
    'verCausasDespacho': true,
    'editarMortalidad': true,
    'eliminarMortalidad': true,
  };

  bool tienePermiso(String permiso) => getPermisos()[permiso] == true;

  Future<void> saveForm(String tabla, Map<String, dynamic> data) async {
    final records = _getParsedRecords(tabla);
    records.add(Map<String, dynamic>.from(data));
    await _saveRecords(tabla, records);
    notifyListeners();
  }

  Future<void> updateRecord(
    String tabla,
    Map<String, dynamic> updatedRecord,
  ) async {
    final records = _getParsedRecords(tabla);
    final targetUuid = updatedRecord['tuuid']?.toString() ?? '';
    var found = false;

    for (var i = 0; i < records.length; i++) {
      if (records[i]['tuuid']?.toString() == targetUuid && targetUuid.isNotEmpty) {
        records[i] = Map<String, dynamic>.from(updatedRecord);
        found = true;
        break;
      }
    }

    if (!found) {
      records.add(Map<String, dynamic>.from(updatedRecord));
    }

    await _saveRecords(tabla, records);
    notifyListeners();
  }

  Future<void> _saveRecords(
    String tabla,
    List<Map<String, dynamic>> records,
  ) async {
    final jsonRecords = records.map(jsonEncode).toList();
    await _prefs.setStringList(_userKey(tabla), jsonRecords);
  }

  List<Map<String, dynamic>> getAllRecords(String tabla) =>
      _getParsedRecords(tabla);

  List<Map<String, dynamic>> getRecordsPendientes(String tabla) =>
      _getParsedRecords(tabla).where((r) => r['synced'] != true).toList();

  List<Map<String, dynamic>> getRecordsByRegisterDate(
    String tabla,
    DateTime date, {
    bool soloPendientes = false,
  }) {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return _getParsedRecords(tabla).where((r) {
      if (soloPendientes && r['synced'] == true) return false;
      final raw = r['tdate_trans']?.toString() ??
          r['fecha']?.toString() ??
          '';
      final onlyDate = raw.contains('T') ? raw.split('T').first : raw.split(' ').first;
      return onlyDate == dateStr;
    }).toList();
  }

  List<Map<String, dynamic>> _getParsedRecords(String tabla) {
    final currentList = _prefs.getStringList(_userKey(tabla));
    if (currentList == null) return [];
    return currentList
        .map((item) => jsonDecode(item) as Map<String, dynamic>)
        .toList();
  }

  Future<void> markRecordAsSynced(
    String tabla,
    Map<String, dynamic> targetRecord,
  ) async {
    final records = _getParsedRecords(tabla);
    final targetUuid = targetRecord['tuuid']?.toString() ?? '';

    for (var i = 0; i < records.length; i++) {
      if (records[i]['tuuid']?.toString() == targetUuid) {
        records[i] = Map<String, dynamic>.from(records[i]);
        records[i]['synced'] = true;
        if (targetRecord['guardado_backend'] != null) {
          records[i]['guardado_backend'] = targetRecord['guardado_backend'];
        } else {
          records[i]['guardado_backend'] = true;
        }
        for (final key in ['doc', 'serie', 'numero', 'codigo', 'id']) {
          if (targetRecord[key] != null) {
            records[i][key] = targetRecord[key];
          }
        }
        break;
      }
    }

    await _saveRecords(tabla, records);
    notifyListeners();
  }

  Future<void> setLastSyncDate() async {
    await _prefs.setString('last_sync_date', _formatNow());
    notifyListeners();
  }

  Future<String?> getLastSyncDate() async => _prefs.getString('last_sync_date');

  Future<void> setLastDownloadDate() async {
    await _prefs.setString('last_download_date', _formatNow());
    notifyListeners();
  }

  Future<String?> getLastDownloadDate() async =>
      _prefs.getString('last_download_date');

  String _formatNow() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/'
        '${now.year} ${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
  }

  Future<void> saveCencosGalpones({
    required List<Map<String, dynamic>> cencos,
    required Map<String, List<Map<String, dynamic>>> galponesPorCenco,
  }) async {
    final jsonStr = jsonEncode(cencos);
    final jsonLen = jsonStr.length;
    debugPrint('[CENCOS_STORAGE] saveCencosGalpones: cencos.count=${cencos.length} json.len=$jsonLen first=${cencos.isNotEmpty ? cencos.first['codigo'] : 'EMPTY'}');
    await _prefs.setString('cencos_data', jsonStr);
    await _prefs.setString('galpones_por_cenco', jsonEncode(galponesPorCenco));
    notifyListeners();
    // Verificar inmediatamente
    final verifyJson = _prefs.getString('cencos_data');
    debugPrint('[CENCOS_STORAGE] verify post-save: key_exists=${verifyJson != null} len=${verifyJson?.length ?? 0}');
  }

  List<Map<String, dynamic>> getCencosLocal() {
    try {
      final json = _prefs.getString('cencos_data');
      if (json == null || json.isEmpty) {
        debugPrint('[CENCOS_STORAGE] getCencosLocal: NO DATA (null or empty)');
        return [];
      }
      final decoded = jsonDecode(json);
      debugPrint('[CENCOS_STORAGE] getCencosLocal: found data len=${json.length} decoded_type=${decoded.runtimeType}');
      return (decoded as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[CENCOS_STORAGE] getCencosLocal ERROR: $e');
      return [];
    }
  }

  /// Granjas con edad recalculada al día desde fec_ing_min de los galpones.
  List<Cenco> getCencosWithEdadActual() {
    final galponesMap = getGalponesPorCencoLocal();
    return getCencosLocal().map((json) {
      final cenco = Cenco.fromJson(json);
      final prefijo = cenco.granjaCodigo;
      final raw = galponesMap[prefijo] ??
          galponesMap[cenco.codigo] ??
          const <Map<String, dynamic>>[];
      final galpones = raw.map(Galpon.fromJson).toList();
      return cenco.withEdadFromGalpones(galpones);
    }).toList();
  }

  Map<String, List<Map<String, dynamic>>> getGalponesPorCencoLocal() {
    try {
      final json = _prefs.getString('galpones_por_cenco');
      if (json == null || json.isEmpty) return {};
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return decoded.map(
        (k, v) => MapEntry(
          k,
          (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  List<Map<String, dynamic>> getGalponesPorCenco(String cencoCode) {
    final all = getGalponesPorCencoLocal();
    final prefijo = cencoCode.length >= 3 ? cencoCode.substring(0, 3) : cencoCode;
    return all[prefijo] ?? all[cencoCode] ?? [];
  }

  Future<void> saveMotivosMortalidad(List<Map<String, dynamic>> motivos) async {
    final catalogos = getCatalogos();
    catalogos['motivos_mortalidad'] = motivos;
    await _prefs.setString('catalogos', jsonEncode(catalogos));
    notifyListeners();
  }

  List<Map<String, dynamic>> getMotivosMortalidad() {
    final catalogos = getCatalogos();
    final raw = catalogos['motivos_mortalidad'];
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Map<String, dynamic> getCatalogos() {
    try {
      final json = _prefs.getString('catalogos');
      if (json == null) return {};
      return Map<String, dynamic>.from(jsonDecode(json) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> saveCatalogos(Map<String, dynamic> data) async {
    final existing = getCatalogos();
    existing.addAll(data);
    await _prefs.setString('catalogos', jsonEncode(existing));
    notifyListeners();
  }

  // ── Cache offline para Liquidación ──
  Future<void> saveLiquidacionCache(List<Map<String, dynamic>> records) async {
    await _prefs.setString('liquidacion_cache', jsonEncode(records));
  }

  List<Map<String, dynamic>> getLiquidacionCache() {
    try {
      final json = _prefs.getString('liquidacion_cache');
      if (json == null || json.isEmpty) return [];
      return (jsonDecode(json) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveLiquidacionCacheDate(String date) async {
    await _prefs.setString('liquidacion_cache_date', date);
  }

  String? getLiquidacionCacheDate() => _prefs.getString('liquidacion_cache_date');

  // ── Cache offline para Mis Auditorías ──
  Future<void> saveMisAuditoriasCache(List<Map<String, dynamic>> auditorias) async {
    debugPrint('[AUDITORIA_CACHE] save mis: count=${auditorias.length} json.len=${jsonEncode(auditorias).length}');
    await _prefs.setString('mis_auditorias_cache', jsonEncode(auditorias));
  }

  List<Map<String, dynamic>> getMisAuditoriasCache() {
    try {
      final json = _prefs.getString('mis_auditorias_cache');
      if (json == null || json.isEmpty) {
        debugPrint('[AUDITORIA_CACHE] get mis: NO DATA');
        return [];
      }
      final decoded = jsonDecode(json);
      debugPrint('[AUDITORIA_CACHE] get mis: found len=${json.length} items=${(decoded as List).length}');
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[AUDITORIA_CACHE] get mis ERROR: $e');
      return [];
    }
  }

  // ── Cache offline para Auditoria Pendiente (registros aun no auditados) ──
  Future<void> saveAuditoriaPendienteCache(List<Map<String, dynamic>> registros) async {
    debugPrint('[AUDITORIA_CACHE] save pendientes: count=${registros.length} json.len=${jsonEncode(registros).length}');
    await _prefs.setString('auditoria_pendiente_cache', jsonEncode(registros));
  }

  List<Map<String, dynamic>> getAuditoriaPendienteCache() {
    try {
      final json = _prefs.getString('auditoria_pendiente_cache');
      if (json == null || json.isEmpty) {
        debugPrint('[AUDITORIA_CACHE] get pendientes: NO DATA');
        return [];
      }
      final decoded = jsonDecode(json);
      debugPrint('[AUDITORIA_CACHE] get pendientes: found len=${json.length} items=${(decoded as List).length}');
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[AUDITORIA_CACHE] get pendientes ERROR: $e');
      return [];
    }
  }

  // ── Offline hash para login offline ──
  Future<void> saveOfflineHash(String hash) async {
    await _prefs.setString('offline_hash', hash);
  }

  String? getOfflineHash() => _prefs.getString('offline_hash');

  // ── Enom usado en el login (para AES offline) ──
  Future<void> saveLoginEnom(String enom) async {
    await _prefs.setString('login_enom', enom);
  }

  String? getLoginEnom() => _prefs.getString('login_enom');

  // ── Cache de cantidad de pollos ──
  Future<void> saveCantidadPollos(Map<String, List<Map<String, dynamic>>> data) async {
    await _prefs.setString('cantidad_pollos', jsonEncode(data));
  }

  Map<String, List<Map<String, dynamic>>> getCantidadPollos() {
    try {
      final json = _prefs.getString('cantidad_pollos');
      if (json == null || json.isEmpty) return {};
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return decoded.map(
        (k, v) => MapEntry(
          k,
          (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  List<Map<String, dynamic>> getCantidadPollosPorGalpon(String tcencos, String tcodint) {
    final all = getCantidadPollos();
    final key = '${tcencos}_$tcodint';
    return all[key] ?? [];
  }

  // ── Cache offline para Liquidación por Bloques ──
  Future<void> saveBloquesLiquidacion(List<Map<String, dynamic>> bloques) async {
    debugPrint('[BLOQUES_STORAGE] save: count=${bloques.length} json.len=${jsonEncode(bloques).length}');
    await _prefs.setString('bloques_liquidacion', jsonEncode(bloques));
    final verify = _prefs.getString('bloques_liquidacion');
    debugPrint('[BLOQUES_STORAGE] verify post-save: exists=${verify != null} len=${verify?.length ?? 0}');
  }

  List<Map<String, dynamic>> getBloquesLiquidacion() {
    try {
      final json = _prefs.getString('bloques_liquidacion');
      if (json == null || json.isEmpty) {
        debugPrint('[BLOQUES_STORAGE] get: NO DATA');
        return [];
      }
      final decoded = jsonDecode(json);
      debugPrint('[BLOQUES_STORAGE] get: found len=${json.length} items=${(decoded as List).length}');
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[BLOQUES_STORAGE] get ERROR: $e');
      return [];
    }
  }

  // ── User-scoped key para registros offline ──
  String _userKey(String tabla) {
    final code = getUserCodeSync();
    if (code != null && code.isNotEmpty) {
      return '${code}_$tabla';
    }
    return tabla;
  }

  // ── Migrar datos antiguos (sin prefijo de usuario) a user-scoped ──
  Future<void> migrateUserData() async {
    final code = getUserCodeSync();
    if (code == null || code.isEmpty) return;
    for (final tabla in [
      AppStrings.formTypeMortalidad,
      AppStrings.formTypeAuditoria,
    ]) {
      final oldKey = tabla;
      final newKey = _userKey(tabla);
      if (oldKey == newKey) continue;
      final oldData = _prefs.getStringList(oldKey);
      if (oldData != null && oldData.isNotEmpty) {
        final newData = _prefs.getStringList(newKey) ?? [];
        newData.addAll(oldData);
        await _prefs.setStringList(newKey, newData);
        await _prefs.remove(oldKey);
      }
    }
  }

  // ── Granja por defecto (Configuracion) ──
  Future<void> saveDefaultGranja(String granjaCodigo) async {
    await _prefs.setString('default_granja', granjaCodigo);
  }

  String? getDefaultGranja() => _prefs.getString('default_granja');
}
