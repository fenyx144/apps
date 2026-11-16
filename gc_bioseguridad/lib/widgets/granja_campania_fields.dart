import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/storage_service.dart';
import 'evidencia_select_field.dart';
import 'granja_campania_picker.dart';

/// Resultado de elegir granja o campaña en [GranjaCampaniaFields].
class GranjaCampaniaSeleccion {
  const GranjaCampaniaSeleccion({
    required this.granja,
    required this.granjaNombre,
    required this.campania,
    required this.campanias,
    this.desdeGranja = false,
  });

  /// Código de granja de 3 dígitos.
  final String granja;

  /// Nombre de la granja tal como lo devuelve el catálogo.
  final String granjaNombre;

  /// Campaña de 3 dígitos; '' cuando la granja tiene más de una y aún no se
  /// eligió ninguna.
  final String campania;

  /// Campañas elegibles para la fecha del registro.
  final List<String> campanias;

  /// `true` cuando el cambio lo originó el campo «Granja».
  final bool desdeGranja;
}

/// Selección premarcada en formularios de reportes (cerco, garita, fómites):
/// primera granja en Mis granjas con campaña sugerida para [fechaYmd].
/// Devuelve `null` cuando no hay granja guardada, o cuando esa granja no tiene
/// campañas elegibles para la fecha: en ese caso el formulario arranca vacío,
/// como antes de configurar la granja.
GranjaCampaniaSeleccion? granjaDeTrabajoSeleccion(
  StorageService storage, {
  required String fechaYmd,
}) {
  final g3 = GranjaCampaniaPicker.normGranja(storage.getGranjaTrabajo());
  if (g3.isEmpty) return null;
  final granjas = storage.getGranjasTrabajo();
  if (granjas.isNotEmpty && !granjas.contains(g3)) return null;
  return granjaSeleccionDe(storage, g3, fechaYmd: fechaYmd);
}

/// Selección de una granja cualquiera ([granja] de 3 dígitos) con su campaña
/// sugerida para [fechaYmd]. La usa también el enlace de otra app.
GranjaCampaniaSeleccion? granjaSeleccionDe(
  StorageService storage,
  String granja, {
  required String fechaYmd,
}) {
  final g3 = GranjaCampaniaPicker.normGranja(granja);
  if (g3.isEmpty) return null;
  final sel = GranjaCampaniaPicker.seleccionDeGranja(
    proyeccion: storage.getProyeccion(),
    cencosGalpones: storage.getCencosGalpones(),
    granja3: g3,
    fechaYmd: fechaYmd,
  );
  if (sel == null) return null;
  return GranjaCampaniaSeleccion(
    granja: (sel['granja3'] ?? '').toString(),
    granjaNombre: (sel['granjaNombre'] ?? '').toString(),
    campania: (sel['campania'] ?? '').toString(),
    campanias: ((sel['campanias'] as List?) ?? [])
        .map((e) => e.toString())
        .toList(),
  );
}

/// Filtro de presencia en escaneo: granja del formulario o lista de «Mi granja».
({String granja, List<String> granjas}) alcancePresenciaGranjas(
  StorageService storage, {
  String granjaFormulario = '',
}) {
  if (granjaFormulario.trim().isNotEmpty) {
    return (granja: granjaFormulario.trim(), granjas: const []);
  }
  return (granja: '', granjas: storage.getGranjasTrabajo());
}

/// Par de campos «Granja» + «Campaña» para los formularios de bioseguridad.
/// Antes era un solo campo que abría el selector de granja y, acto seguido,
/// obligaba a elegir campaña. Ahora cada uno se toca por separado y la campaña
/// arranca con la sugerida por el catálogo para la fecha del registro, igual
/// que en la app de seguimiento de crianza. Cuando la granja tiene una sola
/// campaña elegible el campo queda bloqueado porque ya está resuelta.
class GranjaCampaniaFields extends StatelessWidget {
  const GranjaCampaniaFields({
    super.key,
    required this.fechaYmd,
    required this.granja,
    required this.campania,
    required this.campanias,
    required this.onSeleccion,
    this.granjaNombre = '',
    this.separacion = 12,
    this.flexGranja = 3,
    this.anchoCampania = 100,
    this.granjasPermitidas,
  });

  /// Fecha del registro (`yyyy-MM-dd`): de ella dependen las campañas activas.
  final String fechaYmd;

