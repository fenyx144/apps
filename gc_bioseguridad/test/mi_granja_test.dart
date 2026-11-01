import 'dart:convert';

import 'package:bioseguridad/screens/mi_granja_screen.dart';
import 'package:bioseguridad/screens/register_cerco_screen.dart';
import 'package:bioseguridad/services/catalog_service.dart';
import 'package:bioseguridad/services/storage_service.dart';
import 'package:bioseguridad/utils/constants.dart';
import 'package:bioseguridad/widgets/evidencia_select_field.dart';
import 'package:bioseguridad/widgets/granja_campania_fields.dart';
import 'package:bioseguridad/widgets/granja_campania_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _g3 = '621';
const String _nombre = 'GJA. SANTA TERESA';
const String _campania = '007';

String get _hoy => GranjaCampaniaPicker.fechaHoyYmd();

/// Proyección mínima con una granja y su campaña vigente.
String _proyeccion() => jsonEncode({
  'fecha': _hoy,
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
    {'granja': _g3, 'nombre': _nombre},
  ],
});

/// Proyección con la granja pero sin campañas en el catálogo: nada que
/// premarcar.
String _proyeccionSinCampanias() => jsonEncode({
  'fecha': _hoy,
  'campanias_por_granja': {_g3: <dynamic>[]},
  'granjas': [
    {'granja': _g3, 'nombre': _nombre},
  ],
});

Future<StorageService> _storage(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  return StorageService(await SharedPreferences.getInstance());
}

