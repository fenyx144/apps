import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gc_mortalidad/models/motivo_mortalidad.dart';
import 'package:gc_mortalidad/models/mortality_detail.dart';
import 'package:gc_mortalidad/utils/mortality_design.dart';
import 'package:gc_mortalidad/widgets/inline_mortality_section.dart';
import 'package:gc_mortalidad/widgets/mortality_detail_dialog.dart';

void main() {
  final motivos = [
    MotivoMortalidad(codigo: 'C1', nombre: 'Causa natural', clase: 'MN'),
    MotivoMortalidad(codigo: 'C2', nombre: 'Causa eliminada', clase: 'ME'),
  ];

  Set<String> selectedOf(WidgetTester tester) {
    final buttons = tester.widgetList<SegmentedButton<String>>(
      find.byType(SegmentedButton<String>),
    );
    return buttons.expand((b) => b.selected).toSet();
  }

  testWidgets(
    'Inline (PI/Transporte/Produccion) muestra MN/ME sin selección por defecto',
    (tester) async {
      List<MortalityDetail> last = [];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: InlineMortalitySection(
                initialDetalles: const [],
                onChanged: (d) => last = d,
                tabAccentColor: Colors.green,
                showCausa: true,
                motivos: motivos,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Tipo muerte'), findsOneWidget);
      expect(find.text('M.N.'), findsWidgets);
      expect(find.text('M.E.'), findsWidgets);
      expect(selectedOf(tester), isEmpty);

      // Al tocar M.E. en Machos, el detalle emitido lleva ME (no MN sugerido).
      await tester.tap(find.text('M.E.').first);
      await tester.pump();
      expect(selectedOf(tester), {'ME'});
      await tester.enterText(find.byType(TextField).first, '2');
      await tester.pump();
      expect(last.isNotEmpty, isTrue);
      expect(last.first.tipoMuerte, 'ME');
    },
  );

  testWidgets(
    'Diálogo: al elegir causa con clase MN no queda MN seleccionado',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showMortalityDetailDialog(
                  context: ctx,
                  type: MortalityType.produccion,
                  motivos: motivos,
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Tipo muerte'), findsOneWidget);
      expect(selectedOf(tester), isEmpty);

      // Seleccionar la causa cuya clase es MN.
      await tester.tap(find.text('Seleccionar').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Causa natural'));
      await tester.pumpAndSettle();

      // Nada debe quedar seleccionado en MN/ME.
      expect(selectedOf(tester), isEmpty);
    },
  );
}
