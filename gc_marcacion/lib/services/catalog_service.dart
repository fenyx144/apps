import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/comida_horario.dart';
import '../utils/constants.dart';
import 'api_service.dart';

class CatalogService with ChangeNotifier {
  Map<String, dynamic> _catalogos = {};
  List<PersonalDespacho> _personal = [];
  List<HorarioComida> _horarios = [];
  String _horarioOrigen = horarioOrigenReferencia;
  bool _isLoading = false;

  Map<String, dynamic> get catalogos => _catalogos;
  List<PersonalDespacho> get personal => List.unmodifiable(_personal);
  List<HorarioComida> get horarios => List.unmodifiable(_horarios);
  String get horarioOrigen => _horarioOrigen;
  bool get isLoading => _isLoading;
  bool get hasPersonal => _personal.isNotEmpty;

  Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('catalogos');
      _catalogos = (data != null && data.isNotEmpty)
          ? Map<String, dynamic>.from(jsonDecode(data) as Map)
          : {};

      final personalRaw = prefs.getString(AppConstants.keyPersonal);
      _personal = _parsePersonal(personalRaw);

      final horarioRaw = prefs.getString(AppConstants.keyHorarios);
      _horarios = _parseHorarios(horarioRaw);
      _horarioOrigen =
          prefs.getString(AppConstants.keyHorarioOrigen) ??
              horarioOrigenReferencia;
      notifyListeners();
    } catch (e) {
      debugPrint('CatalogService: $e');
      _catalogos = {};
      _personal = [];
      _horarios = [];
      notifyListeners();
    }
  }

  Future<bool> downloadCatalogos({List<String>? tablas}) async {
    if (_isLoading) return false;
    if (_catalogos.isEmpty) await loadFromPrefs();
    _isLoading = true;
    notifyListeners();
    try {
      final result = await ApiService().downloadCatalogos(tablas: tablas);
      if (result['success'] == true && result['data'] is Map) {
        final raw = Map<String, dynamic>.from(result['data'] as Map);
        if (tablas != null && tablas.isNotEmpty) {
          for (final t in tablas) {
            if (raw.containsKey(t)) _catalogos[t] = raw[t];
          }
        } else {
          _catalogos = raw;
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('catalogos', jsonEncode(_catalogos));
        notifyListeners();
        if (tablas == null || tablas.isEmpty) return _catalogos.isNotEmpty;
        return tablas.every(_catalogos.containsKey);
      }
      return false;
    } catch (e) {
      debugPrint('CatalogService download: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Personal programado y horario de comidas. Devuelve el aviso del servidor
  /// cuando la tabla de personal no se pudo leer.
  Future<({bool ok, String aviso})> downloadMarcacion() async {
    final result = await ApiService().downloadCatalogosMarcacion();
    if (result['success'] != true || result['data'] is! Map) {
      return (
        ok: false,
        aviso: result['message']?.toString() ?? 'No se descargó el personal',
      );
    }
    final data = Map<String, dynamic>.from(result['data'] as Map);
    final prefs = await SharedPreferences.getInstance();
    final personalJson = jsonEncode(data['personal'] ?? []);
    final horariosJson = jsonEncode(data['horarios'] ?? []);
    final origen = (data['horario_origen'] ?? horarioOrigenReferencia)
        .toString();
    await prefs.setString(AppConstants.keyPersonal, personalJson);
    await prefs.setString(AppConstants.keyHorarios, horariosJson);
    await prefs.setString(AppConstants.keyHorarioOrigen, origen);
    _personal = _parsePersonal(personalJson);
    _horarios = _parseHorarios(horariosJson);
    _horarioOrigen = origen;
    notifyListeners();
    final aviso = (data['aviso'] ?? result['message'] ?? '').toString();
    return (ok: true, aviso: aviso);
  }

  List<PersonalDespacho> _parsePersonal(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(PersonalDespacho.fromJson)
          .where((p) => p.dni.isNotEmpty && p.nombre.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<HorarioComida> _parseHorarios(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.whereType<Map>().map(HorarioComida.fromJson).toList();
    } catch (_) {
      return [];
    }
  }
}
