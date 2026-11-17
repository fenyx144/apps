import 'package:bioseguridad/screens/bio_empresa/bio_almacen_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('consumo cabe en pantalla chica con teclado', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final insumos = [
      for (var i = 1; i <= 8; i++)
        {
          'id': i,
          'nombre': 'Desinfectante de amonio cuaternario de nombre largo $i',
        },
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 480),
            viewInsets: EdgeInsets.only(bottom: 240),
          ),
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (_) => AlmacenMovimientoDialog(
                      titulo: 'Consumo',
                      etiquetaItem: 'Insumo',
                      items: insumos,
                      inicial: 1,
                      pideTrabajador: false,
                      trabajadores: const [],
                      dniInicial: '',
                      nombreInicial: '',
                    ),
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Consumo'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Cantidad'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Cantidad'), '3');
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