/// Monta [pantalla] con los providers que usan los formularios.
Future<void> _montar(
  WidgetTester tester,
  Widget pantalla, {
  required Map<String, Object> prefs,
  required void Function(StorageService) onStorage,
}) async {
  // Ventana alta: el formulario entero queda montado sin depender del scroll.
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(prefs);
  final storage = StorageService(await SharedPreferences.getInstance());
  onStorage(storage);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => storage),
        ChangeNotifierProvider(create: (_) => CatalogService()),
      ],
      child: GetMaterialApp(home: pantalla),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('GranjaCampaniaPicker.seleccionDeGranja', () {
    test('resuelve granja, nombre y campaña vigente', () async {
      final s = await _storage({AppConstants.keyProyeccion: _proyeccion()});

      final sel = GranjaCampaniaPicker.seleccionDeGranja(
        proyeccion: s.getProyeccion(),
        // Con espacios: el código se normaliza a 3 dígitos.
        granja3: ' 621 ',
        fechaYmd: _hoy,
      );

      expect(sel, isNotNull);
      expect(sel!['granja3'], _g3);
      expect(sel['granjaNombre'], _nombre);
      expect(sel['campania'], _campania);
      expect(sel['campanias'], [_campania]);
    });

    test('una granja sin campañas en el catálogo no tiene selección', () async {
      final s = await _storage({
        AppConstants.keyProyeccion: _proyeccionSinCampanias(),
      });

      expect(
        GranjaCampaniaPicker.seleccionDeGranja(
          proyeccion: s.getProyeccion(),
          granja3: _g3,
          fechaYmd: _hoy,
        ),
        isNull,
      );
    });

    test('una granja fuera del catálogo no tiene selección', () async {
      final s = await _storage({AppConstants.keyProyeccion: _proyeccion()});

      expect(
        GranjaCampaniaPicker.seleccionDeGranja(
          proyeccion: s.getProyeccion(),
          granja3: '999',
          fechaYmd: _hoy,
        ),
        isNull,
      );
    });
  });

  group('granja de trabajo guardada', () {
    test('arranca vacía y se normaliza al guardarla', () async {
      final s = await _storage({});
      expect(s.getGranjaTrabajo(), '');
      expect(s.getGranjasTrabajo(), isEmpty);

      await s.saveGranjaTrabajo('  621 ');
      expect(s.getGranjaTrabajo(), _g3);
      expect(s.getGranjasTrabajo(), [_g3]);

      await s.addGranjaTrabajo('622');
      expect(s.getGranjasTrabajo(), [_g3, '622']);

      await s.saveGranjaTrabajo('');
      expect(s.getGranjaTrabajo(), '');
      expect(s.getGranjasTrabajo(), isEmpty);
    });

    test('sin granja guardada los formularios no premarcan nada', () async {
      final s = await _storage({AppConstants.keyProyeccion: _proyeccion()});
      expect(granjaDeTrabajoSeleccion(s, fechaYmd: _hoy), isNull);
    });

    test('con granja guardada devuelve granja y campaña sugerida', () async {
      final s = await _storage({
        AppConstants.keyProyeccion: _proyeccion(),
        AppConstants.keyGranjaTrabajo: _g3,
      });

      final sel = granjaDeTrabajoSeleccion(s, fechaYmd: _hoy);

      expect(sel, isNotNull);
      expect(sel!.granja, _g3);
      expect(sel.granjaNombre, _nombre);
      expect(sel.campania, _campania);
      expect(sel.campanias, [_campania]);
    });

    test('con varias granjas premarca la granja principal', () async {
      final s = await _storage({
        AppConstants.keyProyeccion: _proyeccion(),
      });
      await s.setGranjasTrabajo([_g3, '622']);
      final sel = granjaDeTrabajoSeleccion(s, fechaYmd: _hoy);
      expect(sel, isNotNull);
      expect(sel!.granja, _g3);
    });
  });

  group('formularios', () {
    testWidgets('el cerco arranca con la granja de trabajo marcada', (
      tester,
    ) async {
      await _montar(
        tester,
        const RegisterCercoScreen(),
        prefs: {
          AppConstants.keyProyeccion: _proyeccion(),
          AppConstants.keyGranjaTrabajo: _g3,
        },
        onStorage: (_) {},
      );

      expect(find.text('$_g3 $_nombre'), findsOneWidget);
      expect(find.text(_campania), findsOneWidget);
    });

    testWidgets('sin granja de trabajo el cerco arranca vacío', (tester) async {
      await _montar(
        tester,
        const RegisterCercoScreen(),
        prefs: {AppConstants.keyProyeccion: _proyeccion()},
        onStorage: (_) {},
      );

      expect(find.text('$_g3 $_nombre'), findsNothing);
      expect(find.text(_campania), findsNothing);
    });

    testWidgets('la campaña ocupa menos ancho que la granja', (tester) async {
      await _montar(
        tester,
        const RegisterCercoScreen(),
        prefs: {
          AppConstants.keyProyeccion: _proyeccion(),
          AppConstants.keyGranjaTrabajo: _g3,
        },
        onStorage: (_) {},
      );

      final campos = find.descendant(
        of: find.byType(GranjaCampaniaFields),
        matching: find.byType(EvidenciaSelectField),
      );
      expect(campos, findsNWidgets(2));

      // La campaña son tres dígitos, así que va con ancho fijo; la granja se
      // queda todo el resto, que es la que lleva el nombre largo.
      final campania = tester.getSize(campos.at(1)).width;
      expect(campania, 100);
      expect(tester.getSize(campos.at(0)).width, greaterThan(campania * 1.5));
    });
  });

  group('MiGranjaScreen', () {
    testWidgets('muestra la granja de trabajo guardada', (tester) async {
      await _montar(
        tester,
        const MiGranjaScreen(),
        prefs: {
          AppConstants.keyProyeccion: _proyeccion(),
          AppConstants.keyGranjaTrabajo: _g3,
        },
        onStorage: (_) {},
      );

      expect(find.text('$_g3 $_nombre'), findsOneWidget);
      expect(find.text('Agregar granja'), findsOneWidget);
    });

    testWidgets('sin granjas muestra aviso y botón agregar', (tester) async {
      await _montar(
        tester,
        const MiGranjaScreen(),
        prefs: {AppConstants.keyProyeccion: _proyeccion()},
        onStorage: (_) {},
      );

      expect(find.textContaining('Sin granjas configuradas'), findsOneWidget);
      expect(find.byTooltip('Quitar granja'), findsNothing);
    });

    testWidgets('quitar granja la borra del almacenamiento', (tester) async {
      late StorageService storage;
      await _montar(
        tester,
        const MiGranjaScreen(),
        prefs: {
          AppConstants.keyProyeccion: _proyeccion(),
          AppConstants.keyGranjaTrabajo: _g3,
        },
        onStorage: (s) => storage = s,
      );

      await tester.tap(find.byTooltip('Quitar granja'));
      await tester.pumpAndSettle();

      expect(storage.getGranjasTrabajo(), isEmpty);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  });
}
