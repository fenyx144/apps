import 'package:vacuna_al_agua/widgets/bio_form_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Alto de una fila de las listas del reloj. Está repetido a propósito: si
/// cambia, las pruebas tienen que notarlo.
const double altoDeFila = 44.0;

/// Texto de la fila centrada de una lista: la que queda bajo el recuadro.
/// Hace falta ubicarla por posición y no por texto: las listas dibujan las
/// filas vecinas, así que buscar el texto a secas encuentra también las de
/// arriba y las de abajo.
String ruedaCentrada(WidgetTester tester, String clave) {
  final rueda = find.byKey(ValueKey(clave));
  final centro = tester.getCenter(rueda).dy;
  final textos = find.descendant(of: rueda, matching: find.byType(Text));
  for (final elemento in textos.evaluate()) {
    final caja = elemento.renderObject;
    if (caja is! RenderBox) continue;
    final dy = caja.localToGlobal(caja.size.center(Offset.zero)).dy;
    if ((dy - centro).abs() < altoDeFila / 2) {
      return (elemento.widget as Text).data ?? '';
    }
  }
  fail('La lista $clave no tiene una fila centrada');
}

void main() {
  group('bioParseHora interpreta lo que se teclea', () {
    test('bloque de dígitos sin dos puntos', () {
      expect(bioParseHora('6'), '06:00');
      expect(bioParseHora('18'), '18:00');
      expect(bioParseHora('630'), '06:30');
      expect(bioParseHora('0630'), '06:30');
      expect(bioParseHora('2359'), '23:59');
      expect(bioParseHora('0000'), '00:00');
    });

    test('con dos puntos, con o sin ceros a la izquierda', () {
      expect(bioParseHora('06:30'), '06:30');
      expect(bioParseHora('6:30'), '06:30');
      expect(bioParseHora('6:5'), '06:05');
      expect(bioParseHora('18:45'), '18:45');
    });

    test('acepta el formato con segundos que guarda la base', () {
      expect(bioParseHora('18:45:00'), '18:45');
      expect(bioParseHora('06:30:59'), '06:30');
    });

    test('ignora espacios alrededor', () {
      expect(bioParseHora('  18:45  '), '18:45');
      expect(bioParseHora('\t0630\n'), '06:30');
    });

    test('rechaza vacío, fuera de rango y basura', () {
      expect(bioParseHora(''), isNull);
      expect(bioParseHora('    '), isNull);
      expect(bioParseHora(':'), isNull);
      expect(bioParseHora('24:00'), isNull);
      expect(bioParseHora('12:60'), isNull);
      expect(bioParseHora('060'), isNull);
      expect(bioParseHora('12345'), isNull);
      expect(bioParseHora('abc'), isNull);
    });
  });

  group('bioParseDuracion acepta más de 23 horas', () {
    test('horas largas y minutos válidos', () {
      expect(bioParseDuracion('00:00'), '00:00');
      expect(bioParseDuracion('08:00'), '08:00');
      expect(bioParseDuracion('9030'), '90:30');
      expect(bioParseDuracion('99:59'), '99:59');
    });

    test('rechaza hora de reloj fuera de rango de duración', () {
      expect(bioParseDuracion('100:00'), isNull);
      expect(bioParseDuracion('12:60'), isNull);
    });
  });

  group('bioHora12 y bioHora24 pasan de 12 a 24 y de vuelta', () {
    test('la hora del reloj va de la 1 a la 12, nunca de la 0 a la 11', () {
      expect(bioHora12(0), 12);
      expect(bioHora12(1), 1);
      expect(bioHora12(9), 9);
      expect(bioHora12(12), 12);
      expect(bioHora12(13), 1);
      expect(bioHora12(23), 11);
    });

    test('la hora 12 vuelve a empezar en cada meridiano', () {
      // Las 12 del reloj son las 00 de la madrugada y las 12 del mediodía.
      expect(bioHora24(12, false), 0);
      expect(bioHora24(12, true), 12);
      expect(bioHora24(1, false), 1);
      expect(bioHora24(1, true), 13);
      expect(bioHora24(11, true), 23);
    });

    test('ida y vuelta: de 24 a 12 y de 12 a 24 da lo mismo', () {
      for (var hora = 0; hora < 24; hora++) {
        expect(bioHora24(bioHora12(hora), hora >= 12), hora);
      }
    });
  });

  group('showBioHoraDialog', () {
    /// Monta un botón que abre el diálogo con [valorActual] y entrega el
    /// resultado a [guardar].
    Future<void> montar(
      WidgetTester tester,
      void Function(String?) guardar, {
      String valorActual = '',
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  guardar(await showBioHoraDialog(
                    context,
                    valorActual: valorActual,
                  ));
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    /// Gira una lista [filas] posiciones hacia adelante.
    Future<void> girar(WidgetTester tester, String rueda, int filas) async {
      await tester.drag(
        find.byKey(ValueKey(rueda)),
        Offset(0, -altoDeFila * filas),
      );
      await tester.pumpAndSettle();
    }

    /// Pasa de las listas al teclado.
    Future<void> usarTeclado(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.keyboard_alt_outlined));
      await tester.pumpAndSettle();
    }

    /// Lo que quedó escrito en el campo del teclado.
    String textoDelCampo(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField)).controller?.text ?? '';

    testWidgets('acepta 0630 y devuelve 06:30', (tester) async {
      String? resultado;
      await montar(tester, (v) => resultado = v);
      await usarTeclado(tester);

      await tester.enterText(find.byType(TextField), '0630');
      await tester.pump();
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();

      expect(resultado, '06:30');
    });

    testWidgets('con el teclado, Aceptar se deshabilita si la hora no es válida',
        (tester) async {
      await montar(tester, (_) {});
      await usarTeclado(tester);

      ElevatedButton boton() => tester.widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Aceptar'),
          );

      await tester.enterText(find.byType(TextField), '9999');
      await tester.pump();
      expect(boton().onPressed, isNull);
      expect(find.text('Hora no válida'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '1830');
      await tester.pump();
      expect(boton().onPressed, isNotNull);
      expect(find.text('Hora no válida'), findsNothing);
    });

    testWidgets('las listas abren en el valor de partida', (tester) async {
      await montar(tester, (_) {}, valorActual: '18:45');

      // 18:45 se lee como 06:45 PM: cada lista abre en su parte.
      expect(ruedaCentrada(tester, 'bioHoraRuedaHora'), '06');
      expect(ruedaCentrada(tester, 'bioHoraRuedaMinuto'), '45');
      expect(ruedaCentrada(tester, 'bioHoraRuedaMeridiano'), 'PM');
    });

    testWidgets('la medianoche se muestra como 12 y vuelve a ser 00',
        (tester) async {
      String? resultado;
      await montar(tester, (v) => resultado = v, valorActual: '00:30');

      // El reloj no tiene cero: la hora 00 se lee como 12 de la mañana.
      expect(ruedaCentrada(tester, 'bioHoraRuedaHora'), '12');
      expect(ruedaCentrada(tester, 'bioHoraRuedaMinuto'), '30');
      expect(ruedaCentrada(tester, 'bioHoraRuedaMeridiano'), 'AM');

      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      expect(resultado, '00:30');
    });

    testWidgets('la lista de horas avanza de a una y conserva el AM/PM',
        (tester) async {
      String? resultado;
      await montar(tester, (v) => resultado = v, valorActual: '09:00');

      // 09:00 es de la mañana; dos filas más abajo quedan las 11, y el
      // meridiano no se mueve porque tiene su propia lista.
      await girar(tester, 'bioHoraRuedaHora', 2);
      expect(ruedaCentrada(tester, 'bioHoraRuedaHora'), '11');
      expect(ruedaCentrada(tester, 'bioHoraRuedaMeridiano'), 'AM');

      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      expect(resultado, '11:00');
    });

    testWidgets('el meridiano cambia la hora sin tocar la hora ni los minutos',
        (tester) async {
      String? resultado;
      await montar(tester, (v) => resultado = v, valorActual: '09:30');

      // 09:30 es de la mañana; al pasar a PM quedan las 21:30, con la hora y
      // los minutos donde estaban.
      await girar(tester, 'bioHoraRuedaMeridiano', 1);
      expect(ruedaCentrada(tester, 'bioHoraRuedaHora'), '09');
      expect(ruedaCentrada(tester, 'bioHoraRuedaMinuto'), '30');
      expect(ruedaCentrada(tester, 'bioHoraRuedaMeridiano'), 'PM');

      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      expect(resultado, '21:30');
    });

    testWidgets('pasar al teclado se lleva lo elegido en las listas',
        (tester) async {
      String? resultado;
      await montar(tester, (v) => resultado = v, valorActual: '09:30');
      await girar(tester, 'bioHoraRuedaHora', 2);

      // Las 11:30 de la mañana quedan escritas como 11:30, en 24 horas.
      await usarTeclado(tester);
      expect(textoDelCampo(tester), '11:30');

      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      expect(resultado, '11:30');
    });

    testWidgets('volver del teclado deja las listas donde quedó lo escrito',
        (tester) async {
      String? resultado;
      await montar(tester, (v) => resultado = v);
      await usarTeclado(tester);

      await tester.enterText(find.byType(TextField), '1830');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.access_time_rounded));
      await tester.pumpAndSettle();

      expect(ruedaCentrada(tester, 'bioHoraRuedaHora'), '06');
      expect(ruedaCentrada(tester, 'bioHoraRuedaMinuto'), '30');
      expect(ruedaCentrada(tester, 'bioHoraRuedaMeridiano'), 'PM');

      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      expect(resultado, '18:30');
    });

    testWidgets('las listas son anchas y con números grandes', (tester) async {
      // Con un valor de partida fijo: sin él el reloj abre en la hora actual y
      // la fila «01» solo existe si el reloj está cerca de la 1, así que la
      // prueba pasaría o fallaría según la hora a la que se corra.
      await montar(tester, (_) {}, valorActual: '01:00');

      // El alto de fila y el ancho de las listas están repetidos en esta
      // prueba a propósito: son justo lo que hace legible el reloj, así que si
      // cambian, la prueba tiene que notarlo.
      final listas = tester.getSize(find.byKey(const ValueKey('bioHoraListas')));
      expect(listas.width, 320);
      expect(listas.height, altoDeFila * 5);

      final uno = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('bioHoraRuedaHora')),
          matching: find.text('01'),
        ),
      );
      expect(uno.style?.fontSize, 26);
    });

    testWidgets('en una pantalla chica las listas se achican para entrar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await montar(tester, (_) {});

      expect(tester.takeException(), isNull);
      // 320 de pantalla menos los márgenes del diálogo (16+16 del borde y
      // 20+20 del contenido): el ancho que buscan las listas (320) no entra,
      // así que usan todo lo que hay y las ruedas se reparten ese espacio.
      expect(
        tester.getSize(find.byKey(const ValueKey('bioHoraListas'))).width,
        320 - 96,
      );
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
    });

    testWidgets('sin valor de partida abre en la hora actual', (tester) async {
      String? resultado;
      await montar(tester, (v) => resultado = v);

      final ahora = TimeOfDay.now();
      expect(
        ruedaCentrada(tester, 'bioHoraRuedaHora'),
        bioHora12(ahora.hour).toString().padLeft(2, '0'),
      );
      expect(
        ruedaCentrada(tester, 'bioHoraRuedaMeridiano'),
        ahora.hour >= 12 ? 'PM' : 'AM',
      );

      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      expect(bioParseHora(resultado ?? ''), isNotNull);
    });
  });
}
