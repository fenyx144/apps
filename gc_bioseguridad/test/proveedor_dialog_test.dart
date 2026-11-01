import 'package:bioseguridad/widgets/proveedor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Map<String, dynamic>> _sinCcte(String q) async => {
      'success': true,
      'items': <Map<String, String>>[],
    };

List<ProveedorCcteItem> _sinLocal(String q) => const [];

void main() {
  testWidgets('acepta nombre sin RUC en un solo campo', (tester) async {
    ProveedorSeleccion? resultado;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                resultado = await showProveedorDialog(
                  context: context,
                  actual: ProveedorSeleccion.vacia,
                  buscarProveedorLocal: _sinLocal,
                  buscarProveedorCcte: _sinCcte,
                  consultarRuc: (_) async => {'success': false},
                );
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'TRANSPORTES SAC');
    await tester.pump();
    final aceptar = find.widgetWithText(ElevatedButton, 'Aceptar');
    expect(tester.widget<ElevatedButton>(aceptar).onPressed, isNotNull);
    await tester.tap(aceptar);
    await tester.pumpAndSettle();

    expect(resultado?.ruc, '');
    expect(resultado?.nombre, 'TRANSPORTES SAC');
  });

  testWidgets('elige proveedor del maestro ccte por nombre', (tester) async {
    ProveedorSeleccion? resultado;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                resultado = await showProveedorDialog(
                  context: context,
                  actual: ProveedorSeleccion.vacia,
                  buscarProveedorLocal: _sinLocal,
                  buscarProveedorCcte: (q) async => {
                    'success': true,
                    'items': [
                      {
                        'ruc': '20123456789',
                        'razonsocial': 'EMPRESA DEMO SAC',
                      },
                    ],
                  },
                  consultarRuc: (_) async => {'success': false},
                );
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'DEMO');
    await tester.tap(find.byTooltip('Buscar proveedor'));
    await tester.pumpAndSettle();

    expect(find.text('EMPRESA DEMO SAC'), findsOneWidget);
    expect(find.text('RUC 20123456789'), findsWidgets);

    await tester.tap(find.text('EMPRESA DEMO SAC'));
    await tester.pumpAndSettle();

    expect(resultado?.ruc, '20123456789');
    expect(resultado?.nombre, 'EMPRESA DEMO SAC');
  });

  testWidgets('RUC sin ccte usa Factiliza', (tester) async {
    ProveedorSeleccion? resultado;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                resultado = await showProveedorDialog(
                  context: context,
                  actual: ProveedorSeleccion.vacia,
                  buscarProveedorLocal: _sinLocal,
                  buscarProveedorCcte: _sinCcte,
                  consultarRuc: (ruc) async => {
                    'success': true,
                    'razonsocial': 'SUNAT SAC',
                    'ruc': ruc,
                  },
                );
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '20123456789');
    await tester.tap(find.byTooltip('Buscar proveedor'));
    await tester.pumpAndSettle();

    expect(find.text('SUNAT SAC'), findsOneWidget);

    await tester.tap(find.text('SUNAT SAC'));
    await tester.pumpAndSettle();

    expect(resultado?.ruc, '20123456789');
    expect(resultado?.nombre, 'SUNAT SAC');
  });
}
