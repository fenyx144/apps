import 'dart:convert';

import 'package:bioseguridad/screens/register_garita_screen.dart';
import 'package:bioseguridad/services/catalog_service.dart';
import 'package:bioseguridad/services/storage_service.dart';
import 'package:bioseguridad/utils/constants.dart';
import 'package:bioseguridad/widgets/evidencia_select_field.dart';
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

Future<void> _montar(
  WidgetTester tester, {
  required Map<String, Object> prefs,
  Widget screen = const RegisterGaritaScreen(),
}) async {
  // Ventana alta: el formulario entero queda montado sin depender del scroll.
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(prefs);
  final storage = StorageService(await SharedPreferences.getInstance());

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => storage),
        ChangeNotifierProvider(create: (_) => CatalogService()),
      ],
      child: GetMaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('el tipo de bioseguridad se muestra aunque no haya granja', (
    tester,
  ) async {
    // El tipo lo define la sección del menú, así que se ve desde el arranque:
    // antes se pedía elegirlo y parecía un dato más del formulario.
    await _montar(tester, prefs: {AppConstants.keyProyeccion: _proyeccion()});

    expect(find.text('Granja'), findsOneWidget);
    expect(find.text('Tipo de bioseguridad'), findsOneWidget);
    expect(find.text('Bioseguridad fisica'), findsOneWidget);
    expect(find.text('Instalación'), findsOneWidget);
  });

  testWidgets('el tipo de bioseguridad es de solo lectura', (tester) async {
    await _montar(
      tester,
      prefs: {AppConstants.keyProyeccion: _proyeccion()},
      screen: const RegisterGaritaScreen(
        bioseguridadInicial: 'Bioseguridad quimica',
        tipoInicial: BioTipos.quimica,
      ),
    );

    // El valor de la sección del menú, sin selector que lo cambie.
    expect(find.text('Bioseguridad quimica'), findsOneWidget);
    expect(find.byIcon(Icons.science_outlined), findsOneWidget);
    /*expect(
      find.textContaining('Lo define la sección del menú'),
      findsOneWidget,
    );*/

    final campo = tester.widget<EvidenciaSelectField>(
      find.widgetWithText(EvidenciaSelectField, 'Bioseguridad quimica'),
    );
    expect(campo.enabled, isFalse);
    expect(campo.onTap, isNull);
  });

  testWidgets('con la granja de trabajo el tipo ya está a la vista', (
    tester,
  ) async {
    await _montar(
      tester,
      prefs: {
        AppConstants.keyProyeccion: _proyeccion(),
        AppConstants.keyGranjaTrabajo: _g3,
      },
    );

    expect(find.text('$_g3 $_nombre'), findsOneWidget);
    expect(find.text('Tipo de bioseguridad'), findsOneWidget);
  });

  testWidgets('la instalación va después del tipo de bioseguridad', (
    tester,
  ) async {
    await _montar(
      tester,
      prefs: {
        AppConstants.keyProyeccion: _proyeccion(),
        AppConstants.keyGranjaTrabajo: _g3,
      },
    );

    // Se compara por posición y no por orden de hijos: es lo que ve el
    // vigilante al recorrer el formulario hacia abajo.
    final tipo = tester.getTopLeft(find.text('Tipo de bioseguridad')).dy;
    final instalacion = tester.getTopLeft(find.text('Instalación')).dy;

    expect(tipo, lessThan(instalacion));
  });

  testWidgets('el registro precarga anomalía, agente causal y acción', (
    tester,
  ) async {
    await _montar(
      tester,
      prefs: {
        AppConstants.keyProyeccion: _proyeccion(),
        AppConstants.keyGranjaTrabajo: _g3,
      },
    );

    expect(find.text('Anomalía'), findsWidgets);
    expect(find.text('Agente causal'), findsOneWidget);
    expect(find.text('Acción'), findsOneWidget);
    final textos = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.controller?.text ?? '')
        .toList();
    expect(textos, contains('Anomalía de bioseguridad física en Garita'));
    expect(textos, contains('Control de bioseguridad física en Garita'));
    expect(textos, contains('Corregir el hallazgo y dejar evidencia.'));
  });
}
