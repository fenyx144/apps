import 'package:flutter/foundation.dart';
import '../models/resultado_analisis_model.dart';
import '../services/resultado_analisis_service.dart';

class ResultadoAnalisisController extends ChangeNotifier {
  List<EnvioGrupo> _grupos = [];
  int _currentPage = 1;
  int _totalPages = 1;
  bool _isLoading = false;
  bool _hasMore = true;
  String _filtroEstado = 'todos';
  String _busqueda = '';

  List<EnvioGrupo> get grupos => _grupos;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;
  String get filtroEstado => _filtroEstado;
  String get busqueda => _busqueda;

  Future<void> cargarGrupos({bool limpiar = false}) async {
    if (_isLoading && !limpiar) return;
    if (!limpiar && !_hasMore) return;

    _isLoading = true;
    notifyListeners();

    try {
      final response = await ResultadoAnalisisService.fetchGrupos(
        page: limpiar ? 1 : _currentPage,
        estado: _filtroEstado,
        query: _busqueda,
      );

      if (limpiar) {
        _grupos.clear();
        _currentPage = 1;
      }

      final nuevos = response['grupos'] as List<EnvioGrupo>;
      _grupos.addAll(nuevos);

      _totalPages = response['totalPages'] ?? 1;
      _hasMore = _currentPage < _totalPages;

      if (!limpiar) _currentPage++;
    } catch (e) {
      // Opcional: mostrar error
      debugPrint('Error al cargar grupos: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setFiltro(String estado) {
    if (_filtroEstado == estado) return;
    _filtroEstado = estado;
    _resetYRecargar();
  }

  void setBusqueda(String query) {
    _busqueda = query;
    _resetYRecargar();
  }

  void _resetYRecargar() {
    _currentPage = 1;
    _hasMore = true;
    cargarGrupos(limpiar: true);
  }
}
