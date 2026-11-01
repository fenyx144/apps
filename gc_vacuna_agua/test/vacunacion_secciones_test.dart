import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vacuna_al_agua/widgets/bio_table.dart';
import 'package:vacuna_al_agua/widgets/vacunacion_secciones.dart';

/// Monta una sección dentro de un scroll, como vive en la pantalla real: la
/// tabla necesita altura acotada o [IntrinsicHeight] falla.
Future<void> montar(WidgetTester tester, Widget hijo) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: hijo),
      ),
    ),
  );
}

/// Escribe [texto] en la celda número [indice] de la sección.
Future<void> escribir(WidgetTester tester, int indice, String texto) async {
  await tester.enterText(find.byType(TextField).at(indice), texto);
  await tester.pump();
}

/// Elige una hora en una celda de hora (las que muestran `--:--`).
///
/// Entra por el teclado del diálogo, que es la vía determinista: las listas
/// abren en la hora actual y el resultado dependería de cuándo se corra.
Future<void> elegirHora(WidgetTester tester, int indice, String hora) async {
  await tester.tap(find.text('--:--').at(indice));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.keyboard_alt_outlined));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    ),
    hora,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Aceptar'));
  await tester.pumpAndSettle();
}

void main() {
  group('BioTable con encabezado agrupado', () {
    testWidgets('titula el tramo de columnas y respeta los anchos', (
      tester,
    ) async {      await montar(
        tester,
        BioTable(
          groups: const [
            BioColGroup('Pollos evaluados', desde: 1, hasta: 2),
          ],
          columns: const [
            BioColumn('Galpón', width: 66),
            BioColumn('Macho', width: 70),
            BioColumn('hembra', width: 70),
          ],
          rowCount: 1,
          rowBuilder: (context, _) => const [
            BioText('1'),
            BioText('50'),
            BioText('50'),
          ],
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('POLLOS EVALUADOS'), findsOneWidget);

      // El grupo abarca dos columnas: su celda mide la suma de las dos.
      final grupo = find.ancestor(
        of: find.text('POLLOS EVALUADOS'),
        matching: find.byType(BioTableCell),
      );
      expect(tester.getSize(grupo).width, 140);

      // La columna que no está en ningún grupo lleva una celda vacía del mismo
      // ancho, para que los encabezados sigan alineados con las filas.
      final vacia = find.ancestor(
        of: find.text('GALPÓN'),
        matching: find.byType(BioTableCell),
      );
      expect(tester.getSize(vacia).width, 66);
    });
  });

  group('BioTable estira al ancho disponible', () {
    /// Ancho de pantalla que deja la tabla sin llegar al borde por sí sola.
    void pantalla(WidgetTester tester, double ancho) {
      tester.view.physicalSize = Size(ancho, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('con expandir, la tabla llega al borde de la pantalla', (
      tester,
    ) async {
      pantalla(tester, 400);

      await montar(
        tester,
        BioTable(
          expandir: true,
          columns: const [
            BioColumn('Descripción', width: 216, align: TextAlign.left),
            BioColumn('¿Operativo?', width: 96),
          ],
          rowCount: 1,
          rowBuilder: (context, _) => const [BioText('Fuga de agua'), BioText('Sí')],
        ),
      );

      expect(tester.takeException(), isNull);
      // 400 de pantalla menos los 16+16 de relleno del scroll.
      const disponible = 368.0;
      final descripcion = find.ancestor(
        of: find.text('DESCRIPCIÓN'),
        matching: find.byType(BioTableCell),
      );
      final operativo = find.ancestor(
        of: find.text('¿OPERATIVO?'),
        matching: find.byType(BioTableCell),
      );
      // Las dos celdas juntas cubren el ancho y ninguna queda con el sobrante.
      expect(
        tester.getSize(descripcion).width + tester.getSize(operativo).width,
        disponible,
      );
      // El sobrante se reparte en proporción al ancho declarado: la columna
      // ancha se lleva la mayor parte.
      expect(tester.getSize(descripcion).width, greaterThan(216));
      expect(tester.getSize(operativo).width, greaterThan(96));
      expect(
        tester.getSize(descripcion).width,
        greaterThan(tester.getSize(operativo).width),
      );
    });

    testWidgets('sin expandir, la tabla conserva sus anchos declarados', (
      tester,
    ) async {
      pantalla(tester, 400);

      await montar(
        tester,
        BioTable(
          columns: const [
            BioColumn('Descripción', width: 216, align: TextAlign.left),
            BioColumn('¿Operativo?', width: 96),
          ],
          rowCount: 1,
          rowBuilder: (context, _) => const [BioText('Fuga de agua'), BioText('Sí')],
        ),
      );

      final descripcion = find.ancestor(
        of: find.text('DESCRIPCIÓN'),
        matching: find.byType(BioTableCell),
      );
      expect(tester.getSize(descripcion).width, 216);
    });

    testWidgets('una tabla más ancha que la pantalla se sigue desplazando', (
      tester,
    ) async {
      pantalla(tester, 400);

      // Es el caso de la evaluación de eficiencia: nueve columnas que no
      // entran, así que el sobrante es negativo y expandir no tiene nada que
      // repartir.
      await montar(
        tester,
        const EvaluacionEficienciaSection(galpones: ['1', '2']),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(BioTable), findsOneWidget);
    });
  });

  group('Tiempo de sedeó', () {
    testWidgets('dibuja una columna por galpón elegido', (tester) async {
      await montar(
        tester,
        const TiempoSedeoSection(galpones: ['1', '2']),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('GALPÓN 1'), findsOneWidget);
      expect(find.text('GALPÓN 2'), findsOneWidget);
      expect(find.text('--:--'), findsNWidgets(2));
    });

    testWidgets('sin galpones pide elegirlos en vez de mostrar la tabla', (
      tester,
    ) async {
      await montar(tester, const TiempoSedeoSection(galpones: []));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Seleccione los galpones'), findsOneWidget);
      expect(find.byType(BioTable), findsNothing);
    });

    testWidgets('la hora elegida queda en la celda del galpón', (
      tester,
    ) async {
      await montar(tester, const TiempoSedeoSection(galpones: ['1']));
      await elegirHora(tester, 0, '0800');

      expect(find.text('08:00'), findsOneWidget);
    });
  });

  group('Verificación de bebederos', () {
    testWidgets('muestra los dos bloques con un sí/no por ítem', (
      tester,
    ) async {
      await montar(tester, const VerificacionBebederosSection());

      expect(tester.takeException(), isNull);
      expect(
        find.text(
          'OPERATIVIDAD DE LAS LLAVES DE MANEJO DE AGUA EN MESA DE CONTROL',
        ),
        findsOneWidget,
      );
      expect(
        find.text('OPERATIVIDAD DE LAS LÍNEAS DE BEBEDERO EN GALPÓN'),
        findsOneWidget,
      );
      expect(find.text('Fuga de agua en las llaves de manejo'), findsOneWidget);
      expect(
        find.text('Inoperatividad de los reguladores de agua'),
        findsOneWidget,
      );
      // Dos bloques de seis ítems: SI/NO (NO en verde por defecto).
      expect(find.byType(BioSwitchFallo), findsNWidgets(12));
      expect(find.text('NO'), findsNWidgets(12));
    });
  });

  group('Preparación de solución vacunal', () {
    testWidgets('calcula la cantidad de agua con las dos lecturas', (
      tester,
    ) async {
      await montar(
        tester,
        const PreparacionSolucionSection(galpones: ['1'], edad: 21),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Cantidad de agua (m3)'), findsOneWidget);

      // Con un solo galpón los dos primeros campos de la tabla son su lectura
      // inicial y su lectura final.
      await escribir(tester, 0, '100');
      await escribir(tester, 1, '122');

      // 122 - 100, sin decimales de más.
      expect(find.text('22'), findsOneWidget);
    });

    testWidgets('en cada galpón la cantidad de agua sale de sus lecturas', (
      tester,
    ) async {
      await montar(
        tester,
        const PreparacionSolucionSection(galpones: ['1', '2'], edad: 21),
      );

      // El galpón 1 ocupa la primera columna de cada renglón y el 2 la segunda:
      // iniciales en los campos 0 y 1, finales en los campos 2 y 3.
      await escribir(tester, 0, '100');
      await escribir(tester, 1, '200');
      await escribir(tester, 2, '122');
      await escribir(tester, 3, '215');

      expect(find.text('22'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
    });

    testWidgets('sin lecturas deja la cantidad de agua en guion', (
      tester,
    ) async {
      await montar(
        tester,
        const PreparacionSolucionSection(galpones: ['1'], edad: 21),
      );

      // Cantidad de agua y tiempo de vacunación, los dos calculados.
      expect(find.text('—'), findsNWidgets(2));
      // La edad sale de «Información de vacuna».
      expect(find.text('21 días'), findsOneWidget);
    });

    testWidgets('calcula el tiempo de vacunación entre las dos horas', (
      tester,
    ) async {
      await montar(
        tester,
        const PreparacionSolucionSection(galpones: ['1'], edad: null),
      );

      await elegirHora(tester, 0, '0630');
      await elegirHora(tester, 0, '0700');

      // Media hora, en hh:mm como se lee en el formato.
      expect(find.text('00:30'), findsOneWidget);
    });

    testWidgets('sin galpones pide elegirlos', (tester) async {
      await montar(
        tester,
        const PreparacionSolucionSection(galpones: [], edad: 21),
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Seleccione los galpones'), findsOneWidget);
    });
  });

  group('Evaluación de eficiencia', () {
    testWidgets('calcula total, sin vacuna y eficiencia de cada galpón', (
      tester,
    ) async {
      await montar(
        tester,
        const EvaluacionEficienciaSection(galpones: ['1']),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('POLLOS EVALUADOS'), findsOneWidget);
      expect(find.text('POLLOS CON VACUNA'), findsOneWidget);
      expect(find.text('POLLOS SIN VACUNA'), findsOneWidget);

      // Orden de las celdas: evaluados macho, evaluados hembra, con vacuna
      // macho y con vacuna hembra.
      await escribir(tester, 0, '50');
      await escribir(tester, 1, '50');
      await escribir(tester, 2, '45');
      await escribir(tester, 3, '40');

      expect(find.text('100'), findsOneWidget); // total evaluados
      expect(find.text('5'), findsOneWidget); // sin vacuna macho
      expect(find.text('10'), findsOneWidget); // sin vacuna hembra
      expect(find.text('85%'), findsOneWidget); // (45+40) / 100
    });

    testWidgets('un renglón por galpón', (tester) async {
      await montar(
        tester,
        const EvaluacionEficienciaSection(galpones: ['1', '2', '3']),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsNWidgets(12));
    });

    testWidgets('sin galpones pide elegirlos', (tester) async {
      await montar(
        tester,
        const EvaluacionEficienciaSection(galpones: []),
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Seleccione los galpones'), findsOneWidget);
    });
  });

  // Lo que cada sección entrega al guardar es un contrato con
  // `san_fact_vacunaagua_det`: si un nombre de sección o de parámetro cambia,
  // el reporte deja de poder rearmar la tabla.
  group('detalle que se guarda', () {
    /// Monta la sección con su recolector y devuelve las filas que entrega.
    Future<List<Map<String, dynamic>>> filasDe(
      WidgetTester tester,
      Widget Function(VacunacionDetalleController) construir,
    ) async {
      final ctl = VacunacionDetalleController();
      await montar(tester, construir(ctl));
      return ctl.filas();
    }

    testWidgets('sedeo: un renglón por galpón con horas', (tester) async {
      final ctl = VacunacionDetalleController();
      await montar(
        tester,
        TiempoSedeoSection(galpones: const ['1', '2'], detalle: ctl),
      );

      // Sin valores todavía no hay nada que guardar.
      expect(ctl.filas(), isEmpty);

      await elegirHora(tester, 0, '0800');

      final filas = ctl.filas();
      expect(filas, hasLength(1));
      expect(filas.first['seccion'], 'sedeo');
      expect(filas.first['galpon'], '1');
      expect(filas.first['parametro'], 'Horas');
      expect(filas.first['hora'], '08:00');
      expect(filas.first['valor_num'], 8.0);
    });

    testWidgets('bebederos: un renglón por ítem de cada bloque', (
      tester,
    ) async {
      final filas = await filasDe(
        tester,
        (ctl) => VerificacionBebederosSection(detalle: ctl),
      );

      expect(filas, hasLength(12)); // 6 ítems en dos bloques
      expect(filas.first['seccion'], 'bebederos');
      expect(
        filas.first['grupo'],
        'Operatividad de las llaves de manejo de agua en mesa de control',
      );
      expect(filas.first['parametro'], 'Fuga de agua en las llaves de manejo');
      expect(filas.first['flag'], false);
      expect(filas[6]['grupo'], 'Operatividad de las líneas de bebedero en galpón');
    });

    testWidgets('solucion: guarda los renglones escritos y los calculados', (
      tester,
    ) async {
      final ctl = VacunacionDetalleController();
      await montar(
        tester,
        PreparacionSolucionSection(
          galpones: const ['1'],
          edad: 21,
          detalle: ctl,
        ),
      );

      // Celdas: lectura inicial, final, litros, marcador, temp macho, temp
      // hembra (los calculados y las horas no son campos de texto).
      await escribir(tester, 0, '89878');
      await escribir(tester, 1, '89900');
      await elegirHora(tester, 0, '0630');
      await elegirHora(tester, 0, '0715');

      final filas = ctl.filas();
      final porParametro = {
        for (final f in filas) f['parametro'] as String: f,
      };

      expect(porParametro['Lectura inicial de medidor']!['valor_num'], 89878);
      expect(porParametro['Lectura final de medidor']!['valor_num'], 89900);
      expect(porParametro['Cantidad de agua (m3)']!['valor_num'], 22);
      // El tiempo de vacunación se guarda como duración hh:mm (texto), no como
      // fracción de hora: así el informe lo muestra tal cual se leyó.
      expect(porParametro['Tiempo de vacunación']!['valor_texto'], '00:45');
      expect(porParametro['Tiempo de vacunación']!['valor_num'], isNull);
      // La edad no se repite en el detalle: va en la cabecera.
      expect(porParametro.containsKey('Edad'), isFalse);
      for (final f in filas) {
        expect(f['seccion'], 'solucion');
        expect(f['galpon'], '1');
      }
    });

    testWidgets('eficiencia: un renglón por dato, con el grupo del encabezado', (
      tester,
    ) async {
      final ctl = VacunacionDetalleController();
      await montar(
        tester,
        EvaluacionEficienciaSection(galpones: const ['1'], detalle: ctl),
      );

      await escribir(tester, 0, '50');
      await escribir(tester, 1, '50');
      await escribir(tester, 2, '45');
      await escribir(tester, 3, '40');

      final filas = ctl.filas();
      expect(filas, hasLength(8));

      final clave = {
        for (final f in filas) '${f['grupo']}|${f['parametro']}': f,
      };
      expect(clave['Pollos evaluados|Macho']!['valor_num'], 50);
      expect(clave['Pollos evaluados|hembra']!['valor_num'], 50);
      expect(clave['|Cantidad total']!['valor_num'], 100);
      expect(clave['Pollos con vacuna|Macho']!['valor_num'], 45);
      expect(clave['Pollos sin vacuna|Macho']!['valor_num'], 5);
      expect(clave['Pollos sin vacuna|hembra']!['valor_num'], 10);
      expect(clave['|Eficiencia']!['valor_num'], 85);
    });

    testWidgets('el recolector junta las secciones en orden', (tester) async {
      final ctl = VacunacionDetalleController();
      await montar(
        tester,
        Column(
          children: [
            TiempoSedeoSection(galpones: const ['1'], detalle: ctl),
            VerificacionBebederosSection(detalle: ctl),
            EvaluacionEficienciaSection(galpones: const ['1'], detalle: ctl),
          ],
        ),
      );

      await elegirHora(tester, 0, '0600');

      final secciones = ctl.filas().map((f) => f['seccion']).toList();
      // Primero sedeo (tiene el valor), después los 12 ítems de bebederos.
      expect(secciones.first, 'sedeo');
      expect(secciones.where((s) => s == 'bebederos'), hasLength(12));
      // La evaluación no cargó nada, así que no aporta filas.
      expect(secciones.contains('eficiencia'), isFalse);
    });
  });
}
