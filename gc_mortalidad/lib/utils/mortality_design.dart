import 'package:flutter/material.dart';

import '../models/motivo_mortalidad.dart';

enum MortalityType {
  incubacion,
  transporte,
  produccion,
  despacho,
}

const String kCausaTransporteNombre = 'Mortalidad por transporte';

/// Selector manual de causa (no aplica en incubación, transporte ni Necropsia/Lab).
bool mortalityShowsCausa(MortalityType type, {String? origenAnalisis}) {
  if (type == MortalityType.incubacion || type == MortalityType.transporte) {
    return false;
  }
  if (type == MortalityType.produccion) {
    final sub = (origenAnalisis ?? '').trim().toLowerCase();
    return sub != 'necropsia' && sub != 'laboratorio';
  }
  return true;
}

/// Muestra causa en resumen y tarjetas (transporte usa causa fija).
bool mortalityShowsCausaInSummary(MortalityType type, {String? origenAnalisis}) {
  if (type == MortalityType.transporte) return true;
  return mortalityShowsCausa(type, origenAnalisis: origenAnalisis);
}

/// Texto de causa para reportes; null si no debe mostrarse etiqueta ni guion.
String? mortalityCausaLineText({
  required bool showCausa,
  String? causaNombre,
  String? causaCodigo,
}) {
  if (!showCausa) return null;
  final nom = causaNombre?.trim() ?? '';
  if (nom.isNotEmpty) return nom;
  final cod = causaCodigo?.trim() ?? '';
  return cod.isNotEmpty ? cod : null;
}

({String codigo, String nombre}) mortalityCausaTransporte(
  List<MotivoMortalidad> motivos,
) {
  for (final m in motivos) {
    final n = m.nombre.toLowerCase();
    if (n.contains('transporte') || n.contains('trasporte')) {
      return (codigo: m.codigo, nombre: m.nombre);
    }
  }
  return (codigo: kCausaTransporteNombre, nombre: kCausaTransporteNombre);
}

extension MortalityTypeExt on MortalityType {
  String get id {
    switch (this) {
      case MortalityType.incubacion:
        return 'incubacion';
      case MortalityType.transporte:
        return 'transporte';
      case MortalityType.produccion:
        return 'produccion';
      case MortalityType.despacho:
        return 'despacho';
    }
  }

  String get title {
    switch (this) {
      case MortalityType.incubacion:
        return 'Planta incubación';
      case MortalityType.transporte:
        return 'Transporte';
      case MortalityType.produccion:
        return 'Producción';
      case MortalityType.despacho:
        return 'Despacho';
    }
  }

  String get subtitle {
    switch (this) {
      case MortalityType.incubacion:
        return 'Registro en planta';
      case MortalityType.transporte:
        return 'Evento o traslado';
      case MortalityType.produccion:
        return 'Granja en producción';
      case MortalityType.despacho:
        return 'Salida de aves';
    }
  }

  String get emoji {
    switch (this) {
      case MortalityType.incubacion:
        return '🥚';
      case MortalityType.transporte:
        return '🚛';
      case MortalityType.produccion:
        return '🐔';
      case MortalityType.despacho:
        return '📦';
    }
  }

  IconData get icon {
    switch (this) {
      case MortalityType.incubacion:
        return Icons.egg_outlined;
      case MortalityType.transporte:
        return Icons.local_shipping_outlined;
      case MortalityType.produccion:
        return Icons.agriculture_outlined;
      case MortalityType.despacho:
        return Icons.inventory_2_outlined;
    }
  }

  Color get accentColor {
    switch (this) {
      case MortalityType.incubacion:
        return const Color(0xFFFFB300);
      case MortalityType.transporte:
        return const Color(0xFF42A5F5);
      case MortalityType.produccion:
        return const Color(0xFF66BB6A);
      case MortalityType.despacho:
        return const Color(0xFFFF7043);
    }
  }

  /// Gradientes estilo iconos del drawer de necropsias
  LinearGradient get iconGradient {
    switch (this) {
      case MortalityType.incubacion:
        return const LinearGradient(
          colors: [Color(0xFFFFB300), Color(0xFFFFCA28), Color(0xFFFFE082)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case MortalityType.transporte:
        return const LinearGradient(
          colors: [Color(0xFF42A5F5), Color(0xFF64B5F6), Color(0xFF90CAF9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case MortalityType.produccion:
        return const LinearGradient(
          colors: [Color(0xFF4CAF50), Color(0xFF66BB6A), Color(0xFF81C784)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case MortalityType.despacho:
        return const LinearGradient(
          colors: [Color(0xFFFF7043), Color(0xFFFF8A65), Color(0xFFFFAB91)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  static MortalityType? fromId(String? id) {
    if (id == null) return null;
    for (final t in MortalityType.values) {
      if (t.id == id) return t;
    }
    return null;
  }
}

bool mortalityVisibilityFlag(dynamic value) {
  if (value == true) return true;
  if (value is num && value != 0) return true;
  if (value is String) {
    final v = value.trim().toLowerCase();
    return v == '1' || v == 'true';
  }
  return false;
}

/// Filtra tarjetas según san_mortalidad_acceso (codigo_usuario).
List<MortalityType> mortalityTypesFromVisibility(Map<String, dynamic> vis) {
  if (vis.isEmpty || mortalityVisibilityFlag(vis['todos'])) {
    return MortalityType.values.toList();
  }
  return MortalityType.values
      .where((t) => mortalityVisibilityFlag(vis[t.id]))
      .toList();
}
