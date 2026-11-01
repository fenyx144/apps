import 'package:bioseguridad/services/estatus_sanitario_service.dart';
import 'package:bioseguridad/utils/constants.dart';
import 'package:bioseguridad/widgets/situacion_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

EstatusOrigen _origen({
  String granja = '621',
  String nombre = 'SANTA TERESA',
  String estado = 'SOSPECHA',
  String estadoLabel = 'Sospecha',
  String fechaIngreso = '2026-09-28',
  String fechaFin = '',
}) => EstatusOrigen(
  granja: granja,
  nombreGranja: nombre,
  campania: '193',
  estado: estado,
  estadoLabel: estadoLabel,
  fechaIngreso: fechaIngreso,
  fechaFin: fechaFin,
);

Future<void> _abrir(WidgetTester tester, EstatusDni estatus) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showSituacionDialog(
              context: ctx,
              estatus: estatus,
              sujeto: 'Juan Perez',
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  test('sinCampaniaEnNombre quita el tramo C= del nombre del servidor', () {
    expect(
      EstatusOrigen.sinCampaniaEnNombre('Granja C=190'),
      'Granja',
    );
    expect(
      EstatusOrigen.sinCampaniaEnNombre('SANTA TERESA C=193'),
      'SANTA TERESA',
    );
    expect(EstatusOrigen.sinCampaniaEnNombre('SANTA TERESA'), 'SANTA TERESA');
  });

  test('granjaTexto no repite campaña embebida en nombreGranja', () {
    const o = EstatusOrigen(
      granja: '621',
      nombreGranja: 'SANTA TERESA C=190',
    );
    expect(o.granjaTexto, '621 SANTA TERESA');
  });

  test('la frase dice el día, la granja y el estado', () {
    final estatus = EstatusDni(
      enRiesgo: true,
      origenes: [_origen(fechaFin: '2026-10-05')],
    );

    expect(
      estatus.situacionDe('Juan Perez', estatus.origenes.first),
      'Juan Perez ingresó el día 28/09/2026 a la granja 621 SANTA TERESA, '
      'la cual se encuentra en situación especial de Sospecha. '
      'Vigente hasta el 05/10/2026.',
    );
  });

  test('sin fecha de ingreso la frase sigue leyéndose', () {
    final estatus = EstatusDni(
      enRiesgo: true,
      origenes: [_origen(fechaIngreso: '')],
    );

    expect(
      estatus.situacionDe('Juan Perez', estatus.origenes.first),
      'Juan Perez ingresó a la granja 621 SANTA TERESA, la cual se encuentra '
      'en situación especial de Sospecha.',
    );
  });

  testWidgets('al tocar la etiqueta se abre el diálogo, no un aviso pasajero', (
    tester,
  ) async {
    await _abrir(
      tester,
      EstatusDni(enRiesgo: true, origenes: [_origen()]),
    );

    expect(find.text('Situación especial'), findsOneWidget);
    expect(
      find.textContaining(
        'Juan Perez ingresó el día 28/09/2026 a la granja 621 SANTA TERESA, '
        'la cual se encuentra en situación especial de',
        findRichText: true,
      ),
      findsOneWidget,
    );
    // El aviso pasajero ya no existe: se cierra con «Entendido».
    expect(find.text('Entendido'), findsOneWidget);

    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();
    expect(find.text('Situación especial'), findsNothing);
  });

  testWidgets('confirmado se pinta en rojo y sospecha en ámbar', (
    tester,
  ) async {
    final confirmado = EstatusDni(
      enRiesgo: true,
      origenes: [_origen(estado: 'CONFIRMADO', estadoLabel: 'Confirmado')],
    );
    expect(colorSituacion(confirmado), AppColors.errorDark);
    expect(
      colorSituacion(EstatusDni(enRiesgo: true, origenes: [_origen()])),
      AppColors.warning,
    );

    await _abrir(tester, confirmado);
    final icono = tester.widget<Icon>(find.byIcon(Icons.coronavirus_rounded));
    expect(icono.color, AppColors.errorDark);
  });

  testWidgets('cada granja de origen tiene su renglón', (tester) async {
    await _abrir(
      tester,
      EstatusDni(
        enRiesgo: true,
        origenes: [
          _origen(),
          _origen(
            granja: '623',
            nombre: 'GLORIA II',
            fechaIngreso: '2026-09-30',
          ),
        ],
      ),
    );

    expect(
      find.textContaining('a la granja 621 SANTA TERESA', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('a la granja 623 GLORIA II', findRichText: true),
      findsOneWidget,
    );
  });

  group('avisoIngreso (días desde el ingreso)', () {
    final ahora = DateTime(2026, 10, 6);

    EstatusDni conIngreso(String fecha) => EstatusDni(
      enRiesgo: true,
      origenes: [_origen(fechaIngreso: fecha)],
    );

    test('el ingreso del mismo día se lee «hoy»', () {
      expect(
        conIngreso('2026-10-06').avisoIngreso('Esta persona', ahora: ahora),
        'Esta persona ingresó hoy a una granja en situación especial',
      );
    });

    test('un día se lee en singular', () {
      expect(
        conIngreso('2026-10-05').avisoIngreso('Esta persona', ahora: ahora),
        'Esta persona ingresó hace 1 día a una granja en situación especial',
      );
    });

    test('varios días se leen en plural', () {
      expect(
        conIngreso('2026-10-01').avisoIngreso('Esta persona', ahora: ahora),
        'Esta persona ingresó hace 5 días a una granja en situación especial',
      );
    });

    test('sin fecha entendible se omite el «hace»', () {
      expect(
        conIngreso('').avisoIngreso('Esta persona', ahora: ahora),
        'Esta persona ingresó a una granja en situación especial',
      );
    });

    test('con varias granjas manda el ingreso más reciente', () {
      final estatus = EstatusDni(
        enRiesgo: true,
        origenes: [
          _origen(fechaIngreso: '2026-09-26'), // 10 días
          _origen(granja: '623', fechaIngreso: '2026-10-04'), // 2 días
        ],
      );
      expect(
        estatus.avisoIngreso('Esta persona', ahora: ahora),
        'Esta persona ingresó hace 2 días a una granja en situación especial',
      );
    });

    test('una fecha futura no muestra días negativos', () {
      expect(
        conIngreso('2026-10-20').avisoIngreso('Esta persona', ahora: ahora),
        'Esta persona ingresó hoy a una granja en situación especial',
      );
    });
  });
}
