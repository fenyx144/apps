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
    await _prefs.setString(AppConstants.keyUserCode, code);
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

  getRol() {
    return _prefs.getString('rol_sanidad');
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
    required String rol,
  }) async {
    await setLoggedIn(true);
    await setUserCode(userCode);
    await setUserName(userName);
    await setDeviceId(deviceId);
    await setDeviceAuthorized(true);
    await setRol(rol);
  }

  setRol(String rol) async {
    await _prefs.setString('rol_sanidad', rol);
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
    final List<dynamic>? currentList = _prefs.getStringList(tabla);
    if (currentList == null) return [];

    return currentList
        .map((item) => jsonDecode(item) as Map<String, dynamic>)
        .where((record) => record['synced'] != true)
        .toList();
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

  Future<void> updateRecords(
    String tabla,
    List<Map<String, dynamic>> records,
  ) async {
    final List<String> jsonRecords = records.map((r) => jsonEncode(r)).toList();
    await _prefs.setStringList(tabla, jsonRecords);
    notifyListeners();
  }
}
