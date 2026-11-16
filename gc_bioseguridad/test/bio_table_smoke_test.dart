import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bioseguridad/utils/app_theme.dart';
import 'package:bioseguridad/utils/constants.dart';
import 'package:bioseguridad/utils/theme_colors.dart';
import 'package:bioseguridad/widgets/bio_table.dart';

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

  testWidgets('el campo de observación dibuja su línea para escribir', (
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

    // En una celda sin bordes el campo vacío se lee como una raya; la línea de
    // abajo dice que ahí se escribe, y tiene que verse sin tocar el campo.
    final campo = tester.widget<TextField>(find.byType(TextField));
    expect(campo.decoration?.enabledBorder, isA<UnderlineInputBorder>());
    expect(campo.decoration?.focusedBorder, isA<UnderlineInputBorder>());

    // El tenue del tema dejaba una raya de 1 px que no se distinguía de la
    // celda: se leía recién al tocar el campo, cuando el foco la pintaba azul.
    final linea = campo.decoration!.enabledBorder! as UnderlineInputBorder;
    final muted = tester.element(find.byType(TextField)).textThemeMuted;
    expect(linea.borderSide.color, isNot(muted));
    expect(linea.borderSide.color, AppColors.primary.withValues(alpha: 0.65));
    expect(linea.borderSide.width, greaterThan(1));
  });

  testWidgets('la línea de la observación se ve con el campo apagado', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    // Sin `obsSiempreActiva` (una celda que arranca apagada) la línea tiene que
    // estar igual: si no, la celda queda como un «—» suelto y el equipo no ve
    // dónde va la observación hasta prender el interruptor.
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

    final decoration = tester
        .widget<TextField>(find.byType(TextField))
        .decoration!;
    expect(decoration.disabledBorder, isA<UnderlineInputBorder>());
    expect(
      (decoration.disabledBorder! as UnderlineInputBorder).borderSide.color,
      AppColors.primary.withValues(alpha: 0.65),
    );
  });

  testWidgets('en modo oscuro las filas van en gris y el texto se lee', (
    tester,
  ) async {
    // La tabla nació blanca (app Android antigua); sobre el fondo oscuro eso
    // dejaba una cuadrícula deslumbrante.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: BioTable(
            columns: const [
              BioColumn('Componente', width: 122, align: TextAlign.left),
              BioColumn('STD', width: 74),
            ],
            rowCount: 2,
            rowBuilder: (context, index) => [
              const BioText('Cerco Operativo', align: TextAlign.left),
              const BioText('>11'),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    // La celda del componente (primera columna de la primera fila de datos).
    final celda = find
        .ancestor(
          of: find.text('Cerco Operativo'),
          matching: find.byType(BioTableCell),
        )
        .first;
    final fondo = tester
        .widget<Container>(
          find.descendant(of: celda, matching: find.byType(Container)).first,
        )
        .decoration;
    final color = (fondo as BoxDecoration).color;

    expect(color, AppColors.darkTableRow);
    expect(color, isNot(Colors.white));
    // Y el texto sobre ese fondo sale del tema, no del gris oscuro del modo
    // claro (que acá quedaría ilegible).
    expect(
      tester.widget<Text>(find.text('Cerco Operativo').first).style?.color,
      AppColors.darkTextPrimary,
    );
  });

  testWidgets('una columna con flex estira la tabla hasta el ancho disponible', (
    tester,
  ) async { // Caso de la tabla de DNIs del control de ingreso: el renglón del
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
