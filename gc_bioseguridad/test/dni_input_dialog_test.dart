import 'package:bioseguridad/widgets/dni_input_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DNI a mano no rompe al abrir teclado', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: FilledButton(
                onPressed: () => DniInputDialog.show(context),
                child: const Text('Abrir'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '12345678');
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();
    expect(find.text('Abrir'), findsOneWidget);
  });
}
