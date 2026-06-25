import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import 'dart:convert';

class StorageService with ChangeNotifier {
  final SharedPreferences _prefs;

  StorageService(this._prefs);

  // Login status
  Future<bool> isLoggedIn() async {
    return _prefs.getBool(AppConstants.keyIsLoggedIn) ?? false;
  }

  Future<void> setLoggedIn(bool value) async {
    await _prefs.setBool(AppConstants.keyIsLoggedIn, value);
  }

  // User data
  // En StorageService
  String? getUserCodeSync() {
    return _prefs.getString(AppConstants.keyUserCode);
  }

  Future<void> setUserCode(String code) async {
    final result = await _prefs.setString(AppConstants.keyUserCode, code);
    debugPrint('DEBUG setUserCode - Guardado: $code, Resultado: $result');
    // Verificar inmediatamente después de guardar
    final verifyCode = _prefs.getString(AppConstants.keyUserCode);
    debugPrint('DEBUG setUserCode - Verificación inmediata: $verifyCode');
  }

  String? getUserName() {
    return _prefs.getString(AppConstants.keyUserName);
  }

  Future<void> setUserName(String name) async {
    await _prefs.setString(AppConstants.keyUserName, name);
  }

  // Device data
  Future<String?> getDeviceId() async {
    return _prefs.getString(AppConstants.keyDeviceId);
  }

 

  Future<void> setDeviceId(String id) async {
    await _prefs.setString(AppConstants.keyDeviceId, id);
  }

  Future<bool> isDeviceAuthorized() async {
    return _prefs.getBool(AppConstants.keyDeviceAuthorized) ?? false;
  }

  Future<void> setDeviceAuthorized(bool value) async {
    await _prefs.setBool(AppConstants.keyDeviceAuthorized, value);
  }

  // Clear all data (logout)
  Future<void> clearAll() async {
    await _prefs.clear();
  }

  // Save login session
  Future<void> saveLoginSession({
    required String userCode,
    required String userName,
    required String deviceId,
   
  }) async {
    await setLoggedIn(true);
    await setUserCode(userCode);
    await setUserName(userName);
    await setDeviceId(deviceId);
    await setDeviceAuthorized(true);
    
    // IMPORTANTE: Notificar cambios y asegurar persistencia
    notifyListeners();
    
    // Verificar que se guardó correctamente (debug)
    final savedCode = _prefs.getString(AppConstants.keyUserCode);
    debugPrint('DEBUG saveLoginSession - userCode guardado: $savedCode, esperado: $userCode');
  }

  
  Future<void> saveForm(String tabla, Map<String, dynamic> data) async {
    // Obtener lista actual
    final List<dynamic>? currentList = _prefs.getStringList(tabla);
    final List<Map<String, dynamic>> records =
        currentList
            ?.map((item) => jsonDecode(item) as Map<String, dynamic>)
            .toList() ??
        <Map<String, dynamic>>[];

    final recordToSave = Map<String, dynamic>.from(data);

    records.add(recordToSave);

    final List<String> jsonRecords = records.map((r) => jsonEncode(r)).toList();

    await _prefs.setStringList(tabla, jsonRecords);
    notifyListeners();
  }

  List<Map<String, dynamic>> getRecordsPendientes(String tabla) {
    final allRecords = _getParsedRecords(tabla);
    final pendingRecords = allRecords
        .where((record) {
          // Un registro está pendiente si no está sincronizado (synced == false)
          final synced = record['synced'] == true || record['synced'] == 'true';
          return !synced;
        })
        .toList();
    
    // Log para debugging
    debugPrint('📋 getRecordsPendientes - Total registros: ${allRecords.length}, Pendientes: ${pendingRecords.length}');
    for (var record in pendingRecords) {
      final guardadoBackend = record['guardado_backend'];
      final evidenciasCompletas = record['evidencias_completas'];
      debugPrint('   - tuuid: ${record['tuuid']}, synced: ${record['synced']}, guardado_backend: $guardadoBackend');
      if (evidenciasCompletas != null && evidenciasCompletas is Map) {
        int totalImagenes = 0;
        evidenciasCompletas.forEach((key, value) {
          if (value is List) {
            totalImagenes += value.length;
          }
        });
        debugPrint('     📸 evidencias_completas: ${evidenciasCompletas.length} niveles, $totalImagenes imágenes totales');
      } else {
        debugPrint('     ⚠️ evidencias_completas: NO presente o vacío');
      }
    }
    
    return pendingRecords;
  }

