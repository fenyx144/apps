import 'package:bioseguridad/widgets/opcion_catalogo_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const List<Map<String, String>> _instalaciones = [
  {'codigo': '1', 'descripcion': 'Garita'},
  {'codigo': '2', 'descripcion': 'Tranquera'},
];

/// Guarda el resultado del diálogo: se llena solo cuando se cierra.
class _Resultado {
  OpcionCatalogo? valor;
}

Future<_Resultado> _abrir(
  WidgetTester tester, {
  required List<Map<String, String>> opciones,
  OpcionCatalogo actual = OpcionCatalogo.vacia,
  bool Function(String descripcion)? pideDetalle,
  String etiquetaOtro = 'Otros',
}) async {
  // Ventana alta: el diálogo tiene alto fijo y en la ventana por defecto del
  // test (600 px) el contenido se saldría.
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final resultado = _Resultado();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              resultado.valor = await showOpcionCatalogoDialog(
                context: ctx,
                title: 'Seleccionar',
                opciones: opciones,
                actual: actual,
                etiquetaOtro: etiquetaOtro,
                pideDetalle: pideDetalle,
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return resultado;
}

bool _puedeAceptar(WidgetTester tester) {
  final boton = tester.widget<ElevatedButton>(
    find.widgetWithText(ElevatedButton, 'Aceptar'),
  );
  return boton.onPressed != null;
}

void main() {
  testWidgets('agrega «Otros» cuando el catálogo no lo trae', (tester) async {
    await _abrir(tester, opciones: _instalaciones);

    expect(find.text('Garita'), findsOneWidget);
    expect(find.text('Tranquera'), findsOneWidget);
    expect(find.text('Otros'), findsOneWidget);
  });

  testWidgets('no duplica «Otros» si el catálogo ya lo envía', (tester) async {
    await _abrir(
      tester,
      opciones: const [
        {'codigo': '1', 'descripcion': 'Garita'},
        {'codigo': '9', 'descripcion': 'Otros'},
      ],
    );

    expect(find.text('Otros'), findsOneWidget);
  });

  testWidgets('una opción del catálogo se acepta y conserva su código', (
    tester,
  ) async {
    final resultado = await _abrir(tester, opciones: _instalaciones);
    expect(_puedeAceptar(tester), isFalse, reason: 'sin elegir no se acepta');

    await tester.tap(find.text('Tranquera'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();

    expect(resultado.valor!.valor, 'Tranquera');
    expect(resultado.valor!.codigo, '2');
    expect(resultado.valor!.detalle, '');
  });

  testWidgets('«Otros» pide el texto y no deja aceptar vacío', (tester) async {
    final resultado = await _abrir(tester, opciones: _instalaciones);

    await tester.tap(find.text('Otros'));
    await tester.pumpAndSettle();

    // El campo aparece y hasta que no se escribe no se puede aceptar.
    expect(find.text('Especifique'), findsOneWidget);
    expect(_puedeAceptar(tester), isFalse);

    await tester.enterText(find.byType(TextField), 'Bodega');
    await tester.pumpAndSettle();
    expect(_puedeAceptar(tester), isTrue);

    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();

    expect(resultado.valor!.valor, 'Bodega');
    // El texto escrito a mano no tiene código de catálogo.
    expect(resultado.valor!.codigo, '');
  });

  testWidgets('la opción que pide detalle compone la etiqueta', (tester) async {
    final resultado = await _abrir(
      tester,
      opciones: const [
        {'codigo': '1', 'descripcion': 'A la altura del galpón'},
        {'codigo': '2', 'descripcion': 'En el piso'},
      ],
      pideDetalle: (d) => d == 'A la altura del galpón',
    );

    await tester.tap(find.text('A la altura del galpón'));
    await tester.pumpAndSettle();

    // Pide el complemento y no deja aceptar sin él.
    expect(find.text('Detalle'), findsOneWidget);
    expect(_puedeAceptar(tester), isFalse);

    await tester.enterText(find.byType(TextField), 'Galpón 3');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();

    expect(resultado.valor!.valor, 'A la altura del galpón');
    expect(resultado.valor!.codigo, '1');
    expect(resultado.valor!.detalle, 'Galpón 3');
    expect(resultado.valor!.etiqueta, 'A la altura del galpón · Galpón 3');
  });

  testWidgets('las opciones sin detalle se aceptan directo', (tester) async {
    await _abrir(
      tester,
      opciones: const [
        {'codigo': '1', 'descripcion': 'A la altura del galpón'},
        {'codigo': '2', 'descripcion': 'En el piso'},
      ],
      pideDetalle: (d) => d == 'A la altura del galpón',
    );

    await tester.tap(find.text('En el piso'));
    await tester.pumpAndSettle();
    expect(find.text('Detalle'), findsNothing);
    expect(_puedeAceptar(tester), isTrue);
  });

  testWidgets('reabrir con un texto a mano preselecciona «Otros»', (
    tester,
  ) async {
    final resultado = await _abrir(
      tester,
      opciones: _instalaciones,
      actual: const OpcionCatalogo(valor: 'Bodega'),
    );

    final campo = tester.widget<TextField>(find.byType(TextField));
    expect(campo.controller!.text, 'Bodega');
    expect(_puedeAceptar(tester), isTrue);

    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();
    expect(resultado.valor!.valor, 'Bodega');
  });
}
