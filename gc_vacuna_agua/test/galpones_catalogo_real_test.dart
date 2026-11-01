import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vacuna_al_agua/utils/galpones_resolver.dart';

/// Reproduce la carga de galpones con la respuesta **real** de
/// `get_cencos_galpones_movil.php` (test/fixtures/cencos_galpones_real.json).
///
/// La app resuelve los galpones offline a partir de este catálogo: si el
/// resolver no encuentra los galpones de una granja/campaña del catálogo, el
/// campo «Galpones» del registro de Vacunación aparece vacío.
void main() {
  late Map<String, dynamic> data;
  late GalponesCatalogIndices indices;

  setUpAll(() {
    final raw = File(
      'test/fixtures/cencos_galpones_real.json',
    ).readAsStringSync();
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    data = Map<String, dynamic>.from(decoded['data'] as Map);
    indices = GalponesResolver.buildIndicesFromApiData(data);
  });

  test('el catálogo real construye índices por CENCO y por granja', () {
    expect(indices.cencos, isNotEmpty);
    expect(indices.cencos.length, 24);
    expect(indices.galponesPorCenco, isNotEmpty);
    expect(indices.galponesPorGranja, isNotEmpty);
    expect(indices.totalGalpones, greaterThan(0));
  });

  test('cada CENCO del catálogo tiene sus galpones accesibles', () {
    for (final cenco in indices.cencos) {
      final cod6 = GalponesResolver.normalizarCodigoCenco(
        (cenco['codigo'] ?? '').toString(),
      );
      expect(
        indices.galponesPorCenco[cod6],
        isNotEmpty,
        reason: 'CENCO $cod6 quedó sin galpones en el índice',
      );
    }
  });

  test('resolver offline devuelve los galpones de granja + campaña', () {
    // 667066 → granja 667, campaña 066 (GJA. TUCSON C=66).
    final lista = GalponesResolver.resolveOffline(
      granjaCodigo: '667',
      campania: '066',
      galponesPorGranja: indices.galponesPorGranja,
      galponesPorCenco: indices.galponesPorCenco,
      cencosLista: indices.cencos,
    );

    final codigos = lista
        .map((g) => (g['tcodint'] ?? g['galpon'] ?? '').toString().trim())
        .where((c) => c.isNotEmpty)
        .toList();
    expect(codigos, isNotEmpty, reason: 'Sin galpones para 667/066');
    expect(codigos.length, 6);
  });

  test('resolver offline funciona aunque falte la campaña', () {
    // El formulario arranca con la campaña vacía: debe caer al respaldo por
    // granja (3 dígitos) en vez de quedarse sin galpones.
    final lista = GalponesResolver.resolveOffline(
      granjaCodigo: '667',
      campania: '',
      galponesPorGranja: indices.galponesPorGranja,
      galponesPorCenco: indices.galponesPorCenco,
      cencosLista: indices.cencos,
    );

    expect(lista, isNotEmpty, reason: 'Sin galpones para granja 667');
  });

  test('las edades se calculan desde fec_ing_min', () {
    final lista = GalponesResolver.resolveOffline(
      granjaCodigo: '667',
      campania: '066',
      galponesPorGranja: indices.galponesPorGranja,
      galponesPorCenco: indices.galponesPorCenco,
      cencosLista: indices.cencos,
    );

    final conFecha = lista.where(
      (g) => (g['fec_ing_min'] ?? '').toString().trim().isNotEmpty,
    );
    expect(
      conFecha,
      isNotEmpty,
      reason: 'Ningún galpón trae fec_ing_min: la edad no se podría calcular',
    );
  });
}
