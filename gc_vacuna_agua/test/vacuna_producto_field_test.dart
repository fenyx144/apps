import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vacuna_al_agua/widgets/vacuna_producto_field.dart';

/// El nombre de la vacuna sale del maestro de productos (línea 003 de `mitm`),
/// no de un campo libre: estos casos fijan que el campo no deje escribir a mano
/// y que el buscador encuentre por nombre y por código.
void main() {
  const vacunas = <Map<String, String>>[
    {'codigo': '003001', 'descripcion': 'Newcastle + Bronquitis'},
    {'codigo': '003002', 'descripcion': 'Gumboro'},
    {'codigo': '003003', 'descripcion': 'Viruela Aviar'},
  ];

  /// Monta el campo suelto y devuelve lo que va eligiendo el usuario.
  Future<List<String>> montar(
    WidgetTester tester, {
    List<Map<String, String>>? options,
    String value = '',
  }) async {
    final elegidas = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VacunaProductoField(
            value: value,
            options: options ?? vacunas,
            onSelected: elegidas.add,
          ),
        ),
      ),
    );
    return elegidas;
  }

  testWidgets('sin elegir muestra el marcador de posición y la etiqueta', (
    tester,
  ) async {
    await montar(tester);
    expect(find.text('Nombre de vacuna'), findsOneWidget);
    expect(find.text('Seleccione'), findsOneWidget);
  });

  testWidgets('con una vacuna elegida muestra su descripción', (tester) async {
    await montar(tester, value: 'Gumboro');
    expect(find.text('Gumboro'), findsOneWidget);
    expect(find.text('Seleccione'), findsNothing);
  });

  testWidgets('sin catálogo avisa que hay que descargarlo', (tester) async {
    await montar(tester, options: const []);

    await tester.tap(find.byType(VacunaProductoField));
    await tester.pumpAndSettle();

    expect(find.textContaining('No hay vacunas en el catálogo'), findsOneWidget);
    // No se abre el buscador: no hay nada que buscar.
    expect(find.byType(TextField), findsNothing);

    // El aviso es un overlay con temporizador propio: se deja consumir para no
    // terminar la prueba con temporizadores vivos.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('el buscador acota por descripción y devuelve lo elegido', (
    tester,
  ) async {
    final elegidas = await montar(tester);

    await tester.tap(find.byType(VacunaProductoField));
    await tester.pumpAndSettle();

    // Arranca con el catálogo completo.
    expect(find.text('Newcastle + Bronquitis'), findsOneWidget);
    expect(find.text('Gumboro'), findsOneWidget);
    expect(find.text('Viruela Aviar'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'gumb');
    await tester.pumpAndSettle();

    expect(find.text('Gumboro'), findsOneWidget);
    expect(find.text('Newcastle + Bronquitis'), findsNothing);

    await tester.tap(find.text('Gumboro'));
    await tester.pumpAndSettle();

    expect(elegidas, ['Gumboro']);
  });

  testWidgets('también busca por código de producto', (tester) async {
    await montar(tester);

    await tester.tap(find.byType(VacunaProductoField));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '003003');
    await tester.pumpAndSettle();

    expect(find.text('Viruela Aviar'), findsOneWidget);
    expect(find.text('Gumboro'), findsNothing);
  });

  testWidgets('sin resultados lo dice en vez de quedar vacío', (tester) async {
    await montar(tester);

    await tester.tap(find.byType(VacunaProductoField));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();

    expect(find.text('Sin resultados'), findsOneWidget);
  });
}
