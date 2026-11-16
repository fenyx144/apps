import 'dart:convert';

import 'package:intl/intl.dart';

import '../widgets/proveedor_dialog.dart';
import 'api_service.dart';
import 'storage_service.dart';

/// Proveedor propuesto para un grupo de DNI escaneados sin planificación.
class SugerenciaProveedor {
  const SugerenciaProveedor({
    required this.proveedor,
    required this.dnis,
    required this.desdeNomina,
  });

  final ProveedorSeleccion proveedor;

  /// DNI escaneados que pertenecen a este proveedor.
  final List<String> dnis;

  /// `true` si al menos uno figura en la nómina del proveedor (y no solo en
  /// ingresos o planificaciones anteriores).
  final bool desdeNomina;
}

/// Nómina descargada: personal activo que cada proveedor registró en el portal
/// y, para quien no figura en ninguna, el proveedor con el que vino antes.
class NominaProveedores {
  const NominaProveedores({
    this.generado = '',
    this.proveedores = const {},
    this.procesos = const {},
    this.ultimoProceso = const {},
    this.nomina = const {},
    this.historial = const {},
  });

  static const vacia = NominaProveedores();

  final String generado;

  /// RUC razón social.
  final Map<String, String> proveedores;

  /// RUC procesos asignados al proveedor en el portal.
  final Map<String, List<String>> procesos;

  /// RUC último proceso con que vino (planificación o ingreso).
  final Map<String, String> ultimoProceso;

  /// DNI RUC de los proveedores en cuya nómina figura.
  final Map<String, List<String>> nomina;

  /// DNI RUC con los que figuró en planificaciones o ingresos recientes.
  final Map<String, List<String>> historial;

  bool get estaVacia => nomina.isEmpty && historial.isEmpty;

  /// Fecha (AAAA-MM-DD) de la descarga, o '' si no hay.
  String get fecha => generado.length >= 10 ? generado.substring(0, 10) : '';

  static Map<String, List<String>> _mapaListas(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, List<String>>{};
    raw.forEach((k, v) {
      if (v is! List) return;
      final rucs = [
        for (final r in v)
          if (r.toString().trim().isNotEmpty) r.toString().trim(),
      ];
      if (rucs.isNotEmpty) out[k.toString()] = rucs;
    });
    return out;
  }

  static Map<String, String> _mapaTextos(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        if ((e.value ?? '').toString().trim().isNotEmpty)
          e.key.toString(): e.value.toString().trim(),
    };
  }

  factory NominaProveedores.fromJson(Map m) {
    return NominaProveedores(
      generado: (m['generado'] ?? '').toString(),
      proveedores: _mapaTextos(m['proveedores']),
      procesos: _mapaListas(m['procesos']),
      ultimoProceso: _mapaTextos(m['ultimoProceso']),
      nomina: _mapaListas(m['nomina']),
      historial: _mapaListas(m['historial']),
    );
  }

  Map<String, dynamic> toJson() => {
    'generado': generado,
    'proveedores': proveedores,
    'procesos': procesos,
    'ultimoProceso': ultimoProceso,
    'nomina': nomina,
    'historial': historial,
  };

  /// Proceso que se puede proponer para el proveedor: el único que tiene
  /// asignado o, si tiene varios, el último con que vino. `''` si no se sabe.
  String procesoSugerido(String ruc) {
    final lista = procesos[ruc] ?? const <String>[];
    if (lista.length == 1) return lista.first;
    final ultimo = ultimoProceso[ruc] ?? '';
    if (ultimo.isNotEmpty && (lista.isEmpty || lista.contains(ultimo))) {
      return ultimo;
    }
    return '';
  }

  /// Procesos asignados al proveedor (para elegir entre varios).
  List<String> procesosDe(String ruc) => procesos[ruc] ?? const [];

  /// Clave del documento igual que en el servidor (DNI de 8 dígitos o CEE).
  static String claveDocumento(String raw) {
    var t = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (RegExp(r'^\d{10}$').hasMatch(t)) t = t.substring(0, 9);
    return t;
  }

  ProveedorSeleccion proveedorDe(String ruc) =>
      ProveedorSeleccion(ruc: ruc, nombre: proveedores[ruc] ?? '');

  /// Proveedores de los [dnis], el que agrupa más personas primero (a
  /// igualdad, el que viene de la nómina).
  /// [preferir]: proveedores de las visitas planificadas en pantalla. Quien
  /// figura en su nómina y además en la de otro se cuenta solo para ellos
  /// (trabaja para varios proveedores).
  List<SugerenciaProveedor> sugerir(
    Iterable<String> dnis, {
    Set<String> preferir = const {},
  }) {
    final porRuc = <String, List<String>>{};
    final conNomina = <String>{};
    for (final dni in dnis) {
      final k = claveDocumento(dni);
      if (k.isEmpty) continue;
      final deNomina = nomina[k];
      var rucs = deNomina ?? historial[k] ?? const <String>[];
      final preferidos = rucs.where(preferir.contains).toList();
      if (preferidos.isNotEmpty) rucs = preferidos;
      for (final ruc in rucs) {
        final lista = porRuc.putIfAbsent(ruc, () => []);
        if (!lista.contains(dni)) lista.add(dni);
        if (deNomina != null) conNomina.add(ruc);
      }
    }
    final out = [
      for (final e in porRuc.entries)
        SugerenciaProveedor(
          proveedor: proveedorDe(e.key),
          dnis: e.value,
          desdeNomina: conNomina.contains(e.key),
        ),
    ];
    out.sort((a, b) {
      final c = b.dnis.length.compareTo(a.dnis.length);
      if (c != 0) return c;
      if (a.desdeNomina != b.desdeNomina) return a.desdeNomina ? -1 : 1;
      return a.proveedor.nombre.compareTo(b.proveedor.nombre);
    });
    return out;
  }
}

class NominaProveedorService {
  NominaProveedorService({ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;

  static String? _crudoCache;
  static NominaProveedores _cache = NominaProveedores.vacia;

  static NominaProveedores local(StorageService storage) {
    final s = storage.getNominaProveedoresJson();
    if (s == null || s.isEmpty) return NominaProveedores.vacia;
    if (identical(s, _crudoCache) || s == _crudoCache) return _cache;
    try {
      final m = jsonDecode(s);
      _cache = m is Map
          ? NominaProveedores.fromJson(m)
          : NominaProveedores.vacia;
    } catch (_) {
      _cache = NominaProveedores.vacia;
    }
    _crudoCache = s;
    return _cache;
  }

  /// ¿Conviene bajarla otra vez? (nunca descargada o no es de hoy).
  static bool desactualizada(StorageService storage) =>
      local(storage).fecha != DateFormat('yyyy-MM-dd').format(DateTime.now());

  /// Descarga y reemplaza la nómina guardada. `false` sin tocar lo guardado si
  /// no hay red o el servidor no la tiene.
  Future<bool> descargar(StorageService storage) async {
    final data = await _api.descargarNominaProveedores();
    if (data == null) return false;
    final nom = NominaProveedores.fromJson(data);
    await storage.saveNominaProveedoresJson(jsonEncode(nom.toJson()));
    return true;
  }
}
