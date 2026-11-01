import 'dart:convert';

import 'package:bioseguridad/services/catalog_service.dart';
import 'package:bioseguridad/utils/constants.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Deja el catálogo de bioseguridad tal como lo guarda la descarga.
Future<CatalogService> _conTiposFomite(List<Map<String, String>> tipos) async {
  SharedPreferences.setMockInitialValues({
    AppConstants.keyCatalogosBio: jsonEncode({'tipos': tipos}),
  });
  final catalog = CatalogService();
  await catalog.loadFromPrefs();
  return catalog;
}

List<String> _descripciones(CatalogService catalog) =>
    catalog.tiposFomites.map((t) => t['descripcion']!).toList();

void main() {
  test('tiposFomites descarta «Intrusion» aunque venga del catálogo', () async {
    final catalog = await _conTiposFomite([
      {'codigo': '1', 'descripcion': 'Intrusion'},
      {'codigo': '2', 'descripcion': 'Avistamiento'},
      {'codigo': '3', 'descripcion': 'Huella'},
      {'codigo': '4', 'descripcion': 'Muerte'},
    ]);

    expect(_descripciones(catalog), ['Avistamiento', 'Huella', 'Muerte']);
  });

  test('tiposFomites conserva el resto de tipos y su orden', () async {
    final catalog = await _conTiposFomite([
      {'codigo': '2', 'descripcion': 'Avistamiento'},
      {'codigo': '3', 'descripcion': 'Huella'},
    ]);

    expect(_descripciones(catalog), ['Avistamiento', 'Huella']);
  });

  test('tiposFomites tambien descarta la variante con tilde', () async {
    final catalog = await _conTiposFomite([
      {'codigo': '1', 'descripcion': 'Intrusión'},
      {'codigo': '2', 'descripcion': 'Avistamiento'},
    ]);

    expect(_descripciones(catalog), ['Avistamiento']);
  });

  test('sin catálogo descargado no hay tipos de fómite', () async {
    // Ya no hay listas de respaldo en el código: el catálogo sale del servidor
    // y, hasta que se descargue, el campo queda vacío (el formulario lo avisa
    // con `BioCatalogoAviso`).
    SharedPreferences.setMockInitialValues({});
    final catalog = CatalogService();
    await catalog.loadFromPrefs();

    expect(catalog.sinDescargar, isTrue);
    expect(_descripciones(catalog), isEmpty);
  });
}
