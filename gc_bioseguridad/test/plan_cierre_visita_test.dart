import 'package:bioseguridad/services/plan_visitas_service.dart';
import 'package:bioseguridad/utils/plan_ingreso_helper.dart';
import 'package:flutter_test/flutter_test.dart';

PlanVisita _visitaConDnis(List<String> dnis) => PlanVisita(
      id: 1,
      fecha: '2026-10-15',
      granja: '621',
      personas: [for (final d in dnis) PlanPersona(dni: d)],
    );

void main() {
  test('no cierra si falta alguien de la planificación por ingresar', () {
    final visita = _visitaConDnis(['11111111', '22222222', '33333333']);
    expect(
      planVisitaListaParaCerrar(
        visita: visita,
        dnisIngresadosHoy: {'11111111', '22222222'},
        quedaAlguienDentro: false,
      ),
      isFalse,
    );
  });

  test('cierra cuando todos ingresaron y nadie queda dentro', () {
    final visita = _visitaConDnis(['11111111', '22222222']);
    expect(
      planVisitaListaParaCerrar(
        visita: visita,
        dnisIngresadosHoy: {'11111111', '22222222'},
        quedaAlguienDentro: false,
      ),
      isTrue,
    );
  });

  test('no cierra si aún hay alguien dentro', () {
    final visita = _visitaConDnis(['11111111']);
    expect(
      planVisitaListaParaCerrar(
        visita: visita,
        dnisIngresadosHoy: {'11111111'},
        quedaAlguienDentro: true,
      ),
      isFalse,
    );
  });
}
