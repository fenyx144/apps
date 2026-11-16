import 'dart:convert';

import 'package:bioseguridad/services/plan_visitas_service.dart';
import 'package:bioseguridad/services/storage_service.dart';
import 'package:bioseguridad/widgets/proveedor_dialog.dart';

/// Proveedores aprendidos en el dispositivo (planificación e ingresos).
/// No reemplaza `ccte`: complementa cuando no hay red. Sin RUC pueden repetirse
/// nombres mal escritos; la clave de deduplicación es el RUC cuando existe.
class ProveedorHistorialService {
  ProveedorHistorialService(this._storage);

  final StorageService _storage;

  static const int maxEntradas = 250;
  static const int maxResultadosBusqueda = 15;

  static String claveNombre(String nombre) {
    return nombre
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[.,\-_/]+'), ' ');
  }

  static int _pesoFuente(String fuente) {
    switch (fuente) {
      case 'ccte':
        return 4;
      case 'plan':
        return 3;
      case 'factiliza':
        return 3;
      case 'ingreso':
        return 2;
      default:
        return 1;
    }
  }

  static bool _nombrePreferible(String actual, String nuevo, String fActual, String fNuevo) {
    final pa = _pesoFuente(fActual);
    final pn = _pesoFuente(fNuevo);
    if (pn > pa) return true;
    if (pn < pa) return false;
    return nuevo.trim().length > actual.trim().length;
  }

  /// Registra o actualiza un proveedor en el historial local.
  Future<void> registrar(
    ProveedorSeleccion sel, {
    String fuente = 'manual',
  }) async {
    final lista = _cargar();
    _aplicarEnLista(lista, sel, fuente);
    _podar(lista);
    await _guardar(lista);
  }

  void _aplicarEnLista(
    List<Map<String, dynamic>> lista,
    ProveedorSeleccion sel,
    String fuente,
  ) {
    var ruc = sel.ruc.replaceAll(RegExp(r'\D'), '');
    if (ruc.length != 11) ruc = '';
    var nombre = sel.nombre.trim();
    if (ruc.isEmpty && nombre.isEmpty) return;

    final ahora = DateTime.now().toIso8601String();

    if (ruc.length == 11) {
      final idx = lista.indexWhere((e) => e['ruc'] == ruc);
      if (idx >= 0) {
        final prev = lista[idx];
        final nomPrev = (prev['nombre'] ?? '').toString();
        final fPrev = (prev['fuente'] ?? 'manual').toString();
        if (nombre.isEmpty) {
          nombre = nomPrev;
        } else if (nomPrev.isNotEmpty &&
            !_nombrePreferible(nomPrev, nombre, fPrev, fuente)) {
          nombre = nomPrev;
        }
        lista[idx] = {
          'ruc': ruc,
          'nombre': nombre,
          'fuente': _nombrePreferible(nomPrev, nombre, fPrev, fuente)
              ? fuente
              : fPrev,
          'useCount': ((prev['useCount'] ?? 0) as num).toInt() + 1,
          'lastUsedAt': ahora,
        };
        _quitarDuplicadosSinRuc(lista, nombre);
      } else {
        lista.add({
          'ruc': ruc,
          'nombre': nombre,
          'fuente': fuente,
          'useCount': 1,
          'lastUsedAt': ahora,
        });
        _quitarDuplicadosSinRuc(lista, nombre);
      }
    } else {
      final clave = claveNombre(nombre);
      if (clave.isEmpty) return;
      final idx = lista.indexWhere(
        (e) =>
            (e['ruc'] ?? '').toString().isEmpty &&
            claveNombre((e['nombre'] ?? '').toString()) == clave,
      );
      if (idx >= 0) {
        final prev = lista[idx];
        lista[idx] = {
          'ruc': '',
          'nombre': _nombrePreferible(
                (prev['nombre'] ?? '').toString(),
                nombre,
                (prev['fuente'] ?? 'manual').toString(),
                fuente,
              )
              ? nombre
              : (prev['nombre'] ?? '').toString(),
          'fuente': fuente,
          'useCount': ((prev['useCount'] ?? 0) as num).toInt() + 1,
          'lastUsedAt': ahora,
        };
      } else {
        lista.add({
          'ruc': '',
          'nombre': nombre,
          'fuente': fuente,
          'useCount': 1,
          'lastUsedAt': ahora,
        });
      }
    }
  }

  void _quitarDuplicadosSinRuc(List<Map<String, dynamic>> lista, String nombre) {
    final clave = claveNombre(nombre);
    if (clave.isEmpty) return;
    lista.removeWhere(
      (e) =>
          (e['ruc'] ?? '').toString().isEmpty &&
          claveNombre((e['nombre'] ?? '').toString()) == clave,
    );
  }

