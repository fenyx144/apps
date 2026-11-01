import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../utils/constants.dart';
import '../utils/galpones_resolver.dart';
import '../utils/record_id.dart';

class StorageService with ChangeNotifier {
  final SharedPreferences _prefs;
  String? _lastDownloadDateCache;
  String? _lastSyncDateCache;

  /// Código de usuario sin espacios y en mayúsculas (login vs. registro).
  static String normUsuario(String? raw) => (raw ?? '').trim().toUpperCase();

  StorageService(this._prefs) {
    _lastDownloadDateCache = _prefs.getString(AppConstants.keyLastDownloadDate);
    _lastSyncDateCache = _prefs.getString(AppConstants.keyLastSyncDate);
  }

  Future<bool> isLoggedIn() async =>
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

  Future<void> clearAll() async {
    await _prefs.clear();
    _lastDownloadDateCache = null;
    _lastSyncDateCache = null;
    notifyListeners();
  }

  /// Cierra sesión sin borrar catálogos, credenciales offline ni registros.
  Future<void> clearSession() async {
    await _prefs.setBool(AppConstants.keyIsLoggedIn, false);
    notifyListeners();
  }

  /// Granja de trabajo elegida en «Mi granja» (menú → Opciones). Vacía si el
  /// usuario todavía no la eligió: en ese caso los formularios arrancan como
  /// antes, sin granja premarcada.
  String getGranjaTrabajo() =>
      _prefs.getString(AppConstants.keyGranjaTrabajo) ?? '';

  Future<void> saveGranjaTrabajo(String granja3) async {
    await _prefs.setString(AppConstants.keyGranjaTrabajo, granja3.trim());
    notifyListeners();
  }

