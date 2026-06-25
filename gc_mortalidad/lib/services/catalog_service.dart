import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class CatalogService extends ChangeNotifier {
  Map<String, dynamic> _catalogos = {};

  Map<String, dynamic> get catalogos => _catalogos;

  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('catalogos');
    if (json != null) {
      _catalogos = Map<String, dynamic>.from(jsonDecode(json) as Map);
      notifyListeners();
    }
  }

  Future<void> mergeCatalogos(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('catalogos');
    if (json != null) {
      _catalogos = Map<String, dynamic>.from(jsonDecode(json) as Map);
    }
    _catalogos.addAll(data);
    await prefs.setString('catalogos', jsonEncode(_catalogos));
    notifyListeners();
  }

  Future<Map<String, dynamic>> downloadCatalogos({
    required Future<Map<String, dynamic>> Function({List<String>? tablas}) apiCall,
    List<String>? tablas,
  }) async {
    final result = await apiCall(tablas: tablas);
    if (result['success'] == true && result['data'] is Map) {
      await mergeCatalogos(Map<String, dynamic>.from(result['data'] as Map));
    }
    return result;
  }
}