  Future<void> markAllRecordsAsSynced(String tabla) async {
    final List<String>? currentList = _prefs.getStringList(tabla);
    if (currentList == null || currentList.isEmpty) return;

    // Decodificar todos los registros
    final List<Map<String, dynamic>> records = currentList
        .map((item) => jsonDecode(item) as Map<String, dynamic>)
        .toList();

    // Marcar TODOS como sincronizados
    for (var record in records) {
      record['synced'] = true;
    }

    // Guardar de vuelta en SharedPreferences
    final List<String> updatedRecords = records
        .map((r) => jsonEncode(r))
        .toList();
    await _prefs.setStringList(tabla, updatedRecords);

    notifyListeners();
  }

  /// Marca un registro específico como sincronizado
  /// Compara los registros usando tuuid (preferido) o campos clave para identificar el registro correcto
  Future<void> markRecordAsSynced(
    String tabla,
    Map<String, dynamic> targetRecord,
  ) async {
    final List<String>? currentList = _prefs.getStringList(tabla);
    if (currentList == null || currentList.isEmpty) {
      debugPrint('⚠️ markRecordAsSynced - No hay registros en storage');
      return;
    }

    // Decodificar todos los registros
    final List<Map<String, dynamic>> records = currentList
        .map((item) => jsonDecode(item) as Map<String, dynamic>)
        .toList();

    // Identificar el registro usando tuuid (preferido) o campos clave como fallback
    final targetUuid = targetRecord['tuuid']?.toString();
    final targetNumreg = targetRecord['numreg']?.toString() ?? '';
    final targetFectra = targetRecord['fectra']?.toString() ?? '';
    final targetGranja = targetRecord['granja']?.toString() ?? '';
    final targetGalpon = targetRecord['galpon']?.toString() ?? '';

    debugPrint('🔄 markRecordAsSynced - Marcando registro como sincronizado:');
    debugPrint('   - tuuid: $targetUuid');
    debugPrint('   - numreg: $targetNumreg');
    debugPrint('   - fectra: $targetFectra');
    debugPrint('   - granja: $targetGranja');
    debugPrint('   - galpon: $targetGalpon');

    bool found = false;
    int foundIndex = -1;
    
    for (int i = 0; i < records.length; i++) {
      final record = records[i];
      
      // Intentar primero con tuuid (más confiable)
      if (targetUuid != null && targetUuid.isNotEmpty) {
        final recordUuid = record['tuuid']?.toString();
        if (recordUuid == targetUuid) {
          foundIndex = i;
          found = true;
          break;
        }
      }
      
      // Fallback: usar campos clave
      final recordNumreg = record['numreg']?.toString() ?? '';
      final recordFectra = record['fectra']?.toString() ?? '';
      final recordGranja = record['granja']?.toString() ?? '';
      final recordGalpon = record['galpon']?.toString() ?? '';

      // Comparar campos clave
      if (recordNumreg == targetNumreg &&
          recordFectra == targetFectra &&
          recordGranja == targetGranja &&
          recordGalpon == targetGalpon) {
        foundIndex = i;
        found = true;
        break;
      }
    }
    
    if (found && foundIndex >= 0) {
      // CRÍTICO: Crear un nuevo mapa completo en lugar de modificar el existente
      // Esto evita problemas de referencias compartidas
      final recordAntes = records[foundIndex];
      final syncedAntes = recordAntes['synced'];
      final guardadoBackendAntes = recordAntes['guardado_backend'];
      
      // Crear un nuevo mapa copiando todos los campos del registro original
      final updatedRecord = Map<String, dynamic>.from(recordAntes);
      
      // Actualizar los campos necesarios
      updatedRecord['synced'] = true;
      
      // CRÍTICO: Preservar guardado_backend del targetRecord si viene actualizado,
      // de lo contrario establecerlo en true (porque se está sincronizando)
      if (targetRecord['guardado_backend'] != null) {
        updatedRecord['guardado_backend'] = targetRecord['guardado_backend'];
        debugPrint('   ✓ guardado_backend preservado del targetRecord: ${targetRecord['guardado_backend']}');
      } else {
        updatedRecord['guardado_backend'] = true;
        debugPrint('   ✓ guardado_backend establecido en true (no estaba en targetRecord)');
      }

      final codigoNec = targetRecord['codigoNecropsia']?.toString().trim() ?? '';
      if (codigoNec.isNotEmpty) {
        updatedRecord['codigoNecropsia'] = codigoNec;
      }
      
      // Reemplazar el registro completo en la lista
      records[foundIndex] = updatedRecord;
      
      debugPrint('   ✓ Registro encontrado y actualizado');
      debugPrint('   ✓ synced cambiado de $syncedAntes a ${updatedRecord['synced']}');
      debugPrint('   ✓ guardado_backend cambiado de $guardadoBackendAntes a ${updatedRecord['guardado_backend']}');
    }

    if (found) {
      // Guardar de vuelta en SharedPreferences
      final List<String> updatedRecords = records
          .map((r) => jsonEncode(r))
          .toList();
      await _prefs.setStringList(tabla, updatedRecords);
      
      // Verificar que se guardó correctamente
      final recordGuardado = records.firstWhere(
        (r) => (targetUuid != null && targetUuid.isNotEmpty && r['tuuid']?.toString() == targetUuid) ||
               (r['numreg']?.toString() == targetNumreg && 
                r['fectra']?.toString() == targetFectra &&
                r['granja']?.toString() == targetGranja &&
                r['galpon']?.toString() == targetGalpon),
        orElse: () => {},
      );
      
      debugPrint('💾 markRecordAsSynced - Registro guardado en storage:');
      debugPrint('   - tuuid: ${recordGuardado['tuuid']}');
      debugPrint('   - synced final: ${recordGuardado['synced']} (tipo: ${recordGuardado['synced'].runtimeType})');
      debugPrint('   - guardado_backend final: ${recordGuardado['guardado_backend']}');
      
      notifyListeners();
    } else {
      debugPrint('❌ markRecordAsSynced - Registro NO encontrado para marcar como sincronizado');
    }
  }

