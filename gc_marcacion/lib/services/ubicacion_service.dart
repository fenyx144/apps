import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class UbicacionMarcacion {
  const UbicacionMarcacion({
    required this.latitud,
    required this.longitud,
    required this.direccion,
  });

  final String latitud;
  final String longitud;
  final String direccion;

  static const vacia = UbicacionMarcacion(
    latitud: '',
    longitud: '',
    direccion: '',
  );
}

class UbicacionService {
  /// Si el GPS está apagado, sugiere encenderlo y abre los ajustes.
  static Future<void> sugerirGps(BuildContext context) async {
    try {
      if (await Geolocator.isLocationServiceEnabled()) return;
    } catch (_) {
      return;
    }
    if (!context.mounted) return;
    final abrir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.location_off_rounded, size: 40),
        title: const Text('GPS apagado'),
        content: const Text(
          'Encienda la ubicación para registrar dónde se hace la marcación.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Ahora no'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.my_location_rounded),
            label: const Text('Encender GPS'),
          ),
        ],
      ),
    );
    if (abrir == true) await Geolocator.openLocationSettings();
  }
  static UbicacionMarcacion? _cache;
  static DateTime? _cacheEn;
  static bool _permisoPedido = false;
  static StreamSubscription<Position>? _sub;
  static int _usuarios = 0;
  static bool _iniciando = false;
  static Completer<void>? _esperaPos;
  static int _geoSeq = 0;

  static const _maxEdad = Duration(minutes: 10);

  /// Compatibilidad: inicia el flujo continuo.
  static void precalentar() => iniciar();

  /// Inicia (una sola vez) el flujo continuo de posicion. Con contador.
  static void iniciar() {
    _usuarios++;
    _arrancar();
  }

  /// Libera un uso; al llegar a 0 detiene el flujo.
  static void detener() {
    if (_usuarios > 0) _usuarios--;
    if (_usuarios == 0) _parar();
  }

  /// Pausa por app en segundo plano (no cambia el contador).
  static void pausar() => _parar();

  /// Reanuda al volver a primer plano si hay pantallas usandolo.
  static void reanudar() {
    if (_usuarios > 0) _arrancar();
  }

  static void _parar() {
    final s = _sub;
    _sub = null;
    s?.cancel().catchError((_) {});
  }

  static Future<void> _arrancar() async {
    if (_sub != null || _iniciando) return;
    _iniciando = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied && !_permisoPedido) {
        _permisoPedido = true;
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.denied ||
          permiso == LocationPermission.deniedForever) {
        return;
      }
      if (_usuarios == 0 || _sub != null) return;

      // Semilla inmediata con la ultima conocida.
      Geolocator.getLastKnownPosition().then((p) {
        if (p != null &&
            DateTime.now().difference(p.timestamp).abs() < _maxEdad &&
            _cache == null) {
          _guardar(p);
        }
      }).catchError((_) {});

      // Primer fix (no esperado por nadie).
      Geolocator.getCurrentPosition(
        locationSettings: _ajustes(timeLimit: const Duration(seconds: 30)),
      ).then(_guardar).catchError((_) {});

      _sub = Geolocator.getPositionStream(locationSettings: _ajustes())
          .listen(_guardar, onError: (_) {}, cancelOnError: false);
    } catch (_) {
    } finally {
      _iniciando = false;
    }
  }

  static LocationSettings _ajustes({Duration? timeLimit}) {
    try {
      return AndroidSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 10,
        intervalDuration: const Duration(seconds: 5),
        forceLocationManager: false,
        timeLimit: timeLimit,
      );
    } catch (_) {
      return LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 10,
        timeLimit: timeLimit,
      );
    }
  }

  static void _guardar(Position pos) {
    try {
      final lat = pos.latitude.toStringAsFixed(6);
      final lng = pos.longitude.toStringAsFixed(6);
      final previa = _cache;
      _cache = UbicacionMarcacion(
        latitud: lat,
        longitud: lng,
        direccion: previa?.direccion ?? '',
      );
      _cacheEn = DateTime.now();
      final c = _esperaPos;
      _esperaPos = null;
      if (c != null && !c.isCompleted) c.complete();
      _direccion(pos, lat, lng);
    } catch (_) {}
  }

  static Future<void> _direccion(Position pos, String lat, String lng) async {
    final seq = ++_geoSeq;
    try {
      final marcas = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      ).timeout(const Duration(seconds: 2));
      if (marcas.isEmpty || seq != _geoSeq) return;
      final p = marcas.first;
      var direccion = [
        p.street,
        p.subLocality,
        p.locality,
        p.administrativeArea,
      ].whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).join(', ');
      if (direccion.length > 150) direccion = direccion.substring(0, 150);
      final c = _cache;
      if (c != null && c.latitud == lat && c.longitud == lng) {
        _cache = UbicacionMarcacion(
          latitud: lat,
          longitud: lng,
          direccion: direccion,
        );
      }
    } catch (_) {}
  }

  /// Posicion en cache si tiene menos de [edad]; si no, null. Sin esperas.
  static UbicacionMarcacion? enCache({Duration edad = _maxEdad}) {
    final c = _cache;
    final en = _cacheEn;
    if (c == null || en == null) return null;
    if (DateTime.now().difference(en) > edad) return null;
    return c;
  }

  /// Ubicacion para guardar: cache al instante; si no hay, espera
  /// como maximo ~1.5 s; si no llega, vacia. Nunca lanza.
  Future<UbicacionMarcacion> actual() async {
    try {
      final c = enCache();
      if (c != null) return c;
      _arrancar();
      final espera = _esperaPos ??= Completer<void>();
      await espera.future
          .timeout(const Duration(milliseconds: 1500), onTimeout: () {});
      return enCache() ?? UbicacionMarcacion.vacia;
    } catch (_) {
      return UbicacionMarcacion.vacia;
    }
  }
}