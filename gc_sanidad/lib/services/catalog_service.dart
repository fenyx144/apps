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

  List<dynamic> get laboratoriosRaw {
    final data = _catalogos['laboratorios'] as List?;
    return data ?? [];
  }

  List<dynamic> get empresasTransporteRaw {
    final data = _catalogos['emp_trans'] as List?;
    return data ?? [];
  }

  List<dynamic> get tiposMuestraRaw {
    final data = _catalogos['muestras'] as List?;
    return data ?? [];
  }

  List<dynamic> get paquetesRaw {
    final data = _catalogos['paquetes'] as List?;
    return data ?? [];
  }

  List<dynamic> get analisisRaw {
    final data = _catalogos['analisis'] as List?;
    return data ?? [];
  }

  List<dynamic> get cabecerasRaw {
    final data = _catalogos['cabeceras'] as List?;
    return data ?? [];
  }

  List<dynamic> get detallesRaw {
    final data = _catalogos['detalles'] as List?;

    return data ?? [];
  }

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
    if (_isLoading) return false;

    _isLoading = true;
    notifyListeners();

    try {
      final apiService = ApiService();
      final result = await apiService.downloadCatalogos(tablas: tablas);
      print('Download catalogos');
      print(result);
      if (result['success'] == true) {
        final nuevosDatos = result['data'] as Map<String, dynamic>;

        // Merge de datos
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
