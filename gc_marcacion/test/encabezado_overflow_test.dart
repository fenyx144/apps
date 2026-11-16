import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marcacion/widgets/marcacion_masiva.dart';
import 'package:marcacion/utils/comida_horario.dart';

void main() {
  for (final escala in [1.0, 1.3]) {
    testWidgets('encabezado sin overflow 360x640 x$escala', (t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: const Size(360, 640), textScaler: TextScaler.linear(escala)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                MarcacionVistaSwitch(vista: VistaMarcacion.una, onChanged: (_) {}),
                for (final c in Comida.values)
                  MarcacionContextoMasivo(comida: c, hora: '12:45', onComida: (_) {}),
                MarcacionBarraGuardar(personas: 12, detalle: 'Desayuno \u00b7 Inicio 12 \u00b7 Fin 10', color: Colors.green, onGuardar: () {}),
              ]),
            ),
          ),
        ),
      ));
      expect(t.takeException(), isNull);
    });
  }
}
