import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import 'api_service.dart';

/// Catálogos de la app: usuarios/conempre (login y nombres) y los propios de
/// Vacuna al Agua (equipo de medición y turnos).
class CatalogService with ChangeNotifier {
  static const String _prefsKey = 'catalogos';

  Map<String, dynamic> _catalogos = {};
  Map<String, dynamic> _catalogoVacuna = {};
  bool _isLoading = false;
  bool _vacunaLoading = false;
  Future<bool>? _vacunaEnCurso;

  Map<String, dynamic> get catalogos => _catalogos;

  /// Payload de `get_catalogos_vacunaagua_movil.php` tal como llegó.
  Map<String, dynamic> get catalogoVacuna => _catalogoVacuna;

  bool get isLoading => _isLoading || _vacunaLoading;

  /// `true` cuando ya hay catálogo propio de la app guardado en el equipo.
  bool get hasCatalogos => _catalogoVacuna.isNotEmpty;

  Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_prefsKey);
      _catalogos = (data != null && data.isNotEmpty)
          ? Map<String, dynamic>.from(jsonDecode(data) as Map)
          : {};

      final vacunaRaw = prefs.getString(AppConstants.keyCatalogosVacuna);
      _catalogoVacuna = (vacunaRaw != null && vacunaRaw.isNotEmpty)
          ? Map<String, dynamic>.from(jsonDecode(vacunaRaw) as Map)
          : {};
      notifyListeners();
    } catch (e) {
      debugPrint('CatalogService: error al cargar catálogos: $e');
      _catalogos = {};
      _catalogoVacuna = {};
      notifyListeners();
    }
  }

  void clearMemory() {
    _catalogos = {};
    _catalogoVacuna = {};
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
            _catalogos = Map<String, dynamic>.from(raw);
          }
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, jsonEncode(_catalogos));
        notifyListeners();
        return _hasTablasDescargadas(tablas);
      }
      debugPrint(
        'CatalogService.downloadCatalogos falló: ${result['message'] ?? 'sin mensaje'}',
      );
    } catch (e) {
      debugPrint('CatalogService: error al descargar catálogos: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  /// Descarga los catálogos propios de Vacuna al Agua (equipo y turnos).
  /// Si ya hay una descarga en curso (p. ej. la silenciosa del dashboard) se
  /// espera su resultado. Si no, dos disparos simultáneos dejarían el catálogo
  /// viejo en memoria.
  Future<bool> downloadCatalogosVacuna() {
    return _vacunaEnCurso ??=
        _descargarVacuna().whenComplete(() => _vacunaEnCurso = null);
  }

  Future<bool> _descargarVacuna() async {
    _vacunaLoading = true;
    notifyListeners();
    try {
      final result = await ApiService().downloadCatalogosVacuna();
      if (result['success'] == true && result['data'] is Map) {
        final fetched = Map<String, dynamic>.from(result['data'] as Map);
        // Se reemplaza el catálogo completo (no se fusiona con el anterior):
        // así desaparece cualquier valor que el servidor ya no envía.
        _catalogoVacuna = fetched;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          AppConstants.keyCatalogosVacuna,
          jsonEncode(_catalogoVacuna),
        );
        notifyListeners();
        final equipos = fetched['equipos'];
        return equipos is List && equipos.isNotEmpty;
      }
      debugPrint(
        'CatalogService.downloadCatalogosVacuna falló: '
        '${result['message'] ?? 'sin mensaje'}',
      );
    } catch (e) {
      debugPrint('CatalogService: error al descargar catálogos vacuna: $e');
    } finally {
      _vacunaLoading = false;
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

  // ── Accesos tipados al catálogo de Vacuna al Agua ───────────────────────

  /// Respaldo del equipo de vacunación cuando aún no se descargó el catálogo.
  /// Debe coincidir con `equipovacunacion` y con el respaldo de
  /// `get_catalogos_vacunaagua_movil.php`, para que la tabla de equipo se vea
  /// igual antes y después de la primera descarga.
  static const List<Map<String, String>> _equiposFallback = [
    {'codigo': '1', 'descripcion': 'Probeta milimetrada'},
    {'codigo': '2', 'descripcion': 'Vaso precipitado'},
    {'codigo': '3', 'descripcion': 'Botella de vidrio milimetrada'},
    {'codigo': '4', 'descripcion': 'Termómetro'},
    {'codigo': '5', 'descripcion': 'Coller'},
    {'codigo': '6', 'descripcion': 'Otro'},
  ];

  /// Recursos del equipo de vacunación, en el orden del catálogo.
  List<Map<String, String>> get equiposVacunacion {
    final raw = _catalogoVacuna['equipos'];
    if (raw is! List || raw.isEmpty) return List.of(_equiposFallback);
    final out = <Map<String, String>>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final codigo = (item['codigo'] ?? '').toString().trim();
      final descripcion = (item['descripcion'] ?? '').toString().trim();
      if (descripcion.isEmpty && codigo.isEmpty) continue;
      out.add({
        'codigo': codigo,
        'descripcion': descripcion.isEmpty ? codigo : descripcion,
      });
    }
    return out.isEmpty ? List.of(_equiposFallback) : out;
  }

  /// `true` cuando el recurso pide descripción siempre (el «Otro» del catálogo).
  static bool esRecursoOtro(String descripcion) =>
      descripcion.trim().toLowerCase() == 'otro';

  /// Vacunas del maestro de productos (línea 003), en el orden del catálogo.
  /// Es la misma lista que usa Planificación al elegir el producto de un
  /// programa: el nombre de la vacuna sale del maestro y no se escribe a mano.
  /// Sin catálogo descargado devuelve lista vacía y el campo avisa que hay que
  /// descargar catálogos.
  List<Map<String, String>> get vacunas {
    final raw = _catalogoVacuna['vacunas'];
    if (raw is! List || raw.isEmpty) return const [];
    final out = <Map<String, String>>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final codigo = (item['codigo'] ?? '').toString().trim();
      final descripcion = (item['descripcion'] ?? '').toString().trim();
      if (codigo.isEmpty && descripcion.isEmpty) continue;
      out.add({
        'codigo': codigo,
        'descripcion': descripcion.isEmpty ? codigo : descripcion,
      });
    }
    return out;
  }

  List<String> get turnos {
    final raw = _catalogoVacuna['turnos'];
    if (raw is! List || raw.isEmpty) return const ['Dia', 'Noche'];
    final out = raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return out.isEmpty ? const ['Dia', 'Noche'] : out;
  }

  /// Nombre del usuario del sistema cuyo DNI coincide con [dni].
  /// `usuario.libtri` guarda el DNI (así lo usa el módulo de roles), y el
  /// catálogo de usuarios ya viene descargado para el login offline. Es la
  /// segunda barrera cuando la consulta en línea del documento no responde:
  /// el personal de la granja se resuelve sin conexión.
  /// Devuelve cadena vacía si el DNI no está entre los usuarios descargados.
  String nombrePorDni(String dni) {
    final buscado = dni.replaceAll(RegExp(r'\D'), '');
    if (buscado.isEmpty) return '';
    final usuarios = _catalogos['usuarios'];
    if (usuarios is! List) return '';
    for (final u in usuarios) {
      if (u is! Map) continue;
      final libtri = (u['libtri'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      if (libtri.isEmpty || libtri != buscado) continue;
      final nombre = (u['nombre'] ?? '').toString().trim();
      if (nombre.isNotEmpty) return nombre;
    }
    return '';
  }

  /// Descripción legible de un código de catálogo (p. ej. equipo `4` Termómetro).
  String descripcionDe(List<Map<String, String>> catalogo, String codigo) {
    for (final item in catalogo) {
      if (item['codigo'] == codigo) return item['descripcion'] ?? codigo;
    }
    return codigo;
  }
}