  /// Obtener registros por fecha (todos, sincronizados o no). fectra se guarda como YYYY-MM-DD.
  List<Map<String, dynamic>> getRecordsByDate(String tabla, DateTime date) {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final allRecords = _getParsedRecords(tabla);
    return allRecords
        .where((r) {
          final fectra = r['fectra']?.toString().trim() ?? '';
          return fectra == dateStr || fectra.startsWith(dateStr);
        })
        .toList();
  }

  /// Obtener registros por fecha de registro/transacción.
  /// Prioriza: tdate_trans -> tdate -> diareg, y usa fectra como fallback.
  List<Map<String, dynamic>> getRecordsByRegisterDate(
    String tabla,
    DateTime date,
  ) {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final allRecords = _getParsedRecords(tabla);

    String onlyDate(String raw) {
      final s = raw.trim();
      if (s.isEmpty) return '';
      if (s.contains('T')) return s.split('T').first;
      if (s.contains(' ')) return s.split(' ').first;
      return s;
    }

    return allRecords.where((r) {
      final raw = r['tdate_trans']?.toString() ??
          r['tdate']?.toString() ??
          r['diareg']?.toString() ??
          r['fectra']?.toString() ??
          '';
      return onlyDate(raw) == dateStr;
    }).toList();
  }

