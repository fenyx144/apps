import 'dart:convert';

import 'package:bioseguridad/services/catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Carga el catálogo de usuarios como lo deja la descarga de catálogos.
Future<CatalogService> _catalogoCon(List<Map<String, String>> usuarios) async {
  SharedPreferences.setMockInitialValues({
    'catalogos': jsonEncode({'usuarios': usuarios}),
  });
  final catalog = CatalogService();
  await catalog.loadFromPrefs();
  return catalog;
}

void main() {
  test('nombrePorDni resuelve por el DNI guardado en libtri', () async {
    final catalog = await _catalogoCon([
      {'codigo': 'JQUISPE', 'nombre': 'Juan Quispe Ramos', 'libtri': '45678912'},
      {'codigo': 'MLOPEZ', 'nombre': 'María López Díaz', 'libtri': '12345678'},
    ]);

    expect(catalog.nombrePorDni('12345678'), 'María López Díaz');
    expect(catalog.nombrePorDni('45678912'), 'Juan Quispe Ramos');
  });

  test('nombrePorDni tolera separadores en el DNI consultado', () async {
    final catalog = await _catalogoCon([
      {'codigo': 'MLOPEZ', 'nombre': 'María López Díaz', 'libtri': '12345678'},
    ]);

    expect(catalog.nombrePorDni('12-345.678'), 'María López Díaz');
    expect(catalog.nombrePorDni(' 12345678 '), 'María López Díaz');
  });

  test('nombrePorDni devuelve vacío si el DNI no es de un usuario', () async {
    final catalog = await _catalogoCon([
      {'codigo': 'MLOPEZ', 'nombre': 'María López Díaz', 'libtri': '12345678'},
    ]);

    expect(catalog.nombrePorDni('99999999'), '');
    expect(catalog.nombrePorDni(''), '');
  });

  test('nombrePorDni ignora usuarios sin libtri o sin nombre', () async {
    final catalog = await _catalogoCon([
      {'codigo': 'SINDNI', 'nombre': 'Sin Documento', 'libtri': ''},
      {'codigo': 'SINNOM', 'nombre': '', 'libtri': '87654321'},
    ]);

    expect(catalog.nombrePorDni('87654321'), '');
    expect(catalog.nombrePorDni('00000000'), '');
  });

  test('sin catálogo descargado nombrePorDni no falla', () async {
    SharedPreferences.setMockInitialValues({});
    final catalog = CatalogService();
    await catalog.loadFromPrefs();

    expect(catalog.nombrePorDni('12345678'), '');
  });
}