  /// Código de granja de 3 dígitos ('' si todavía no se eligió).
  final String granja;

  /// Nombre de la granja elegida (para la etiqueta del campo).
  final String granjaNombre;

  /// Campaña de 3 dígitos ('' si falta elegir).
  final String campania;

  /// Campañas elegibles para [fechaYmd].
  final List<String> campanias;

  /// Devuelve la selección completa cada vez que cambia granja o campaña.
  final ValueChanged<GranjaCampaniaSeleccion> onSeleccion;

  /// Separación horizontal entre los dos campos.
  final double separacion;

  /// Peso con que «Granja» se queda el espacio sobrante (es la que lleva el
  /// nombre, que es largo).
  final int flexGranja;

  /// Ancho fijo de «Campaña». Es de tres dígitos y no necesita más: dejarla
  /// flexible le robaba ancho a la granja, que es la que tiene texto largo.
  final double anchoCampania;

  /// Si no es null ni vacío, el selector de granja solo muestra estos códigos
  /// (p. ej. granjas de trabajo en Mis granjas).
  final List<String>? granjasPermitidas;

  /// La campaña se puede cambiar solo si hay más de una elegible: con una sola
  /// ya viene resuelta y con la granja vacía todavía no hay de dónde elegir.
  bool get _campaniaEditable => granja.isNotEmpty && campanias.length > 1;

  Future<void> _elegirGranja(BuildContext context) async {
    final storage = context.read<StorageService>();
    final proyeccion = storage.getProyeccion();
    final cencosGalpones = storage.getCencosGalpones();
    final sel = await GranjaCampaniaPicker.show(
      context,
      proyeccion: proyeccion,
      cencosGalpones: cencosGalpones,
      fechaYmd: fechaYmd,
      granjasPermitidas: granjasPermitidas,
    );
    if (sel == null) return;

    final g3 = (sel['granja3'] ?? '').toString();
    final nombre = (sel['granjaNombre'] ?? '').toString();
    final lista = ((sel['campanias'] as List?) ?? [])
        .map((e) => GranjaCampaniaPicker.padCampania(e.toString()))
        .where((c) => c.isNotEmpty)
        .toList();

    var camp = lista.length == 1 ? lista.first : '';
    if (camp.isEmpty) {
      camp = GranjaCampaniaPicker.resolveCampaniaDefaultForFecha(
            proyeccion: proyeccion,
            granja3: g3,
            fechaYmd: fechaYmd,
            campaniasDisponibles: lista,
            cencosGalpones: cencosGalpones,
          ) ??
          (lista.isNotEmpty ? lista.first : '');
    }

    onSeleccion(GranjaCampaniaSeleccion(
      granja: g3,
      granjaNombre: nombre,
      campania: camp,
      campanias: lista,
      desdeGranja: true,
    ));
  }

  Future<void> _elegirCampania(BuildContext context) async {
    final camp = await GranjaCampaniaPicker.showCampania(
      context,
      campanias: campanias,
      selected: campania,
    );
    if (camp == null || camp.isEmpty) return;
    onSeleccion(GranjaCampaniaSeleccion(
      granja: granja,
      granjaNombre: granjaNombre,
      campania: camp,
      campanias: campanias,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: flexGranja,
          child: EvidenciaSelectField(
            label: 'Granja',
            value: granja.isEmpty
                ? ''
                : GranjaCampaniaPicker.formatGranjaLabel(granja, granjaNombre),
            placeholder: 'Seleccione',
            icon: Icons.warehouse_rounded,
            // Un solo renglón: un nombre largo se corta con puntos suspensivos
            // en vez de estirar el campo y desalinear el de al lado.
            maxLines: 1,
            onTap: () => _elegirGranja(context),
          ),
        ),
        SizedBox(width: separacion),
        SizedBox(
          width: anchoCampania,
          child: EvidenciaSelectField(
            label: 'Campaña',
            value: campania.isEmpty
                ? ''
                : GranjaCampaniaPicker.padCampania(campania),
            placeholder: granja.isEmpty
                ? ''
                : (campania.isEmpty ? 'Elegir' : ''),
            icon: Icons.tag,
            showIcon: false,
            enabled: _campaniaEditable,
            onTap: _campaniaEditable ? () => _elegirCampania(context) : null,
          ),
        ),
      ],
    );
  }
}
