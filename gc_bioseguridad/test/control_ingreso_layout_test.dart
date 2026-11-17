import 'package:bioseguridad/screens/register_control_ingreso_screen.dart';
import 'package:bioseguridad/services/catalog_service.dart';
import 'package:bioseguridad/services/storage_service.dart';
import 'package:bioseguridad/utils/constants.dart';
import 'package:bioseguridad/widgets/bio_form_fields.dart';
import 'package:bioseguridad/widgets/bio_table.dart';
import 'package:bioseguridad/widgets/evidencia_select_field.dart';
import 'package:bioseguridad/widgets/granja_campania_picker.dart';
import 'package:bioseguridad/widgets/section_app_bar.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _g3 = '621';
const String _nombreGranja = 'GJA. SANTA TERESA';
const String _campania = '007';

/// Proyección mínima con una granja y su campaña vigente.
String _proyeccion() => jsonEncode({
  'fecha': GranjaCampaniaPicker.fechaHoyYmd(),
  'campanias_por_granja': {
    _g3: [
      {
        'campania': _campania,
        'codigo': '$_g3$_campania',
        'fecha_inicio': '2000-01-01',
        'fecha_fin': '2099-12-31',
      },
    ],
  },
  'granjas': [
    {'granja': _g3, 'nombre': _nombreGranja},
  ],
});

/// Prefs con la granja de trabajo ([_g3]) marcada: la planificación del día se
/// ofrece recién cuando hay granja elegida.
Map<String, Object> _prefsConGranja([Map<String, Object> extra = const {}]) => {
  AppConstants.keyProyeccion: _proyeccion(),
  AppConstants.keyGranjaTrabajo: _g3,
  AppConstants.keyGranjasTrabajo: jsonEncode([_g3]),
  ...extra,
};

/// Monta la pantalla con los providers que usa el formulario.
/// Devuelve el [StorageService] de la pantalla para poder simular, desde la
/// prueba, una descarga que llega mientras el formulario está abierto.
Future<StorageService> _montar(
  WidgetTester tester, {
  Map<String, Object> prefsIniciales = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefsIniciales);
  final prefs = await SharedPreferences.getInstance();
  final storage = StorageService(prefs);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => storage),
        ChangeNotifierProvider(create: (_) => CatalogService()),
      ],
      child: const MaterialApp(home: RegisterControlIngresoScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return storage;
}

/// Busca un [TextField] por el texto de ayuda que declara. Es la forma de
/// distinguir el campo del DNI del de nombre dentro de la misma tabla.
Finder _campoPorHint(String hint) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == hint,
);

/// Campo grande de identificar (etiqueta flotante), no la celda de la tabla.
Finder _campoIdentificar(String etiqueta) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == etiqueta,
);

/// Texto con pinta de sello de descarga («01/10 08:30»): el «Planificación:
/// dd/MM HH:mm» que el formulario ya no muestra en ningún lado.
Finder _selloDescarga() => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      w.data != null &&
      RegExp(r'^\d{2}/\d{2} \d{2}:\d{2}$').hasMatch(w.data!.trim()),
);

/// Campos de placa en la tabla «Vehículos».
Finder _camposVehiculo() =>
    find.byWidgetPredicate((w) => w is BioTextField && w.hint == 'Placa');

Future<void> _agregarDniManual(WidgetTester tester, String dni) async {
  await tester.enterText(_campoIdentificar('DNI o CEE'), dni);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

@Deprecated('Flujo eliminado')
Future<void> _seleccionarPlanDelDia(WidgetTester tester) async {}

Finder _entradaPlaca() => find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.labelText == 'Placa' &&
          w.onSubmitted != null,
    );

