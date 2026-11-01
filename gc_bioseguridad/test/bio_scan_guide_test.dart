import 'package:bioseguridad/utils/constants.dart';
import 'package:bioseguridad/widgets/bio_scan_guide.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Monta la guía sola, como se ve sobre la cámara.
Future<void> _montar(WidgetTester tester, {String? aviso}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(400, 900);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: BioScanGuide(aviso: aviso),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Tamaño con el que se dibuja el recuadro.
Size _tamano(WidgetTester tester) {
  final caja = tester.getSize(find.byKey(BioScanGuide.claveFranja));
  return caja;
}

Color? _colorBorde(WidgetTester tester) {
  final contenedor = tester.widget<Container>(
    find.byKey(BioScanGuide.claveFranja),
  );
  return (contenedor.decoration as BoxDecoration?)?.border?.top.color;
}

void main() {
  group('BioScanGuide', () {
    testWidgets('dibuja un solo recuadro, con la forma del código de barras',
        (tester) async {
      await _montar(tester);

      expect(find.byKey(BioScanGuide.claveFranja), findsOneWidget);

      final franja = _tamano(tester);
      expect(franja.width, greaterThan(franja.height),
          reason: 'un código de barras es ancho y bajo');
    });

    testWidgets('no dibuja ningún segundo recuadro', (tester) async {
      await _montar(tester, aviso: 'Código leído sin DNI válido.');

      // El recuadro del QR ya no existe: sobre la cámara sólo va la franja.
      expect(
        find.byKey(const Key('bio-scan-guia-cuadrado')),
        findsNothing,
      );
      expect(find.byKey(BioScanGuide.claveFranja), findsOneWidget);
    });

    testWidgets('el aviso se muestra y tiñe la guía de advertencia',
        (tester) async {
      await _montar(tester, aviso: 'Código leído sin DNI válido. Intente de nuevo.');

      expect(
        find.text('Código leído sin DNI válido. Intente de nuevo.'),
        findsOneWidget,
      );
      expect(_colorBorde(tester), AppColors.warning);
    });

    testWidgets('sin aviso la guía va en el color normal', (tester) async {
      await _montar(tester);

      expect(_colorBorde(tester), AppColors.primaryLight);
    });
  });
}
