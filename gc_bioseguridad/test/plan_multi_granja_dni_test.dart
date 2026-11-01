import 'package:bioseguridad/utils/plan_ingreso_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('planVisitaIdsEnFilaDni respeta visita elegida', () {
    expect(
      planVisitaIdsEnFilaDni(
        planificado: true,
        visitaPlanId: 10,
        visitasPlanIdsSeleccionados: {20},
      ),
      {20},
    );
  });

  test('planVisitaIdsEnFilaDni cae al id único del plan', () {
    expect(
      planVisitaIdsEnFilaDni(
        planificado: true,
        visitaPlanId: 42,
        visitasPlanIdsSeleccionados: {},
      ),
      {42},
    );
  });
}