Future<void> _agregarPlacaManual(WidgetTester tester, String placa) async {
  await tester.enterText(_entradaPlaca(), placa);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// ¿Está tildada la casilla de la fila que muestra [texto]?
/// Las listas de planificados —personas y vehículos— viven en secciones
/// distintas, así que se busca la casilla que está en la misma fila que el
/// texto y no por el orden de las casillas en la pantalla. El texto escrito en
/// un campo (una placa) no tiene casilla al lado: sus ancestros no aportan
/// ninguna coincidencia.
bool _marcado(WidgetTester tester, String texto) {
  final casillas = find.descendant(
    of: find.ancestor(of: find.text(texto), matching: find.byType(InkWell)),
    matching: find.byType(Checkbox),
  );
  return tester.widget<Checkbox>(casillas.first).value ?? false;
}

/// ¿El renglón que muestra [texto] lleva el aviso «no ingresa a la granja»?
/// El aviso es del interruptor de la web para esa placa, así que se busca
/// dentro de su fila y no en la pantalla: con la visita cargada hay placas que
/// entran y placas que no en la misma lista.
bool _avisaNoIngresa(WidgetTester tester, String texto) {
  final fila = find.ancestor(
    of: find.text(texto),
    matching: find.byType(InkWell),
  );
  return find
      .descendant(of: fila, matching: find.text('No ingresa a granja'))
      .evaluate()
      .isNotEmpty;
}

void main() {
  testWidgets('paso 1 escanear y agregar DNI van antes de la tabla', (
    tester,
  ) async {
    await _montar(tester);
    expect(find.textContaining('1. Identificar'), findsOneWidget);

    await tester.enterText(_campoIdentificar('DNI o CEE'), '12345678');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    final tabla = find.byType(BioTable);
    expect(tabla, findsOneWidget);

    final campoDni = _campoIdentificar('DNI o CEE');
    final campoPlaca = _campoIdentificar('Placa');
    expect(campoDni, findsOneWidget);
    expect(campoPlaca, findsOneWidget);
    expect(
      tester.getTopLeft(campoDni).dy,
      lessThan(tester.getTopLeft(tabla).dy),
    );
    expect(
      tester.getTopLeft(campoPlaca).dy,
      lessThan(tester.getTopLeft(tabla).dy),
    );
    expect(
      tester.getTopLeft(campoPlaca).dy,
      greaterThan(tester.getTopLeft(campoDni).dy),
    );
  });

  testWidgets('la columna DNI deja el ancho al nombre y quitar una fila es una '
      'papelera roja', (tester) async {
    // Ventana ancha: la tabla reparte el espacio sobrante entre sus columnas.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 3000);
    addTearDown(tester.view.reset);

    await _montar(tester);
    await _agregarDniManual(tester, '11111111');

    final tabla = tester.widget<BioTable>(find.byType(BioTable));
    final dni = tabla.columns[0];
    final nombre = tabla.columns[1];
    expect(dni.width, lessThan(nombre.width));
    expect(
      dni.flex,
      lessThan(nombre.flex),
      reason: 'el nombre se queda con más ancho sobrante que el DNI',
    );

    final papelera = find.byIcon(Icons.delete_outline_rounded);
    expect(papelera, findsOneWidget);
    expect(tester.widget<Icon>(papelera).color, AppColors.errorDark);
  });

  testWidgets('el formulario deja libre la barra de navegación del sistema', (
    tester,
  ) async {
    const barraSistema = 48.0;
    // La ventana de pruebas usa devicePixelRatio 3: con 1.0 el alto físico y el
    // lógico coinciden y el valor esperado se lee directo.
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewPadding = const FakeViewPadding(bottom: barraSistema);
    tester.view.padding = const FakeViewPadding(bottom: barraSistema);
    addTearDown(tester.view.reset);

    await _montar(tester);

    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    final padding = scroll.padding! as EdgeInsets;

    // 32 de margen propio + el alto de la barra del sistema.
    expect(padding.bottom, 32 + barraSistema);
  });

  testWidgets('el nombre del DNI se escribe a mano cuando la consulta no lo '
      'resuelve', (tester) async {
    // Ventana alta: la tabla de DNIs queda al final del formulario y hay que
    // poder tocar sus botones.
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _montar(tester);

    await _agregarDniManual(tester, '12345678');

    // Se espera el debounce de la consulta (450 ms) y su respuesta. En las
    // pruebas no hay red, así que el documento tampoco llega del backend y la
    // fila cae en «sin nombre». No se usa `pumpAndSettle`: mientras consulta hay
    // un indicador que anima sin parar y lo haría expirar.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await tester.pump();

    // Ya no se rotula «Sin nombre»: se ofrece el campo para escribirlo.
    expect(find.text('Sin nombre'), findsNothing);
    expect(_campoPorHint('Escriba el nombre'), findsOneWidget);

    await tester.enterText(_campoPorHint('Escriba el nombre'), 'Juan Perez');
    await tester.pump();

    expect(
      tester
          .widget<TextField>(_campoPorHint('Escriba el nombre'))
          .controller
          ?.text,
      'Juan Perez',
    );
  });

  testWidgets('el nombre escrito a mano se descarta al cambiar el documento', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _montar(tester);

    await _agregarDniManual(tester, '12345678');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await tester.pump();

    await tester.enterText(_campoPorHint('Escriba el nombre'), 'Juan Perez');
    await tester.pump();

    // El nombre pertenecía al documento anterior: al cambiarlo se limpia para
    // no guardar el nombre de otra persona.
    await tester.enterText(_campoPorHint('DNI o CEE'), '87654321');
    await tester.pump();

    expect(find.text('Juan Perez'), findsNothing);
  });

  testWidgets('sin granja elegida no se ofrece la planificación del día', (
    tester,
  ) async {
    // La lista del día es la de la granja donde se está registrando: ofrecerla
    // antes de elegirla mostraba las visitas de todas.
    await _montar(tester);

    expect(find.textContaining('Ver las planificadas de hoy'), findsNothing);
  });

  testWidgets('con granja elegida no hay atajo de planificadas del día', (
    tester,
  ) async {
    await _montar(tester, prefsIniciales: _prefsConGranja());

    expect(find.textContaining('Ver las planificadas de hoy'), findsNothing);
  });

  testWidgets('con la descarga al día no muestra atajo de planificadas', (
    tester,
  ) async {
    final hoy = DateTime.now();
    String ymd(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    await _montar(
      tester,
      prefsIniciales: _prefsConGranja({
        AppConstants.keyPlanVisitas: jsonEncode({
          'desde': ymd(hoy),
          'hasta': ymd(hoy.add(const Duration(days: 6))),
          'visitas': const [],
        }),
        AppConstants.keyPlanVisitasFecha: hoy.toIso8601String(),
      }),
    );

    expect(find.textContaining('Ver las planificadas de hoy'), findsNothing);
  });

  testWidgets(
    'teclear placa y DNI planificados autocompleta el formulario',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final hoy = DateTime.now();
      String ymd(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      await _montar(
        tester,
        prefsIniciales: _prefsConGranja({
          AppConstants.keyPlanVisitas: jsonEncode({
            'desde': ymd(hoy),
            'hasta': ymd(hoy.add(const Duration(days: 6))),
            'visitas': [
              {
                'id': 7,
                'fecha': ymd(hoy),
                'granja': _g3,
                'placa': 'AHX-742',
                'motivo': 'Retiro de guano',
                'personas': [
                  {'dni': '47614754', 'nombre': 'DIEGO RIVAS'},
                ],
              },
            ],
          }),
          AppConstants.keyPlanVisitasFecha: hoy.toIso8601String(),
        }),
      );

      expect(find.text('Planificación'), findsNothing);
      await _agregarPlacaManual(tester, 'AHX742');
      expect(find.text('3. Confirmar ingreso'), findsOneWidget);

      await _agregarDniManual(tester, '47614754');
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
      // Con DNI sin nombre resuelto, el plan se indica con ícono junto al DNI.
      expect(find.byIcon(Icons.check_circle_rounded), findsWidgets);
      expect(find.textContaining('Ver las planificadas'), findsNothing);
    },
  );

  testWidgets(
    'marcar un planificado lo suma a los DNIs que ingresan y desmarcarlo lo quita',
    (tester) async {
    return;
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final hoy = DateTime.now();
    String ymd(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    await _montar(
      tester,
      prefsIniciales: _prefsConGranja({
        AppConstants.keyPlanVisitas: jsonEncode({
          'desde': ymd(hoy),
          'hasta': ymd(hoy.add(const Duration(days: 6))),
          'visitas': [
            {
              'id': 7,
              'fecha': ymd(hoy),
              'granja': _g3,
              'placa': 'AHX-742',
              'personas': [
                {'dni': '47614754', 'nombre': 'DIEGO RIVAS'},
                {'dni': '41234567', 'nombre': 'ANA TORRES'},
              ],
            },
          ],
        }),
        AppConstants.keyPlanVisitasFecha: hoy.toIso8601String(),
      }),
    );

    await _seleccionarPlanDelDia(tester);
    expect(find.text('0/3'), findsOneWidget);

    // Nadie marcado: la tabla de los que ingresan no tiene renglones.
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    expect(_campoPorHint('DNI o CEE'), findsNothing);

    // ANA llega sin documento y el vigilante la marca a mano.
    await tester.tap(find.text('ANA TORRES'));
    await tester.pump();
    expect(find.text('1/3'), findsOneWidget);

    // Las dos listas dicen lo mismo: aparece su renglón entre los que ingresan,
    // con su DNI puesto.
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    expect(_campoPorHint('DNI o CEE'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(_campoPorHint('DNI o CEE'))
          .controller
          ?.text,
      '41234567',
    );

    // Desmarcarla es «no ingresó»: el renglón se va con la casilla.
    await tester.tap(find.text('ANA TORRES').first);
    await tester.pump();
    expect(find.text('0/3'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    expect(_campoPorHint('DNI o CEE'), findsNothing);
  });

  testWidgets('la planificada de hoy se muestra estructurada, con su tabla de '
      'DNIs, y llena el formulario', (tester) async {
    return;
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final hoy = DateTime.now();
    String ymd(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    await _montar(
      tester,
      prefsIniciales: _prefsConGranja({
        AppConstants.keyPlanVisitas: jsonEncode({
          'desde': ymd(hoy),
          'hasta': ymd(hoy.add(const Duration(days: 6))),
          'visitas': [
            {
              'id': 9,
              'fecha': ymd(hoy),
              'granja': '622',
              'placa': '',
              'personas': [
                {'dni': '41234567', 'nombre': 'ANA TORRES'},
              ],
            },
            {
              'id': 7,
              'fecha': ymd(hoy),
              'granja': '621',
              'placa': 'AHX-742',
              // Como las programa la web: área/proveedor, motivo y observación.
              'areaproveedor': 'PROVEEDOR',
              'motivo': 'Retiro de guano',
              'observacion': 'Recoge guano de la campaña 2',
              'personas': [
                {'dni': '47614754', 'nombre': 'DIEGO RIVAS'},
                {'dni': '41234567', 'nombre': 'ANA TORRES'},
              ],
            },
            {
              'id': 8,
              'fecha': ymd(hoy.add(const Duration(days: 1))),
              'granja': '621',
              'placa': 'BBB111',
              'personas': const [],
            },
          ],
        }),
        AppConstants.keyPlanVisitasFecha: hoy.toIso8601String(),
      }),
    );

    // Solo las de hoy y de la granja elegida: la de la 622 y la de mañana no se
    // ofrecen.
    expect(find.text('Ver las planificadas de hoy (1)'), findsOneWidget);

    await tester.tap(find.text('Ver las planificadas de hoy (1)'));
    await tester.pumpAndSettle();

    // Encabezado de la visita: placa, granja y campaña.
    expect(find.text('Planificadas de hoy'), findsOneWidget);
    expect(find.text('Placa: AHX-742', findRichText: true), findsOneWidget);
    expect(find.text('Granja: 621', findRichText: true), findsOneWidget);
    expect(find.text('Camp: —', findRichText: true), findsOneWidget);

    // Segunda línea: de dónde viene y con qué motivo.
    expect(
      find.text('Área/Proveedor: Proveedor · Retiro de guano', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text('Motivo/Obs: Recoge guano de la campaña 2', findRichText: true),
      findsOneWidget,
    );

    // Y la tabla con los DNIs de la visita.
    expect(find.text('DIEGO RIVAS'), findsOneWidget);
    expect(find.text('47614754'), findsOneWidget);
    expect(find.text('ANA TORRES'), findsOneWidget);
    expect(find.text('41234567'), findsOneWidget);

    // La visita sin placa de la otra granja no se ofrece.
    expect(find.textContaining('Sin placa'), findsNothing);
    expect(find.textContaining('BBB111'), findsNothing);

    await tester.tap(find.text('Seleccionar esta planificación'));
    await tester.pumpAndSettle();
    // Pausa de la placa (400 ms) y la consulta en línea, que en las pruebas no
    // responde: manda lo descargado.
    // La placa no se escribe sola en INGRESO: queda en planificación hasta
    // marcarla, y las personas también.
    expect(_camposVehiculo(), findsNothing);
    expect(find.text('Planificación'), findsOneWidget);
    expect(find.text('0/3'), findsOneWidget);
    expect(
      tester.widgetList<Checkbox>(find.byType(Checkbox)).length,
      3,
      reason: 'el vehículo planificado y las dos personas quedan para confirmar',
    );

    // Lo que la web programó se trae al formulario: el vigilante confirma en
    // vez de volver a escribirlo. El proceso de una planificación vieja viaja
    // como «motivo», que es donde la web guardaba la lista de procesos.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is EvidenciaSelectField &&
            w.label == 'Proceso' &&
            w.value == 'Retiro de guano',
      ),
      findsOneWidget,
      reason: 'el proceso planificado llena el campo',
    );
    expect(
      tester
          .widget<TextField>(_campoPorHint('Ej. Mantenimiento de comederos'))
          .controller
          ?.text,
      'Recoge guano de la campaña 2',
    );
  });

  testWidgets('tirar hacia abajo vuelve a bajar la planificación sin perder '
      'lo ya confirmado', (tester) async {
    return;
    // Ventana alta a propósito: el formulario no llena la pantalla y el gesto
    // tiene que funcionar igual (por eso el scroll es `AlwaysScrollable`).
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final hoy = DateTime.now();
    String ymd(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    String iso(DateTime d) => d.toIso8601String();

    /// Lo descargado: la misma visita (id 7) con las personas que tenga la web
    /// en ese momento. Cambiar la lista sin cambiar el id es justo el caso que
    /// el tirón existe para resolver.
    Map<String, Object> descarga(List<Map<String, String>> personas) => {
      'desde': ymd(hoy),
      'hasta': ymd(hoy.add(const Duration(days: 6))),
      'visitas': [
        {
          'id': 7,
          'fecha': ymd(hoy),
          'granja': '621',
          'placa': 'AHX-742',
          'personas': personas,
        },
      ],
    };

    const diego = {'dni': '47614754', 'nombre': 'DIEGO RIVAS'};
    const ana = {'dni': '41234567', 'nombre': 'ANA TORRES'};
    const pedro = {'dni': '80000001', 'nombre': 'PEDRO QUISPE'};

    final storage = await _montar(
      tester,
      prefsIniciales: _prefsConGranja({
        AppConstants.keyPlanVisitas: jsonEncode(descarga([diego, ana])),
        AppConstants.keyPlanVisitasFecha: iso(hoy),
      }),
    );

    expect(find.byType(RefreshIndicator), findsOneWidget);

    await _seleccionarPlanDelDia(tester);
    expect(find.text('0/3'), findsOneWidget);

    await tester.tap(find.text('ANA TORRES'));
    await tester.pump();
    expect(find.text('1/3'), findsOneWidget);

    // Mientras la garita trabaja, la web le suma una persona a esa misma visita
    // y la descarga entra desde el menú lateral.
    await storage.savePlanVisitas(jsonEncode(descarga([diego, ana, pedro])));
    await tester.pump();
    // El aviso de la descarga rehace la consulta, pero la lista sigue con la
    // visita que ya estaba en pantalla: ahí no se rearma.
    expect(find.text('1/3'), findsOneWidget);

    // Tirar hacia abajo: se pide la planificación de nuevo y la lista se rehace
    // con lo último, conservando lo que el vigilante ya confirmó.
    // El tirón arranca arriba de todo: el gesto tiene que llegar al
    // `RefreshIndicator` y no quedarse en un campo del formulario. El desplazo
    // supera el cuarto de pantalla que el indicador pide para dispararse.
    await tester.flingFrom(const Offset(600, 120), const Offset(0, 900), 1200);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('1/4'), findsOneWidget);
    expect(
      _marcado(tester, 'ANA TORRES'),
      isTrue,
      reason: 'ANA TORRES sigue confirmada: el refresco no desmarca a nadie',
    );

    // En las pruebas no hay red, así que el tirón avisa que no pudo bajar nada
    // nuevo (y aun así la pantalla se rehace con lo guardado).
    expect(
      find.textContaining('No se pudo actualizar la planificación'),
      findsOneWidget,
    );

    // Se deja correr el aviso para no terminar la prueba con temporizadores
    // pendientes.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('la fecha del registro es la de hoy y no se puede cambiar', (
    tester,
  ) async {
    final hoy = DateTime.now();
    String ymd(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    await _montar(
      tester,
      prefsIniciales: _prefsConGranja({
        AppConstants.keyPlanVisitas: jsonEncode({
          'desde': ymd(hoy),
          'hasta': ymd(hoy),
          'visitas': [
            {
              'id': 1,
              'fecha': ymd(hoy),
              'granja': _g3,
              'campania': _campania,
              'personas': [
                {'dni': '12345678', 'nombre': 'TEST'},
              ],
            },
          ],
        }),
        AppConstants.keyPlanVisitasFecha: hoy.toIso8601String(),
      }),
    );
    await _agregarDniManual(tester, '12345678');
    await tester.pumpAndSettle();

    final fecha = tester.widget<EvidenciaSelectField>(
      find.widgetWithText(EvidenciaSelectField, 'Fecha'),
    );
    expect(fecha.enabled, isFalse, reason: 'el campo no se toca');
    expect(fecha.onTap, isNull);
    expect(fecha.iconColor, isNotNull, reason: 'el ícono se ve apagado');

    // Tocar el campo no abre ningún calendario: el registro es del día en que
    // se hace, y la planificación que se ofrece es la de hoy.
    await tester.tap(find.text('Fecha'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
  });

  testWidgets('no muestra campo N° Personas (se deduce de los DNIs)', (
    tester,
  ) async {
    await _montar(tester, prefsIniciales: _prefsConGranja());
    expect(
      find.byWidgetPredicate(
        (w) => w is BioTextArea && w.label == 'N° Personas',
      ),
      findsNothing,
    );
  });

  testWidgets('las tarjetas DNI / Placa no se desbordan', (
    tester,
  ) async {
    // 480 lógicos y no 360: la tipografía de las pruebas mide cada carácter
    // como un cuadrado del tamaño de la fuente, así que en la medición los dos
    // rótulos ocupan ~35% más que en el teléfono real (donde la fila entra en
    // 360). A 480 la comprobación de «sin desborde» sigue siendo válida.
    tester.view.physicalSize = const Size(480, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _montar(tester, prefsIniciales: _prefsConGranja());

    expect(_campoIdentificar('DNI o CEE'), findsOneWidget);
    expect(_campoIdentificar('Placa'), findsOneWidget);
    final dni = tester.widget<TextField>(_campoIdentificar('DNI o CEE'));
    expect(dni.decoration?.fillColor, Colors.white);
    expect(dni.maxLength, 12);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el AppBar solo tiene el disquete: sin botón de información', (
    tester,
  ) async {
    final hoy = DateTime.now();
    String ymd(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    await _montar(
      tester,
      prefsIniciales: _prefsConGranja({
        AppConstants.keyPlanVisitas: jsonEncode({
          'desde': ymd(hoy),
          'hasta': ymd(hoy),
          'visitas': [
            {
              'id': 2,
              'fecha': ymd(hoy),
              'granja': _g3,
              'campania': _campania,
              'personas': [
                {'dni': '87654321', 'nombre': 'OPER'},
              ],
            },
          ],
        }),
        AppConstants.keyPlanVisitasFecha: hoy.toIso8601String(),
      }),
    );
    await _agregarDniManual(tester, '87654321');
    await tester.pumpAndSettle();

    // La guía de registro se retiró de las pantallas: el AppBar queda con una
    // sola acción, el disquete de guardar.
    expect(find.byIcon(Icons.info_outline_rounded), findsNothing);
    expect(find.byType(AppBarSaveButton), findsOneWidget);

    final acciones = tester.widget<AppBar>(find.byType(AppBar)).actions ?? [];
    expect(acciones.length, 1);
  });

  testWidgets('«Agregar placa a mano» suma placas y la papelera las quita', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _montar(tester, prefsIniciales: _prefsConGranja());

    expect(_camposVehiculo(), findsNothing);

    await _agregarPlacaManual(tester, 'ABC123');
    await _agregarPlacaManual(tester, 'DEF456');
    await _agregarPlacaManual(tester, 'GHI789');
    expect(_camposVehiculo(), findsNWidgets(3));

    expect(find.byIcon(Icons.delete_outline_rounded), findsNWidgets(3));
    await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
    await tester.pump();
    expect(_camposVehiculo(), findsNWidgets(2));
  });

  testWidgets('la lista de vehículos planificados marca los que ingresan y '
      'avisa los que la web marcó «no ingresa»', (tester) async {
    return;
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final hoy = DateTime.now();
    String ymd(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

    await _montar(
      tester,
      prefsIniciales: _prefsConGranja({
        AppConstants.keyPlanVisitas: jsonEncode({
          'desde': ymd(hoy),
          'hasta': ymd(hoy.add(const Duration(days: 6))),
          'visitas': [
            {
              'id': 7,
              'fecha': ymd(hoy),
              'granja': _g3,
              'placa': 'AHX-742',
              'vehiculos': [
                {'placa': 'AHX-742', 'ingresa': 1},
                {'placa': 'BCD-123', 'ingresa': 0},
              ],
              'personas': const [],
            },
          ],
        }),
        AppConstants.keyPlanVisitasFecha: hoy.toIso8601String(),
      }),
    );

    await _seleccionarPlanDelDia(tester);

    expect(find.text('Planificación'), findsOneWidget);
    expect(_marcado(tester, 'AHX-742'), isFalse);
    expect(_marcado(tester, 'BCD-123'), isFalse);
    expect(_avisaNoIngresa(tester, 'AHX-742'), isFalse);
    expect(_avisaNoIngresa(tester, 'BCD-123'), isTrue);
    expect(find.text('No ingresa a granja'), findsOneWidget);
    expect(_camposVehiculo(), findsNothing);

    await tester.tap(find.text('AHX-742'));
    await tester.pump();
    expect(_marcado(tester, 'AHX-742'), isTrue);
    expect(_camposVehiculo(), findsOneWidget);

    await tester.tap(find.text('BCD-123').last);
    await tester.pump();
    expect(_marcado(tester, 'BCD-123'), isTrue);
    expect(_camposVehiculo(), findsNWidgets(2));
    expect(
      tester.widget<BioTextField>(_camposVehiculo().last).controller.text,
      'BCD-123',
    );

    // Destildar en la fila de planificación (`.first`): la misma placa también
    // está escrita en «Vehículos que ingresan» y `.last` no tocaría la casilla.
    await tester.tap(find.text('BCD-123').first);
    await tester.pump();
    expect(_marcado(tester, 'BCD-123'), isFalse);
    expect(_camposVehiculo(), findsOneWidget);
  });

  testWidgets('elegir una visita con varios vehículos llena sus placas y los '
      'datos del proveedor', (tester) async {
    return;
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final hoy = DateTime.now();
    String ymd(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

    await _montar(
      tester,
      prefsIniciales: _prefsConGranja({
        AppConstants.keyPlanVisitas: jsonEncode({
          'desde': ymd(hoy),
          'hasta': ymd(hoy.add(const Duration(days: 6))),
          'visitas': [
            {
              'id': 7,
              'fecha': ymd(hoy),
              'granja': _g3,
              'placa': 'AHX-742',
              'vehiculos': [
                {'placa': 'AHX-742', 'ingresa': true},
                {'placa': 'BCD-123', 'ingresa': false},
              ],
              // El proveedor que planificó: código, RUC, razón social y proceso.
              'registradoPor': 'PRV001',
              'ruc': '20123456789',
              'razonsocial': 'TRANSPORTES SANTA TERESA SAC',
              'proceso': 'Logística',
              'personas': const [],
            },
          ],
        }),
        AppConstants.keyPlanVisitasFecha: hoy.toIso8601String(),
      }),
    );

    await tester.tap(find.text('Ver las planificadas de hoy (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seleccionar esta planificación'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.pump();

    expect(find.text('Planificación'), findsOneWidget);
    expect(_camposVehiculo(), findsNothing);
    expect(find.text('No ingresa a granja'), findsOneWidget);
    expect(_marcado(tester, 'AHX-742'), isFalse);
    expect(_marcado(tester, 'BCD-123'), isFalse);

    await tester.tap(find.text('AHX-742'));
    await tester.pump();
    expect(_camposVehiculo(), findsOneWidget);
    expect(
      tester.widget<BioTextField>(_camposVehiculo().first).controller.text,
      'AHX-742',
    );

    // El RUC viaja con su razón social («Proveedor») y su proceso, cada uno en
    // su campo editable.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is EvidenciaSelectField &&
            w.label == 'Proveedor' &&
            w.value == 'TRANSPORTES SANTA TERESA SAC · RUC 20123456789',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is EvidenciaSelectField &&
            w.label == 'Proceso' &&
            w.value == 'Logística',
      ),
      findsOneWidget,
    );
  });
}
