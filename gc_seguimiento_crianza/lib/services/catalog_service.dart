import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class CatalogService with ChangeNotifier {
  Map<String, dynamic> _catalogos = {};
  bool _isLoading = false;

  Map<String, dynamic> get catalogos => _catalogos;
  bool get isLoading => _isLoading;

  Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('catalogos');
      if (data != null && data.isNotEmpty) {
        _catalogos = Map<String, dynamic>.from(jsonDecode(data) as Map);
      } else {
        _catalogos = {};
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading catalogs: $e');
      _catalogos = {};
      notifyListeners();
    }
  }

  void clearMemory() {
    _catalogos = {};
    notifyListeners();
  }

  Future<bool> downloadCatalogos({List<String>? tablas}) async {
    if (_isLoading) return false;
    if (_catalogos.isEmpty) {
      await loadFromPrefs();
    }
    _isLoading = true;
    notifyListeners();
    try {
      final result = await ApiService().downloadCatalogos(tablas: tablas);
      if (result['success'] == true) {
        final raw = result['data'];
        if (raw is Map<String, dynamic>) {
          if (tablas != null && tablas.isNotEmpty) {
            for (final t in tablas) {
              if (raw.containsKey(t)) {
                _catalogos[t] = raw[t];
              }
            }
          } else {
            _catalogos.addAll(raw);
          }
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('catalogos', jsonEncode(_catalogos));
        notifyListeners();
        return _hasTablasDescargadas(tablas);
      }
      debugPrint(
        'downloadCatalogos falló: ${result['message'] ?? 'sin mensaje'}',
      );
    } catch (e) {
      debugPrint('Error downloading catalogs: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  bool _hasTablasDescargadas(List<String>? tablas) {
    if (tablas == null || tablas.isEmpty) {
      return _catalogos.isNotEmpty;
    }
    for (final t in tablas) {
      final data = _catalogos[t];
      if (data is List && data.isNotEmpty) return true;
    }
    return false;
  }
}