  void _podar(List<Map<String, dynamic>> lista) {
    lista.sort((a, b) {
      final ta = DateTime.tryParse((a['lastUsedAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final tb = DateTime.tryParse((b['lastUsedAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    if (lista.length > maxEntradas) {
      lista.removeRange(maxEntradas, lista.length);
    }
  }

  /// Incorpora proveedores de una descarga de planificación.
  Future<void> ingestarDesdePlan(PlanDescarga descarga) async {
    final lista = _cargar();
    for (final v in descarga.visitas) {
      final ruc = v.ruc;
      final nombre = v.razonSocial.trim();
      if (ruc.isEmpty && nombre.isEmpty) continue;
      _aplicarEnLista(
        lista,
        ProveedorSeleccion(ruc: ruc, nombre: nombre),
        'plan',
      );
    }
    _podar(lista);
    await _guardar(lista);
  }

  /// Incorpora proveedores de registros de ingreso ya guardados en el equipo.
  Future<void> ingestarDesdeRegistrosLocales() async {
    final lista = _cargar();
    for (final record in _storage.getAllRecords()) {
      if ((record['reporte'] ?? '').toString() != 'ingreso') continue;
      final reg = record['registro'];
      if (reg is! Map) continue;
      final ruc = (reg['proveedor_ruc'] ?? '').toString();
      final nombre = (reg['proveedor'] ?? '').toString();
      _aplicarEnLista(
        lista,
        ProveedorSeleccion(ruc: ruc, nombre: nombre),
        'ingreso',
      );
    }
    _podar(lista);
    await _guardar(lista);
  }

  /// Una vez: rellena el historial desde ingresos y planificación ya en el equipo.
  Future<void> ensureBootstrapped() async {
    if (_storage.getProveedorHistorialBootstrapped()) return;
    await ingestarDesdeRegistrosLocales();
    final planJson = _storage.getPlanVisitasJson();
    if (planJson != null && planJson.isNotEmpty) {
      try {
        final m = jsonDecode(planJson);
        if (m is Map<String, dynamic>) {
          await ingestarDesdePlan(PlanDescarga.fromJson(m));
        } else if (m is Map) {
          await ingestarDesdePlan(
            PlanDescarga.fromJson(Map<String, dynamic>.from(m)),
          );
        }
      } catch (_) {}
    }
    await _storage.setProveedorHistorialBootstrapped(true);
  }

  /// Búsqueda local para el diálogo (sin red).
  List<ProveedorCcteItem> buscar(String q) {
    final texto = q.trim();
    if (texto.isEmpty) return const [];

    final digits = texto.replaceAll(RegExp(r'\D'), '');
    final soloDigitos =
        digits.isNotEmpty && RegExp(r'^[\d\s.\-]+$').hasMatch(texto);
    final tieneLetras = RegExp(r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]').hasMatch(texto);

    if (texto.length < 3 && digits.length != 11) return const [];

    final lista = _cargar();
    final out = <({ProveedorCcteItem item, int useCount})>[];

    for (final row in lista) {
      final ruc = (row['ruc'] ?? '').toString();
      final nombre = (row['nombre'] ?? '').toString().trim();
      if (nombre.isEmpty && ruc.isEmpty) continue;

      var coincide = false;
      if (soloDigitos && digits.length >= 3) {
        coincide = ruc.startsWith(digits);
      }
      if (!coincide && tieneLetras && texto.length >= 3) {
        coincide = claveNombre(nombre).contains(claveNombre(texto));
      }
      if (!coincide && digits.length == 11 && ruc == digits) {
        coincide = true;
      }
      if (!coincide) continue;

      out.add((
        item: ProveedorCcteItem(
          ruc: ruc,
          razonsocial: nombre.isNotEmpty ? nombre : 'RUC $ruc',
          enDispositivo: true,
        ),
        useCount: ((row['useCount'] ?? 0) as num).toInt(),
      ));
    }

    out.sort((a, b) => b.useCount.compareTo(a.useCount));
    return [
      for (final e in out.take(maxResultadosBusqueda)) e.item,
    ];
  }

  List<Map<String, dynamic>> _cargar() {
    final raw = _storage.getProveedorHistorialJson();
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [
        for (final e in decoded)
          if (e is Map) Map<String, dynamic>.from(e),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _guardar(List<Map<String, dynamic>> lista) async {
    await _storage.saveProveedorHistorialJson(jsonEncode(lista));
  }
}
