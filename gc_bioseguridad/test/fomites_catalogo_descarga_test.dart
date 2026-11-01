import 'dart:convert';

import 'package:bioseguridad/screens/register_fomites_screen.dart';
import 'package:bioseguridad/services/catalog_service.dart';
import 'package:bioseguridad/services/storage_service.dart';
import 'package:bioseguridad/utils/constants.dart';
import 'package:bioseguridad/widgets/bio_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _descargar(
  WidgetTester tester,
  CatalogService catalog,
  Map<String, Object> bio,
) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(AppConstants.keyCatalogosBio, jsonEncode(bio));
  await catalog.loadFromPrefs();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('un depredador nuevo del catálogo aparece sin reabrir fómites', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      AppConstants.keyCatalogosBio: jsonEncode({
        'depredadores': ['Zorro', 'Perro'],
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final catalog = CatalogService();
    await catalog.loadFromPrefs();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => StorageService(prefs)),
          ChangeNotifierProvider.value(value: catalog),
        ],
        child: const MaterialApp(home: RegisterFomitesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Zorro'), findsOneWidget);
    expect(find.text('Puma'), findsNothing);

    await _descargar(tester, catalog, {
      'depredadores': ['Zorro', 'Perro', 'Puma'],
    });

    expect(find.text('Puma'), findsOneWidget);
    expect(find.text('Zorro'), findsOneWidget);
  });

  test('procesosFomites descarta «Despacho» de un catálogo anterior', () async {
    SharedPreferences.setMockInitialValues({
      AppConstants.keyCatalogosBio: jsonEncode({
        'procesos': [
          {'codigo': '1', 'descripcion': 'Crianza'},
          {'codigo': '4', 'descripcion': 'Despacho'},
          {'codigo': '2', 'descripcion': 'Limpieza'},
        ],
      }),
    });
    final catalog = CatalogService();
    await catalog.loadFromPrefs();
    expect(
      catalog.procesosFomites.map((p) => p['descripcion']).toList(),
      ['Crianza', 'Limpieza'],
    );
  });

  testWidgets('la tabla de fómites acorta Fómite, Tipo y Cantidad', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      AppConstants.keyCatalogosBio: jsonEncode({
        'depredadores': ['Zorro', 'Perro'],
      }),
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => StorageService(prefs)),
          ChangeNotifierProvider(create: (_) => CatalogService()),
        ],
        child: const MaterialApp(home: RegisterFomitesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final tabla = tester.widget<BioTable>(find.byType(BioTable).first);
    final anchos = {for (final c in tabla.columns) c.label: c.width};

    // Fómite, Tipo y Cantidad iban anchas para lo que muestran (un nombre, una
    // palabra y hasta cuatro dígitos) y empujaban «Hora» y «D. del cerco» fuera
    // de la pantalla del teléfono.
    expect(anchos['Fómite'], 96);
    expect(anchos['Tipo'], 104);
    expect(anchos['Cant.'], 64);
    expect(find.text('CANT.'), findsOneWidget);

    // Con esos anchos los textos siguen entrando (Puma/Avistamiento/9999) y en
    // un teléfono de 360 la tabla se desplaza sin romper el layout.
    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('procesosFomites corrige «Descanzo» del catálogo del servidor', () async {
    // La palabra venía con z en `procesofomites` (la fila del código 3) y así
    // quedó en 39 registros históricos: mientras esa base no corra la migración
    // el selector mostraba la errata.
    SharedPreferences.setMockInitialValues({
      AppConstants.keyCatalogosBio: jsonEncode({
        'procesos': [
          {'codigo': '1', 'descripcion': 'Crianza'},
          {'codigo': '2', 'descripcion': 'Limpieza'},
          {'codigo': '3', 'descripcion': 'Descanzo'},
        ],
      }),
    });
    final catalog = CatalogService();
    await catalog.loadFromPrefs();
    expect(
      catalog.procesosFomites.map((p) => p['descripcion']).toList(),
      ['Crianza', 'Limpieza', 'Descanso'],
    );
  });

  test('procesosFomites respeta el catálogo ya corregido y su código', () async {
    SharedPreferences.setMockInitialValues({
      AppConstants.keyCatalogosBio: jsonEncode({
        'procesos': [
          {'codigo': '3', 'descripcion': 'Descanso'},
          {'codigo': '5', 'descripcion': 'Otro proceso'},
        ],
      }),
    });
    final catalog = CatalogService();
    await catalog.loadFromPrefs();
    expect(catalog.procesosFomites, [
      {'codigo': '3', 'descripcion': 'Descanso'},
      {'codigo': '5', 'descripcion': 'Otro proceso'},
    ]);
  });

  test('la descarga reemplaza el catálogo entero, no lo fusiona', () async {
    // Un catálogo viejo en el equipo: opciones que el servidor ya no envía.
    SharedPreferences.setMockInitialValues({
      AppConstants.keyCatalogosBio: jsonEncode({
        'referencias': [
          {'codigo': '9', 'descripcion': 'Referencia vieja'},
        ],
        'tipos': [
          {'codigo': '9', 'descripcion': 'Tipo viejo'},
        ],
        'procesos': [
          {'codigo': '4', 'descripcion': 'Despacho'},
          {'codigo': '5', 'descripcion': 'Proceso viejo'},
        ],
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final catalog = CatalogService();
    await catalog.loadFromPrefs();
    expect(
      catalog.procesosFomites.map((p) => p['descripcion']),
      ['Proceso viejo'],
    );

    // Lo que deja una descarga: se guarda el payload del servidor y se recarga.
    await prefs.setString(
      AppConstants.keyCatalogosBio,
      jsonEncode({
        'referencias': [
          {'codigo': '1', 'descripcion': 'Garita'},
        ],
        'tipos': [
          {'codigo': '3', 'descripcion': 'Huella'},
        ],
        'procesos': [
          {'codigo': '1', 'descripcion': 'Crianza'},
          {'codigo': '2', 'descripcion': 'Limpieza'},
        ],
      }),
    );
    await catalog.loadFromPrefs();

    // Ninguna lista conserva valores del catálogo anterior: el mismo reemplazo
    // vale para referencias, tipos, procesos, instalaciones y los demás.
    expect(
      catalog.procesosFomites.map((p) => p['descripcion']),
      ['Crianza', 'Limpieza'],
      reason: 'las opciones viejas del proceso desaparecen',
    );
    expect(
      catalog.tiposFomites.map((t) => t['descripcion']),
      ['Huella'],
    );
    expect(
      catalog.referencias.map((r) => r['descripcion']),
      ['Garita'],
    );
  });

  test('un catálogo a medias no reemplaza al anterior', () {
    Map<String, Object> base() => {
      'referencias': [
        {'codigo': '1', 'descripcion': 'Garita'},
      ],
      'tipos': [
        {'codigo': '3', 'descripcion': 'Huella'},
      ],
      'procesos': [
        {'codigo': '1', 'descripcion': 'Crianza'},
      ],
      'instalaciones': [
        {'codigo': '1', 'descripcion': 'Garita'},
      ],
    };

    expect(CatalogService.validarCatalogoBio(base()), isNull);

    // Sin procesos (o con la lista vacía) el formulario no tendría qué ofrecer:
    // se conserva el catálogo anterior y la descarga se reporta fallida.
    final sinProcesos = base()..['procesos'] = const <Object>[];
    expect(CatalogService.validarCatalogoBio(sinProcesos), 'procesos');

    final sinInstalaciones = base()..remove('instalaciones');
    expect(CatalogService.validarCatalogoBio(sinInstalaciones), 'instalaciones');
  });
}
