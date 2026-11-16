import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class CatalogService with ChangeNotifier {
  Map<String, dynamic> _catalogos = {};
  bool _isLoading = false;

  Map<String, dynamic> get catalogos => _catalogos;
  bool get isLoading => _isLoading;
  bool get isEmpty => _catalogos.isEmpty;

  // Pre-carga desde SharedPreferences (llamado en main.dart)
  Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? data = prefs.getString('catalogos');
      if (data != null) {
        _catalogos = jsonDecode(data) as Map<String, dynamic>;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading catalogs: $e');
    }
  }

  Future<bool> downloadCatalogos({List<String>? tablas}) async {
    print('aqui');
    if (_isLoading) return false;

    _isLoading = true;
    notifyListeners();

    try {
      final apiService = ApiService();
      final result = await apiService.downloadCatalogos(tablas: tablas);
      print(result);
      if (result['success'] == true) {
        final rawData = result['data'];
        print(rawData);
        final nuevosDatos = rawData is Map<String, dynamic> ? rawData : <String, dynamic>{};

        // Merge de datos (download.php devuelve: laboratorios, emp_trans, usuarios, muestras, paquetes, analisis)
        _catalogos.addAll(nuevosDatos);

        // Guardar en SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('catalogos', jsonEncode(_catalogos));

        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Error downloading catalogs: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  void clear() {
    _catalogos.clear();
    notifyListeners();
  }

}