  Future<void> saveRecord(Map<String, dynamic> data) async {
    final tabla = AppStrings.recordsTable;
    final list = _prefs.getStringList(tabla) ?? [];
    final records = list
        .map((e) => Map<String, dynamic>.from(jsonDecode(e) as Map))
        .toList();
    final copy = Map<String, dynamic>.from(data);
    if (!EvidenciaRecordId.isUuidV4(EvidenciaRecordId.of(copy))) {
      copy['id'] = const Uuid().v4();
    }
    final created = copy['created_at']?.toString().trim() ?? '';
    if (created.isEmpty) {
      copy['created_at'] = DateTime.now().toIso8601String();
    }
    final u = normUsuario(copy['usuario']?.toString());
    final mi = normUsuario(getUserCodeSync());
    if (u.isNotEmpty) {
      copy['usuario'] = u;
    } else if (mi.isNotEmpty) {
      copy['usuario'] = mi;
    }
    records.add(EvidenciaRecordId.normalize(copy));
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
    final miUsuario = normUsuario(getUserCodeSync());
    final records = list.map((e) {
      final raw = Map<String, dynamic>.from(jsonDecode(e) as Map);
      if (EvidenciaRecordId.hadLegacyFields(raw)) {
        needsPersist = true;
      }
      final r = EvidenciaRecordId.normalize(raw);
      final u = normUsuario(r['usuario']?.toString());
      // Un registro sin usuario es legado: se lo queda quien lo abre, una sola
      // vez, para que deje de ser visible para todos los usuarios del equipo.
      if (miUsuario.isNotEmpty && u.isEmpty) {
        r['usuario'] = miUsuario;
        needsPersist = true;
      } else if (u.isNotEmpty && r['usuario']?.toString() != u) {
        r['usuario'] = u;
        needsPersist = true;
      }
      return r;
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

  /// Registros visibles para el usuario actual (solo los suyos).
  ///
  /// Sin sesión se muestran todos, para que el dashboard no quede en cero. Un
  /// registro sin usuario también cuenta: es legado y [getAllRecords] se lo
  /// asigna a quien lo abre.
  List<Map<String, dynamic>> getMyRecords() {
    final miUsuario = normUsuario(getUserCodeSync());
    if (miUsuario.isEmpty) return getAllRecords();
    return getAllRecords().where((r) {
      final u = normUsuario(r['usuario']?.toString());
      return u.isEmpty || u == miUsuario;
    }).toList();
  }

  /// Pendientes visibles para el usuario actual.
  List<Map<String, dynamic>> getMyRecordsPendientes() {
    return getMyRecords()
        .where((r) => r['synced'] != true && r['synced'] != 'true')
        .toList();
  }

  /// Cantidad de pendientes visibles para el usuario actual.
  int getMyPendingCount() => getMyRecordsPendientes().length;

  /// Registros del usuario actual para una fecha específica.
  List<Map<String, dynamic>> getMyRecordsByDate(DateTime date) {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return getMyRecords()
        .where((r) => (r['fecha']?.toString() ?? '').startsWith(dateStr))
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

  /// El servidor recibió el uuid pero las imágenes no quedaron completas.
  ///
  /// Sigue en el dispositivo como pendiente para que el menú lo reenvíe y el
  /// servidor repare los archivos. [guardadoBackend] indica que la fila ya
  /// existe y no hay que insertarla de nuevo.
  Future<void> markRecordPending(
    Map<String, dynamic> target, {
    bool guardadoBackend = true,
  }) async {
    final recordId = EvidenciaRecordId.of(target);
    if (recordId.isEmpty) return;

    final records = getAllRecords();
    for (var i = 0; i < records.length; i++) {
      if (EvidenciaRecordId.of(records[i]) == recordId) {
        records[i] = EvidenciaRecordId.normalize({
          ...records[i],
          'id': recordId,
          'synced': false,
          'guardado_backend': guardadoBackend,
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

  /// Convierte un sello de [_formatSyncTimestamp] (`dd/MM/yyyy HH:mm`) a fecha.
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

  /// Fecha/hora de la última descarga de catálogos, o `null` si nunca se bajó.
  DateTime? get lastDownloadDateTime =>
      _parseSyncTimestamp(lastDownloadDateDisplay);

  /// `true` si nunca se descargaron catálogos o si ya pasaron
  /// [AppConstants.staleCatalogDays] días desde la última descarga.
  bool get needsCatalogUpdate {
    final ultima = lastDownloadDateTime;
    if (ultima == null) return true;
    final dias = DateTime.now().difference(ultima).inDays;
    return dias >= AppConstants.staleCatalogDays;
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

  Future<void> clearCencosGalpones() async {
    await _prefs.remove(AppConstants.keyCencosGalpones);
    await _prefs.remove(AppConstants.keyCencosLista);
    await _prefs.remove(AppConstants.keyGalponesPorCenco);
    await _prefs.remove(AppConstants.keyGalponesPorGranja);
    await _prefs.remove(AppConstants.keyProyeccion);
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

  List<Map<String, dynamic>> getGalponesMetaPorCenco(
    String norm6, {
    List<Map<String, dynamic>> fallbackGalpones = const [],
  }) {
    if (norm6.length < 6) return fallbackGalpones;
    for (final entry in getGalponesPorCencoLocal().entries) {
      if (GalponesResolver.normalizarCodigoCenco(entry.key) != norm6) {
        continue;
      }
      if (entry.value.isNotEmpty) {
        return List<Map<String, dynamic>>.from(entry.value);
      }
    }
    for (final c in getCencosListaLocal()) {
      final cc = GalponesResolver.normalizarCodigoCenco(
        (c['codigo'] ?? '').toString(),
      );
      if (cc != norm6) continue;
      final gps = GalponesResolver.parseGalponesList(
        c['galpones'],
        codigoCenco: cc,
      );
      if (gps.isNotEmpty) return gps;
    }
    if (fallbackGalpones.isNotEmpty) {
      return GalponesResolver.filterGalponesPorCenco(
        fallbackGalpones,
        norm6,
      );
    }
    return GalponesResolver.filterGalponesPorCenco(
      getGalponesForGranja(norm6.substring(0, 3)),
      norm6,
    );
  }

  ({int total, int conFecIng}) statsFecIngMin() {
    var total = 0;
    var conFecIng = 0;
    getGalponesPorCencoLocal().forEach((_, list) {
      for (final g in list) {
        total++;
        final fi = (g['fec_ing_min'] ?? '').toString().trim();
        if (fi.isNotEmpty && fi != '0000-00-00') conFecIng++;
      }
    });
    return (total: total, conFecIng: conFecIng);
  }

  Future<void> mergeCampaniaInfoFromApi({
    required String granja3,
    required String campania,
    required Map<String, dynamic> data,
  }) async {
    final g3 = _normGranjaKey(granja3);
    final camp = _padCampania(campania);
    if (g3.isEmpty || camp.isEmpty) return;

    final fi = (data['fecha_inicio'] ?? '').toString().trim();
    final ff = (data['fecha_fin'] ?? '').toString().trim();
    if (!_validYmd(fi) && !_validYmd(ff) && data['activa'] == null) return;

    final prev = getProyeccion() ?? {};
    final campMap = _campaniasMapFrom(prev['campanias_por_granja']);
    final rows = List<Map<String, dynamic>>.from(
      (campMap[g3] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map)) ??
          [],
    );

    var idx = rows.indexWhere(
      (r) => _padCampania((r['campania'] ?? '').toString()) == camp,
    );
    if (idx < 0) {
      rows.add({'campania': camp, 'codigo': g3 + camp});
      idx = rows.length - 1;
    }
    final row = Map<String, dynamic>.from(rows[idx]);
    if (_validYmd(fi)) row['fecha_inicio'] = fi;
    if (_validYmd(ff)) row['fecha_fin'] = ff;
    rows[idx] = row;

    await saveProyeccion({'campanias_por_granja': {g3: rows}});
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
    final prev = getProyeccion();
    final merged = _mergeProyeccionMaps(prev, data);
    await _prefs.setString(AppConstants.keyProyeccion, jsonEncode(merged));
    notifyListeners();
  }

  /// Acumula campañas/cencos ccos en el dispositivo y poda fuera de retención.
  static Map<String, dynamic> _mergeProyeccionMaps(
    Map<String, dynamic>? prev,
    Map<String, dynamic> next,
  ) {
    final hoy = _ymd(DateTime.now());
    final desde = _ymd(
      DateTime.now().subtract(
        Duration(days: AppConstants.catalogHistoricoDias),
      ),
    );

    final out = Map<String, dynamic>.from(next);
    out['fecha'] = hoy;
    out['catalogo_actualizado_en'] = DateTime.now().toIso8601String();
    out['catalogo_retencion_desde'] = desde;
    out['fuente_fechas'] = out['fuente_fechas'] ?? 'ccos';

    final prevCamp = _campaniasMapFrom(prev?['campanias_por_granja']);
    final nextCamp = _campaniasMapFrom(out['campanias_por_granja']);
    final granjasKeys = {...prevCamp.keys, ...nextCamp.keys};
    final mergedCamp = <String, dynamic>{};

    for (final gk in granjasKeys) {
      final g3 = _normGranjaKey(gk);
      if (g3.isEmpty) continue;
      final rows = _mergeCampaniasRows(
        prevCamp[g3] ?? prevCamp[gk],
        nextCamp[g3] ?? nextCamp[gk],
      );
      final podadas = rows
          .where((row) => _campaniaDentroRetencion(row, desde, hoy))
          .toList();
      if (podadas.isNotEmpty) {
        mergedCamp[g3] = podadas;
      }
    }
    out['campanias_por_granja'] = mergedCamp;

    out['cencos'] = _mergeCencosList(
      prev?['cencos'],
      out['cencos'],
      desde,
      hoy,
    );
    out['granjas'] = _mergeGranjasList(prev?['granjas'], out['granjas']);

    final fechasIni = <String>[];
    mergedCamp.forEach((_, raw) {
      if (raw is! List) return;
      for (final row in raw) {
        if (row is! Map) continue;
        final fi = _fechaInicioRow(Map<String, dynamic>.from(row));
        if (fi.isNotEmpty) fechasIni.add(fi);
      }
    });
    fechasIni.sort();
    out['historico_desde'] = fechasIni.isEmpty ? desde : fechasIni.first;
    out['historico_hasta'] = hoy;

    return out;
  }

  static String _ymd(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static String _normGranjaKey(String gk) {
    var s = gk.trim();
    while (s.length < 3) {
      s = '0$s';
    }
    return s.length > 3 ? s.substring(0, 3) : s;
  }

  static bool _validYmd(String? raw) {
    final s = (raw ?? '').trim();
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s) && s != '0000-00-00';
  }

  static Map<String, dynamic> _campaniasMapFrom(dynamic raw) {
    if (raw is! Map) return {};
    final out = <String, dynamic>{};
    raw.forEach((key, value) {
      final g3 = _normGranjaKey(key.toString());
      if (g3.isEmpty || value is! List) return;
      out[g3] = value
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    });
    return out;
  }

  static String _padCampania(String camp) {
    var d = camp.replaceAll(RegExp(r'\D'), '');
    if (d.length >= 3) return d.substring(d.length - 3);
    while (d.length < 3) {
      d = '0$d';
    }
    return d.substring(d.length - 3);
  }

  static String _fechaInicioRow(Map<String, dynamic> row) {
    for (final k in ['fecha_inicio', 'fec_inicio', 'fecini']) {
      final v = (row[k] ?? '').toString().trim();
      if (_validYmd(v)) return v;
    }
    return '';
  }

  static String _fechaFinRow(Map<String, dynamic> row) {
    for (final k in ['fecha_fin', 'fec_fin', 'fecfin']) {
      final v = (row[k] ?? '').toString().trim();
      if (_validYmd(v)) return v;
    }
    return '';
  }

  static bool _campaniaDentroRetencion(
    Map<String, dynamic> row,
    String desdeYmd,
    String hastaYmd,
  ) {
    final fi = _fechaInicioRow(row);
    if (fi.isEmpty) return true;
    if (fi.compareTo(hastaYmd) > 0) return false;
    final ff = _fechaFinRow(row);
    if (ff.isEmpty) return true;
    return ff.compareTo(desdeYmd) >= 0;
  }

  static List<Map<String, dynamic>> _mergeCampaniasRows(
    dynamic prevRaw,
    dynamic nextRaw,
  ) {
    final byCamp = <String, Map<String, dynamic>>{};

    void absorb(dynamic raw) {
      if (raw is! List) return;
      for (final item in raw) {
        if (item is! Map) continue;
        final row = Map<String, dynamic>.from(item);
        final camp = _padCampania((row['campania'] ?? '').toString());
        if (camp.isEmpty) continue;
        row['campania'] = camp;
        final prev = byCamp[camp];
        byCamp[camp] = prev == null ? row : _mergeCampaniaRow(prev, row);
      }
    }

    absorb(prevRaw);
    absorb(nextRaw);

    final camps = byCamp.keys.toList()..sort();
    return camps.map((c) => byCamp[c]!).toList();
  }

  static Map<String, dynamic> _mergeCampaniaRow(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final out = Map<String, dynamic>.from(b);
    final fiA = _fechaInicioRow(a);
    final fiB = _fechaInicioRow(b);
    if (fiA.isNotEmpty && fiB.isNotEmpty) {
      out['fecha_inicio'] = fiA.compareTo(fiB) <= 0 ? fiA : fiB;
    } else if (fiA.isNotEmpty) {
      out['fecha_inicio'] = fiA;
    }

    final ffA = _fechaFinRow(a);
    final ffB = _fechaFinRow(b);
    if (ffA.isEmpty || ffB.isEmpty) {
      if (ffA.isEmpty && ffB.isEmpty) {
        out.remove('fecha_fin');
      } else {
        out['fecha_fin'] = ffA.isEmpty ? ffB : ffA;
      }
    } else {
      out['fecha_fin'] = ffA.compareTo(ffB) >= 0 ? ffA : ffB;
    }

    for (final k in ['nombre', 'swac', 'codigo']) {
      final vb = (out[k] ?? '').toString().trim();
      final va = (a[k] ?? '').toString().trim();
      if (vb.isEmpty && va.isNotEmpty) out[k] = a[k];
    }
    return out;
  }

  static List<Map<String, dynamic>> _mergeCencosList(
    dynamic prevRaw,
    dynamic nextRaw,
    String desdeYmd,
    String hastaYmd,
  ) {
    final byCodigo = <String, Map<String, dynamic>>{};

    void absorb(dynamic raw) {
      if (raw is! List) return;
      for (final item in raw) {
        if (item is! Map) continue;
        final row = Map<String, dynamic>.from(item);
        final codigo = (row['codigo'] ?? '').toString().trim();
        if (codigo.length < 6) continue;
        byCodigo[codigo] = row;
      }
    }

    absorb(prevRaw);
    absorb(nextRaw);

    final out = <Map<String, dynamic>>[];
    for (final row in byCodigo.values) {
      final campRow = <String, dynamic>{
        'campania': row['campania'],
        'fecha_inicio': row['fecha_inicio'] ?? row['fecini'],
        'fecha_fin': row['fecha_fin'] ?? row['fecfin'],
      };
      if (_campaniaDentroRetencion(campRow, desdeYmd, hastaYmd)) {
        out.add(row);
      }
    }
    out.sort((a, b) =>
        (a['codigo'] ?? '').toString().compareTo((b['codigo'] ?? '').toString()));
    return out;
  }

  static List<Map<String, dynamic>> _mergeGranjasList(
    dynamic prevRaw,
    dynamic nextRaw,
  ) {
    final byCodigo = <String, Map<String, dynamic>>{};

    void absorb(dynamic raw) {
      if (raw is! List) return;
      for (final item in raw) {
        if (item is! Map) continue;
        final row = Map<String, dynamic>.from(item);
        final cod = _normGranjaKey(
          (row['granja'] ?? row['codigo'] ?? '').toString(),
        );
        if (cod.isEmpty) continue;
        byCodigo[cod] = row;
      }
    }

    absorb(prevRaw);
    absorb(nextRaw);

    final out = byCodigo.values.toList();
    out.sort((a, b) => _normGranjaKey((a['granja'] ?? a['codigo'] ?? '').toString())
        .compareTo(_normGranjaKey((b['granja'] ?? b['codigo'] ?? '').toString())));
    return out;
  }

  /// Planificación de visitas descargada (JSON tal cual la arma
  /// `PlanVisitasService`). Se guarda con la fecha y hora de la descarga.
  Future<void> savePlanVisitas(String json) async {
    await _prefs.setString(AppConstants.keyPlanVisitas, json);
    await _prefs.setString(
      AppConstants.keyPlanVisitasFecha,
      DateTime.now().toIso8601String(),
    );
    notifyListeners();
  }

  String? getPlanVisitasJson() => _prefs.getString(AppConstants.keyPlanVisitas);

  /// Momento de la última descarga de la planificación, o `null` si nunca.
  DateTime? getPlanVisitasFecha() {
    final s = _prefs.getString(AppConstants.keyPlanVisitasFecha);
    return s == null ? null : DateTime.tryParse(s);
  }

  Map<String, dynamic>? getProyeccion() {
    final s = _prefs.getString(AppConstants.keyProyeccion);
    if (s == null) return null;
    return Map<String, dynamic>.from(jsonDecode(s) as Map);
  }

  Future<void> saveAppInfo(Map<String, dynamic> data) async {
    await _prefs.setString(AppConstants.keyAppInfo, jsonEncode(data));
    notifyListeners();
  }

  Map<String, dynamic>? getAppInfo() {
    final s = _prefs.getString(AppConstants.keyAppInfo);
    if (s == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(s) as Map);
    } catch (_) {
      return null;
    }
  }

  String? getProveedoresVacunaCatalogJson() =>
      _prefs.getString(AppConstants.keyProveedoresVacunaCatalog);

  Future<void> saveProveedoresVacunaCatalogJson(String json) async {
    await _prefs.setString(AppConstants.keyProveedoresVacunaCatalog, json);
    notifyListeners();
  }
}
