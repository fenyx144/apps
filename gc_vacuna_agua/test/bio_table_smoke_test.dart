import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vacuna_al_agua/widgets/bio_table.dart';

void main() {
  testWidgets('BioTable se construye dentro de SingleChildScrollView', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BioTable(
              caption: 'Verificación del tablero',
              columns: const [
                BioColumn('Componente', width: 122, align: TextAlign.left),
                BioColumn('STD', width: 74),
                BioColumn('L1', width: 178),
              ],
              rowCount: 2,
              rowBuilder: (context, index) => const [
                BioText('Cerco Operativo', align: TextAlign.left),
                BioText('>11'),
                BioSwitchFallo(value: false, onChanged: null),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('switch + observación conviven en la misma celda', (
    tester,
  ) async {
    // Es el caso de la tabla de cerco: el campo de texto queda dentro de una
    // fila con switch dentro de una celda de ancho fijo y de la IntrinsicHeight
    // de BioTable.
    final controllers = [TextEditingController(), TextEditingController()];
    addTearDown(() {
      for (final c in controllers) {
        c.dispose();
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BioTable(
              caption: 'Verificación del tablero',
              columns: const [
                BioColumn('Componente', width: 122, align: TextAlign.left),
                BioColumn('STD', width: 74),
                BioColumn('L1 · ¿Falló?', width: 178),
                BioColumn('L2 · ¿Falló?', width: 178),
              ],
              rowCount: 2,
              rowBuilder: (context, index) => [
                const BioText('Cerco Operativo', align: TextAlign.left),
                const BioText('>11'),
                BioSwitchObs(
                  value: index == 0,
                  onChanged: (_) {},
                  controller: controllers[index],
                ),
                BioSwitchObs(
                  value: false,
                  onChanged: (_) {},
                  controller: controllers[index],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('SI'), findsOneWidget);
    expect(find.text('NO'), findsNWidgets(3));
  });

  testWidgets('voltaje y batería escriben la observación sin falla', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BioSwitchObs(
            value: false,
            onChanged: (_) {},
            controller: controller,
            obsSiempreActiva: true,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(find.text('Obs'), findsOneWidget);
  });

  testWidgets('las demás métricas solo habilitan la observación al fallar', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BioSwitchObs(
            value: false,
            onChanged: (_) {},
            controller: controller,
          ),
        ),
      ),
    );

    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('una columna con flex estira la tabla hasta el ancho disponible', (
    tester,
  ) async {
    // Caso de la tabla de DNIs del control de ingreso: el renglón del
    // documento es flexible y la columna de quitar queda fija, así que la
    // tabla debe llegar al borde en vez de dejar un hueco a la derecha.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: BioTable(
                columns: const [
                  BioColumn('DNI', width: 220, align: TextAlign.left, flex: 1),
                  BioColumn('', width: 44),
                ],
                rowCount: 1,
                rowBuilder: (context, index) => const [
                  BioText('12345678', align: TextAlign.left),
                  SizedBox.shrink(),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final celdaDni = find.ancestor(
      of: find.text('DNI'),
      matching: find.byType(BioTableCell),
    );
    // 400 de ancho menos los 44 de la columna fija.
    expect(tester.getSize(celdaDni).width, 356);

    // La columna de quitar conserva su ancho declarado: los dos encabezados
    // siguen sumando exactamente el ancho de la tabla.
    final cabeceras = find.descendant(
      of: find.byType(BioTable),
      matching: find.byType(BioTableCell),
    );
    expect(tester.getSize(cabeceras.at(1)).width, 44);
  });
}
