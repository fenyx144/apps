import 'dart:convert';

import 'package:bioseguridad/screens/register_cerco_screen.dart';
import 'package:bioseguridad/services/catalog_service.dart';
import 'package:bioseguridad/services/storage_service.dart';
import 'package:bioseguridad/utils/constants.dart';
import 'package:bioseguridad/widgets/bio_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Catálogo de métricas del tablero tal como lo guarda la descarga.
Map<String, Object> _bioCon(List<Map<String, Object?>> metricas) => {
  AppConstants.keyCatalogosBio: jsonEncode({'metricas_cerco': metricas}),
};

/// Guarda un catálogo nuevo en prefs y hace que el servicio lo relea: es lo que
/// ocurre cuando el drawer termina de descargar los catálogos de bioseguridad.
Future<void> _descargar(
  WidgetTester tester,
  CatalogService catalog,
  List<Map<String, Object?>> metricas,
) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    AppConstants.keyCatalogosBio,
    jsonEncode({'metricas_cerco': metricas}),
  );
  await catalog.loadFromPrefs();
  await tester.pumpAndSettle();
}

/// Todos los campos de observación del tablero.
Finder _camposObs() => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Obs',
    );

/// Campo de observación de una fila del tablero (L1 va antes que L2).
Finder _campoObs(int indice) => _camposObs().at(indice);

Future<CatalogService> _montar(
  WidgetTester tester, {
  required List<Map<String, Object?>> metricas,
  Size pantalla = const Size(1200, 3000),
}) async {
  tester.view.physicalSize = pantalla;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(_bioCon(metricas));
  final prefs = await SharedPreferences.getInstance();
  final catalog = CatalogService();
  await catalog.loadFromPrefs();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => StorageService(prefs)),
        ChangeNotifierProvider.value(value: catalog),
      ],
      child: const MaterialApp(home: RegisterCercoScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return catalog;
}

/// Métrica del catálogo con la forma que envía el servidor (`bloque` + `obs`).
///
/// `ok` y `falla` son las dos respuestas de la fila; el servidor las manda
/// siempre, pero se pueden omitir para probar el respaldo.
Map<String, Object?> _m(
  String nombre,
  String std,
  String bloque, {
  bool obs = false,
  String? ok,
  String? falla,
}) => {
  'metrica': nombre,
  'std': std,
  'bloque': bloque,
  'obs': obs,
  'ok': ?ok,
  'falla': ?falla,
};

/// Catálogo completo (mismos 25 componentes que `bio_cerco_bloques()`), para
/// comprobar que cada fila aparece una sola vez, en su bloque.
List<Map<String, Object?>> _catalogoCompleto() => [
  _m('Verificación del voltaje', '>11', CatalogService.bloqueTablero, obs: true),
  _m('Cerco Operativo', 'Luz encendida', CatalogService.bloqueTablero),
  _m('Voltaje Operativo', 'Luz encendida', CatalogService.bloqueTablero),
  _m('Sirena Operativo', 'Luz encendida', CatalogService.bloqueTablero),
  _m('Nivel de Batería', '', CatalogService.bloqueTablero, obs: true),
  _m('Cerco Bloqueado/sin energía', '', CatalogService.bloqueTablero),
  _m('Cerco Apagado/No se active', '', CatalogService.bloqueTablero),
  _m('La sirena está sonando alerta', '', CatalogService.bloqueTablero),
  _m('Verificación de voltaje', '', CatalogService.bloqueCerco),
  _m('Argolla Pegada', 'No pegada', CatalogService.bloqueCerco),
  _m('Argolla caída', 'Completo', CatalogService.bloqueCerco),
  _m('Puente pegado', 'No Pegado', CatalogService.bloqueCerco),
  _m('Puente caído (línea abierta)', 'Completo', CatalogService.bloqueCerco),
  _m('Línea enterrada (humedad)', '', CatalogService.bloqueCerco),
  _m('Línea con bolsa (basura)', 'Sin basura', CatalogService.bloqueCerco),
  _m('Cable Conectado', 'Conectado', CatalogService.bloqueCerco),
  _m('Templador/aislador suelto', 'Conectado', CatalogService.bloqueCerco),
  _m('Aislador suelto intermedio', 'Conectado', CatalogService.bloqueCerco),
  _m('Puerta Vehicular abierta', 'Cerrado', CatalogService.bloquePerimetro),
  _m('Puerta Vehicular desactivada', 'Cerrada', CatalogService.bloquePerimetro),
  _m('Puerta del personal abierta', 'Cerrado', CatalogService.bloquePerimetro),
  _m('Puerta pozo séptico abierta', 'Cerrado', CatalogService.bloquePerimetro),
  _m('Pozo séptico desactivado', 'Cerrado', CatalogService.bloquePerimetro),
];