  List<Map<String, dynamic>> _getParsedRecords(String tabla) {
    final List<dynamic>? currentList = _prefs.getStringList(tabla);
    if (currentList == null) return [];

    return currentList.map((item) {
      final record = jsonDecode(item) as Map<String, dynamic>;
      if (record.containsKey('evidencias_completas')) {
        final evidenciasRaw = record['evidencias_completas'];
        if (evidenciasRaw is Map) {
          final evidenciasNormalizadas = <String, List<Map<String, dynamic>>>{};
          evidenciasRaw.forEach((key, value) {
            if (value is List) {
              evidenciasNormalizadas[key] = value.map((item) {
                if (item is Map<String, dynamic>) {
                  return Map<String, dynamic>.from(item);
                } else if (item is Map) {
                  return Map<String, dynamic>.from(item);
                } else if (item is String) {
                  return {'path': item};
                } else {
                  return {'path': item.toString()};
                }
              }).toList().cast<Map<String, dynamic>>();
            } else {
              evidenciasNormalizadas[key] = [];
            }
          });
          record['evidencias_completas'] = evidenciasNormalizadas;
        }
      }
      return record;
    }).toList();
  }

  /// (Opcional) Obtener todos los registros (para depuración o historial)
  List<Map<String, dynamic>> getAllRecords(String tabla) {
    final List<dynamic>? currentList = _prefs.getStringList(tabla);
    if (currentList == null) return [];

    return currentList
        .map((item) => jsonDecode(item) as Map<String, dynamic>)
        .toList();
  }

  Future<void> setLastSyncDate() async {
    final now = DateTime.now();
    final formattedDate =
        '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/'
        '${now.year} ${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
    await _prefs.setString('last_sync_date', formattedDate);
    notifyListeners();
  }

  Future<String?> getLastSyncDate() async {
    return _prefs.getString('last_sync_date');
  }

  Future<void> setLastDownloadDate() async {
    final now = DateTime.now();
    final formattedDate =
        '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/'
        '${now.year} ${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
    await _prefs.setString('last_download_date', formattedDate);
    notifyListeners();
  }

  Future<String?> getLastDownloadDate() async {
    return _prefs.getString('last_download_date');
  }

  // CENCOS y galpones almacenados localmente
  Future<void> saveCencosGalpones({
    required List<Map<String, dynamic>> cencos,
    required Map<String, List<Map<String, dynamic>>> galponesPorCenco,
  }) async {
    try {
      // Guardar CENCOS
      final cencosJson = jsonEncode(cencos);
      await _prefs.setString('cencos_data', cencosJson);
      
      // Guardar galpones agrupados por CENCO
      final galponesJson = jsonEncode(galponesPorCenco);
      await _prefs.setString('galpones_por_cenco', galponesJson);
      
      debugPrint('💾 CENCOS y galpones guardados localmente');
      debugPrint('   - CENCOS: ${cencos.length}');
      debugPrint('   - CENCOS con galpones: ${galponesPorCenco.length}');
      debugPrint('   - CENCOS: $cencosJson');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error guardando CENCOS y galpones: $e');
    }
  }

  List<Map<String, dynamic>> getCencosLocal() {
    try {
      final cencosJson = _prefs.getString('cencos_data');
      if (cencosJson == null || cencosJson.isEmpty) {
        return [];
      }
      final List<dynamic> decoded = jsonDecode(cencosJson);
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('❌ Error leyendo CENCOS locales: $e');
      return [];
    }
  }

  Map<String, List<Map<String, dynamic>>> getGalponesPorCencoLocal() {
    try {
      final galponesJson = _prefs.getString('galpones_por_cenco');
      if (galponesJson == null || galponesJson.isEmpty) {
        return {};
      }
      final Map<String, dynamic> decoded = jsonDecode(galponesJson);
      return decoded.map((key, value) => MapEntry(
        key,
        (value as List<dynamic>).cast<Map<String, dynamic>>(),
      ));
    } catch (e) {
      debugPrint('❌ Error leyendo galpones locales: $e');
      return {};
    }
  }

