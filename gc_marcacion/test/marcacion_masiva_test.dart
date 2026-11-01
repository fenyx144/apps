import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marcacion/utils/comida_horario.dart';
import 'package:marcacion/widgets/marcacion_masiva.dart';

void main() {
  test('el título del grupo no repite el código', () {
    expect(tituloGrupo('G1 · Proc. Automático', 'G1'), 'Proc. Automático');
    expect(tituloGrupo('G1', 'G1'), 'G1');
  });

  testWidgets('la casilla del grupo marca solo a quien falta', (tester) async {
    final sel = <String>{};
    final ana = _persona('12345678', 'Ana');
    final luis = _persona('87654321', 'Luis');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return MarcacionGrupoTarjeta(
                clave: 'G1',
                titulo: 'Proc. Automático',
                comidas: const [Comida.desayuno, Comida.almuerzo],
                comidaActiva: Comida.desayuno,
                permite: true,
                total: 2,
                filas: [
                  FilaMasiva(
                    persona: ana,
                    estado: MarcaPersonaEstado.pendiente,
                    nota: '',
                    seleccionada: sel.contains(ana.dni),
                  ),
                  FilaMasiva(
                    persona: luis,
                    estado: MarcaPersonaEstado.marcada,
                    nota: '06:10',
                    seleccionada: sel.contains(luis.dni),
                  ),
                ],
                onTogglePersona: (dni) {
                  setState(() {
                    if (!sel.add(dni)) sel.remove(dni);
                  });
                },
                onTogglePendientes: (dnis, marcar) {
                  setState(() {
                    if (marcar) {
                      sel.addAll(dnis);
                    } else {
                      sel.removeAll(dnis);
                    }
                  });
                },
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('grupo-G1')));
    await tester.pump();
    expect(sel, {'12345678'});

    await tester.tap(find.byKey(const ValueKey('persona-87654321')));
    await tester.pump();
    expect(sel, {'12345678', '87654321'});
  });
}

PersonalDespacho _persona(String dni, String nombre) {
  return PersonalDespacho(
    dni: dni,
    codigo: dni,
    nombre: nombre,
    cargo: '',
    grupo: 'G1',
    nomGrupo: 'Proc. Automático',
    fecha: '2026-10-23',
  );
}