void main() {
  final metricasViejas = [
    _m('Verificación del voltaje', '>31', CatalogService.bloqueTablero,
        obs: true),
    _m('Cerco Operativo', 'Luz encendida', CatalogService.bloqueTablero),
  ];

  testWidgets('el STD del tablero se actualiza al descargar el catálogo', (
    tester,
  ) async {
    final catalog = await _montar(tester, metricas: metricasViejas);

    // El equipo trae el catálogo de la descarga anterior. El STD se muestra
    // dentro de la primera columna, debajo del nombre del componente.
    expect(find.text('STD: >31'), findsOneWidget);

    // El vigilante ya escribió el voltaje medido.
    await tester.enterText(_campoObs(0), '31 V');
    await tester.pump();
    expect(find.text('31 V'), findsOneWidget);

    // Descarga desde el drawer: el servidor corrigió el estándar a >11.
    await _descargar(tester, catalog, [
      _m('Verificación del voltaje', '>11', CatalogService.bloqueTablero,
          obs: true),
      _m('Cerco Operativo', 'Luz encendida', CatalogService.bloqueTablero),
    ]);

    expect(find.text('STD: >31'), findsNothing);
    expect(find.text('STD: >11'), findsOneWidget);
    // La observación escrita no se pierde en la actualización.
    expect(find.text('31 V'), findsOneWidget);
  });

  testWidgets('una métrica nueva del catálogo aparece sin reiniciar la app', (
    tester,
  ) async {
    final catalog = await _montar(tester, metricas: metricasViejas);

    expect(find.text('Sirena Operativo'), findsNothing);

    await _descargar(tester, catalog, [
      _m('Verificación del voltaje', '>11', CatalogService.bloqueTablero,
          obs: true),
      _m('Cerco Operativo', 'Luz encendida', CatalogService.bloqueTablero),
      _m('Sirena Operativo', 'Luz encendida', CatalogService.bloqueTablero),
    ]);

    expect(find.text('Sirena Operativo'), findsOneWidget);
    expect(find.text('STD: >11'), findsOneWidget);
  });

  testWidgets('los bloques salen del catálogo y no duplican filas', (
    tester,
  ) async {
    await _montar(tester, metricas: _catalogoCompleto());

    // Un bloque por cada `bloque` que envía el servidor, usado como título.
    expect(find.text('VERIFICACIÓN DEL TABLERO'), findsOneWidget);
    expect(find.text('VERIFICACIÓN DEL CERCO'), findsOneWidget);
    expect(find.text('VERIFICACIÓN DEL PERÍMETRO'), findsOneWidget);

    // El encabezado es «ESTADO» en las dos líneas de los tres bloques: el par
    // de respuestas («CT / FALLA» o «No / SI») se lee en cada celda, que es
    // donde se contesta, y repetirlo arriba no cabía en el ancho del teléfono.
    expect(find.text('L1\nESTADO'), findsNWidgets(3));
    expect(find.text('L2\nESTADO'), findsNWidgets(3));
    expect(find.textContaining('CT / FALLA'), findsNothing);

    // Cada componente aparece una sola vez: son las 25 del catálogo, sin
    // repetir las de cerco/perímetro dentro del tablero.
    expect(find.text('Argolla Pegada'), findsOneWidget);
    expect(find.text('Puerta Vehicular abierta'), findsOneWidget);
    expect(find.text('Verificación del voltaje'), findsOneWidget);

    // Solo voltaje y nivel de batería piden observación (indicado por el
    // catálogo), una vez por línea: 2 filas × 2 líneas.
    expect(_camposObs(), findsNWidgets(4));
  });

  group('las respuestas de cada fila salen del formato físico', () {
    CercoMetrica metrica(String nombre, {String? ok, String? falla}) =>
        CercoMetrica(
          nombre: nombre,
          std: '',
          bloque: CatalogService.bloqueTablero,
          ok: ok,
          falla: falla,
        );

    test('casi todas las filas se contestan CT o FALLA', () {
      // El tablero —salvo sus alertas— y las filas del cerco que no son una
      // pregunta de sí/no: ahí la pregunta es si el componente está controlado.
      for (final nombre in const [
        'Cerco Operativo',
        'Verificación del voltaje',
        'Verificación de voltaje',
        'Cable Conectado',
      ]) {
        expect(metrica(nombre).ok, 'CT', reason: nombre);
        expect(metrica(nombre).falla, 'FALLA', reason: nombre);
      }
    });

    test('el cerco y el perímetro también tienen filas de sí/no', () {
      // «¿La argolla está pegada?»: lo bueno es «No» (no hay anomalía) y «SI» la
      // falla, igual que en las alertas del tablero. El servidor manda las
      // mismas (ver `bio_cerco_respuestas()`), así que el respaldo las repite.
      for (final nombre in const [
        'Argolla Pegada',
        'Puente caído (línea abierta)',
        'Puerta Vehicular abierta',
        'Pozo séptico desactivado',
      ]) {
        expect(metrica(nombre).ok, 'No', reason: nombre);
        expect(metrica(nombre).falla, 'SI', reason: nombre);
      }
    });

    test('las tres alertas del tablero se contestan No o SI', () {
      // Ahí la pregunta no es si el componente está controlado sino si la
      // alerta está presente: «SI» es lo malo.
      for (final nombre in const [
        'Cerco Bloqueado/sin energía',
        'Cerco Apagado/No se active',
        'La sirena está sonando alerta',
      ]) {
        expect(metrica(nombre).ok, 'No', reason: nombre);
        expect(metrica(nombre).falla, 'SI', reason: nombre);
      }
    });

    test('el catálogo puede corregir las respuestas sin publicar la app', () {
      expect(metrica('Cerco Operativo', ok: 'OK', falla: 'MAL').ok, 'OK');
      expect(metrica('Cerco Operativo', ok: 'OK', falla: 'MAL').falla, 'MAL');
    });
  });

  test('las respuestas que manda el servidor llegan al servicio', () async {
    SharedPreferences.setMockInitialValues(_bioCon([
      _m('Cerco Operativo', 'Luz encendida', CatalogService.bloqueTablero,
          ok: 'OK', falla: 'MAL'),
      _m('La sirena está sonando alerta', '', CatalogService.bloqueTablero),
    ]));
    final catalog = CatalogService();
    await catalog.loadFromPrefs();

    final metricas = catalog.metricasCerco;
    expect(metricas.first.ok, 'OK');
    expect(metricas.first.falla, 'MAL');
    // La que no las trae hereda la regla del respaldo.
    expect(metricas.last.ok, 'No');
    expect(metricas.last.falla, 'SI');
  });

  testWidgets('las filas de sí/no se contestan No/SI y el resto CT/FALLA',
      (tester) async {
    await _montar(tester, metricas: _catalogoCompleto());

    // Nada marcado todavía, así que cada celda muestra la respuesta buena: «CT»
    // en las siete filas de CT/FALLA (las cinco primeras del tablero y dos del
    // cerco) y «No» en las dieciséis de sí/no (las tres alertas del tablero,
    // ocho del cerco y las cinco del perímetro). Cada fila tiene L1 y L2.
    expect(find.text('CT'), findsNWidgets(7 * 2));
    expect(find.text('No'), findsNWidgets(16 * 2));

    // Las alertas del tablero van después de sus cinco primeras filas, dos
    // interruptores por fila: el de la primera alerta es el décimo.
    final alerta = find.byType(BioSwitchCumple).at(10);
    await tester.tap(
      find.descendant(of: alerta, matching: find.byType(Switch)),
    );
    await tester.pumpAndSettle();

    // Marcar la falla en una alerta da «SI», que es como lo pide el formato
    // físico; en el resto de filas daría «FALLA».
    expect(find.text('SI'), findsOneWidget);
    expect(find.text('FALLA'), findsNothing);
    expect(find.text('No'), findsNWidgets(16 * 2 - 1));
  });

  testWidgets('el STD va en la primera columna, debajo del componente', (
    tester,
  ) async {
    await _montar(tester, metricas: _catalogoCompleto());

    // Ya no hay una columna «STD» aparte: el estándar se lee dentro de la celda
    // del componente, con la misma forma que tiene en la hoja («texto» arriba,
    // «STD: valor» abajo).
    expect(find.text('STD'), findsNothing);
    expect(find.text('STD: >11'), findsOneWidget);
    expect(find.text('STD: Luz encendida'), findsNWidgets(3));

    // Las métricas sin STD (las alertas del tablero) muestran solo el nombre.
    expect(find.text('La sirena está sonando alerta'), findsOneWidget);

    // El STD va en negrita: es contra lo que se compara lo medido y en la celda
    // tiene que leerse sin buscarlo.
    expect(
      tester.widget<Text>(find.text('STD: >11')).style?.fontWeight,
      FontWeight.w800,
    );
  });

  testWidgets('la observación va debajo del interruptor, en la misma celda', (
    tester,
  ) async {
    await _montar(tester, metricas: _catalogoCompleto());

    // La primera fila del tablero es «Verificación del voltaje», de valor
    // medido: lleva switch y observación. Van uno encima del otro para que la
    // observación no le robe ancho al interruptor ni lo corra de la columna.
    final interruptor = find.byType(Switch).first;
    final celda = find.ancestor(
      of: interruptor,
      matching: find.byType(BioTableCell),
    );
    expect(celda, findsOneWidget);

    final cajaSwitch = tester.getRect(interruptor);
    final cajaCampo = tester.getRect(
      find.descendant(of: celda, matching: find.byType(TextField)),
    );

    expect(cajaCampo.top, greaterThanOrEqualTo(cajaSwitch.bottom));
    // El campo usa el ancho de la celda, no el que le dejaba el interruptor.
    expect(cajaCampo.width, greaterThan(cajaSwitch.width));
  });

  testWidgets('las tres columnas entran en un teléfono: L1 y L2 se ven', (
    tester,
  ) async {
    // 360 lógicos es el teléfono más chico que se usa en campo.
    await _montar(
      tester,
      metricas: _catalogoCompleto(),
      pantalla: const Size(360, 800),
    );

    // Cuando la tabla no entra, BioTable le pone scroll horizontal propio. Que
    // no haya ninguno es exactamente que las tres columnas entren: L1 y L2 se
    // ven las dos, sin desplazar la tabla.
    expect(
      find.descendant(
        of: find.byType(BioTable),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    for (final etiqueta in ['L1\nESTADO', 'L2\nESTADO']) {
      expect(find.text(etiqueta), findsWidgets, reason: etiqueta);
    }
  });

  testWidgets('un catálogo cacheado sin bloque ni obs se agrupa con el respaldo',
      (tester) async {
    // Formato antiguo: solo `metrica` y `std`. El bloque y la observación se
    // heredan del respaldo por nombre.
    await _montar(tester, metricas: const [
      {'metrica': 'Argolla Pegada', 'std': 'No pegada'},
      {'metrica': 'Verificación del voltaje', 'std': '>11'},
    ]);

    expect(find.text('VERIFICACIÓN DEL CERCO'), findsOneWidget);
    expect(find.text('Argolla Pegada'), findsOneWidget);
    // «Verificación del voltaje» es de valor medido: hereda la observación.
    expect(_camposObs(), findsNWidgets(2));
  });
}