  bool hasCencosGalponesLocal() {
    final cencosJson = _prefs.getString('cencos_data');
    return cencosJson != null && cencosJson.isNotEmpty;
  }

  Future<void> savePlanMatchCandidates({
    required List<Map<String, dynamic>> candidates,
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final desdeStr =
        '${desde.year}-${desde.month.toString().padLeft(2, '0')}-${desde.day.toString().padLeft(2, '0')}';
    final hastaStr =
        '${hasta.year}-${hasta.month.toString().padLeft(2, '0')}-${hasta.day.toString().padLeft(2, '0')}';
    final payload = {
      'desde': desdeStr,
      'hasta': hastaStr,
      'timestamp': DateTime.now().toIso8601String(),
      'total': candidates.length,
    };
    await _prefs.setString('plan_match_candidates', jsonEncode(candidates));
    await _prefs.setString('plan_match_meta', jsonEncode(payload));
    notifyListeners();
  }

  List<Map<String, dynamic>> getPlanMatchCandidatesLocal() {
    try {
      final raw = _prefs.getString('plan_match_candidates');
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic> getPlanMatchMeta() {
    try {
      final raw = _prefs.getString('plan_match_meta');
      if (raw == null || raw.isEmpty) return {};
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  bool isDateWithinPlanMatchRange(DateTime selected, {int windowDays = 7}) {
    final meta = getPlanMatchMeta();
    final desdeRaw = meta['desde']?.toString() ?? '';
    final hastaRaw = meta['hasta']?.toString() ?? '';
    if (desdeRaw.isEmpty || hastaRaw.isEmpty) return false;
    try {
      final desde = DateTime.parse(desdeRaw);
      final hasta = DateTime.parse(hastaRaw);
      final min = selected.subtract(Duration(days: windowDays));
      final max = selected.add(Duration(days: windowDays));
      return !min.isBefore(desde) && !max.isAfter(hasta);
    } catch (_) {
      return false;
    }
  }

  List<Map<String, dynamic>> getPlanMatchSuggestions({
    required String granja,
    required String campania,
    required String galpon,
    required int edad,
  }) {
    final candidates = getPlanMatchCandidatesLocal();
    final granjaNorm = _normalize3(granja);
    final campaniaNorm = _normalize3(campania);
    final galponNorm = _normalizeGalpon(galpon);
    final exact = <Map<String, dynamic>>[];
    final tolerancia = <Map<String, dynamic>>[];

    for (final row in candidates) {
      final g = _normalize3(row['granja']?.toString() ?? '');
      final c = _normalize3(row['campania']?.toString() ?? '');
      final gp = _normalizeGalpon(row['galpon']?.toString() ?? '');
      if (g != granjaNorm || c != campaniaNorm || gp != galponNorm) {
        continue;
      }

      final edadPlan = int.tryParse('${row['edad'] ?? 0}') ?? 0;
      final tol = int.tryParse('${row['tolerancia'] ?? 0}') ?? 0;
      if (edadPlan == edad) {
        final item = Map<String, dynamic>.from(row);
        item['isExact'] = true;
        exact.add(item);
        continue;
      }
      if (edad >= (edadPlan - tol) && edad <= (edadPlan + tol)) {
        final item = Map<String, dynamic>.from(row);
        item['isExact'] = false;
        tolerancia.add(item);
      }
    }
    return [...exact, ...tolerancia];
  }

  String _normalize3(String value) {
    final v = value.trim();
    if (v.isEmpty) return '';
    return v.length >= 3 ? v.substring(0, 3) : v.padLeft(3, '0');
  }

  String _normalizeGalpon(String value) {
    final v = value.trim();
    if (v.isEmpty) return '';
    final n = int.tryParse(v);
    if (n == null) return v;
    return '$n';
  }

  Future<void> updateRecords(
    String tabla,
    List<Map<String, dynamic>> records,
  ) async {
    final List<String> jsonRecords = records.map((r) => jsonEncode(r)).toList();
    await _prefs.setStringList(tabla, jsonRecords);
    notifyListeners();
  }

  Future<void> savePlanEventualLocal(Map<String, dynamic> item) async {
    final current = getPlanEventualesLocal();
    current.add(item);
    await _prefs.setString('plan_eventuales_local', jsonEncode(current));
    notifyListeners();
  }

  List<Map<String, dynamic>> getPlanEventualesLocal() {
    try {
      final raw = _prefs.getString('plan_eventuales_local');
      if (raw == null || raw.isEmpty) return [];
      final arr = jsonDecode(raw) as List<dynamic>;
      return arr
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<Map<String, dynamic>> getPlanEventualesPendientesByDate(DateTime date) {
    final target =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return getPlanEventualesLocal()
        .where((e) => (e['synced'] != true) && (e['fecha']?.toString() == target))
        .toList();
  }

  Future<void> markPlanEventualAsSynced({
    required String localPlanId,
    required String realPlanId,
  }) async {
    final all = getPlanEventualesLocal();
    for (final row in all) {
      if ((row['localPlanId']?.toString() ?? '') == localPlanId) {
        row['synced'] = true;
        row['planIdReal'] = realPlanId;
      }
    }
    await _prefs.setString('plan_eventuales_local', jsonEncode(all));
    notifyListeners();
  }

  Future<void> replacePlanIdInNecropsias({
    required String oldPlanId,
    required String newPlanId,
  }) async {
    final records = getAllRecords(AppStrings.formType1);
    bool changed = false;
    for (final r in records) {
      if ((r['planId']?.toString() ?? '') == oldPlanId) {
        r['planId'] = newPlanId;
        changed = true;
      }
    }
    if (changed) {
      await updateRecords(AppStrings.formType1, records);
    }
  }

  Future<void> updatePlanCandidateId({
    required String oldPlanId,
    required String newPlanId,
  }) async {
    final candidates = getPlanMatchCandidatesLocal();
    bool changed = false;
    for (final c in candidates) {
      if ((c['idCronograma']?.toString() ?? '') == oldPlanId) {
        c['idCronograma'] = newPlanId;
        changed = true;
      }
    }
    if (changed) {
      await _prefs.setString('plan_match_candidates', jsonEncode(candidates));
      notifyListeners();
    }
  }

  Future<void> addLocalPlanCandidate(Map<String, dynamic> candidate) async {
    final all = getPlanMatchCandidatesLocal();
    all.add(candidate);
    await _prefs.setString('plan_match_candidates', jsonEncode(all));
    notifyListeners();
  }

  /// Actualiza un registro específico en el storage
  /// Identifica el registro usando tuuid (preferido) o numreg, fectra, granja, galpon como fallback
  Future<bool> updateRecord(
    String tabla,
    Map<String, dynamic> updatedRecord,
  ) async {
    final List<String>? currentList = _prefs.getStringList(tabla);
    if (currentList == null || currentList.isEmpty) return false;

    // Decodificar todos los registros
    final List<Map<String, dynamic>> records = currentList
        .map((item) => jsonDecode(item) as Map<String, dynamic>)
        .toList();

    // Identificar el registro usando tuuid (preferido) o campos clave como fallback
    final targetUuid = updatedRecord['tuuid']?.toString();
    final targetNumreg = updatedRecord['numreg']?.toString() ?? '';
    final targetFectra = updatedRecord['fectra']?.toString() ?? '';
    final targetGranja = updatedRecord['granja']?.toString() ?? '';
    final targetGalpon = updatedRecord['galpon']?.toString() ?? '';

    // Log para debugging
    debugPrint('💾 updateRecord - Actualizando registro en storage:');
    debugPrint('   - tuuid: $targetUuid');
    debugPrint('   - guardado_backend: ${updatedRecord['guardado_backend']} (tipo: ${updatedRecord['guardado_backend']?.runtimeType})');
    debugPrint('   - synced: ${updatedRecord['synced']} (tipo: ${updatedRecord['synced']?.runtimeType})');
    debugPrint('   - numreg: $targetNumreg');
    final evidenciasCompletas = updatedRecord['evidencias_completas'];
    if (evidenciasCompletas != null) {
      if (evidenciasCompletas is Map) {
        debugPrint('   - evidencias_completas: ${evidenciasCompletas.length} niveles');
      } else {
        debugPrint('   - evidencias_completas: presente pero tipo inesperado (${evidenciasCompletas.runtimeType})');
      }
    } else {
      debugPrint('   - evidencias_completas: NO presente');
    }

    bool found = false;
    for (int i = 0; i < records.length; i++) {
      final record = records[i];
      
      // Intentar primero con tuuid (más confiable)
      if (targetUuid != null && targetUuid.isNotEmpty) {
        final recordUuid = record['tuuid']?.toString();
        if (recordUuid == targetUuid) {
          // Reemplazar el registro con el actualizado (preserva todos los campos incluyendo guardado_backend y evidencias_completas)
          records[i] = Map<String, dynamic>.from(updatedRecord);
          debugPrint('   ✓ Registro encontrado por tuuid y actualizado');
          debugPrint('   ✓ guardado_backend preservado: ${records[i]['guardado_backend']}');
          final evidenciasEnRecord = records[i]['evidencias_completas'];
          if (evidenciasEnRecord != null && evidenciasEnRecord is Map) {
            debugPrint('   ✓ evidencias_completas preservado: ${evidenciasEnRecord.length} niveles');
          } else {
            debugPrint('   ⚠️ evidencias_completas NO preservado o vacío');
          }
          found = true;
          break;
        }
      }
      
      // Fallback: usar campos clave (numreg, fectra, granja, galpon)
      final recordNumreg = record['numreg']?.toString() ?? '';
      final recordFectra = record['fectra']?.toString() ?? '';
      final recordGranja = record['granja']?.toString() ?? '';
      final recordGalpon = record['galpon']?.toString() ?? '';

      // Comparar campos clave
      if (recordNumreg == targetNumreg &&
          recordFectra == targetFectra &&
          recordGranja == targetGranja &&
          recordGalpon == targetGalpon) {
        // Reemplazar el registro con el actualizado (preserva todos los campos incluyendo guardado_backend y evidencias_completas)
        records[i] = Map<String, dynamic>.from(updatedRecord);
        debugPrint('   ✓ Registro encontrado por campos clave y actualizado');
        debugPrint('   ✓ guardado_backend preservado: ${records[i]['guardado_backend']}');
        final evidenciasEnRecord = records[i]['evidencias_completas'];
        if (evidenciasEnRecord != null && evidenciasEnRecord is Map) {
          debugPrint('   ✓ evidencias_completas preservado: ${evidenciasEnRecord.length} niveles');
        } else {
          debugPrint('   ⚠️ evidencias_completas NO preservado o vacío');
        }
        found = true;
        break;
      }
    }

    if (found) {
      // Guardar de vuelta en SharedPreferences
      final List<String> updatedRecords = records
          .map((r) => jsonEncode(r))
          .toList();
      await _prefs.setStringList(tabla, updatedRecords);
      
      // Verificar que el flag se preservó correctamente
      final updatedRecordInList = records.firstWhere(
        (r) => (targetUuid != null && targetUuid.isNotEmpty && r['tuuid']?.toString() == targetUuid) ||
               (r['numreg']?.toString() == targetNumreg && 
                r['fectra']?.toString() == targetFectra &&
                r['granja']?.toString() == targetGranja &&
                r['galpon']?.toString() == targetGalpon),
        orElse: () => {},
      );
      
      debugPrint('💾 updateRecord - Registro guardado en storage:');
      debugPrint('   - tuuid: ${updatedRecordInList['tuuid']}');
      debugPrint('   - guardado_backend final: ${updatedRecordInList['guardado_backend']}');
      debugPrint('   - synced final: ${updatedRecordInList['synced']}');
      
      notifyListeners();
      return true;
    }

    debugPrint('💾 updateRecord - Registro NO encontrado para actualizar');
    return false;
  }
}
