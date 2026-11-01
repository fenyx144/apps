import 'package:bioseguridad/services/plan_visitas_service.dart';
import 'package:bioseguridad/utils/plan_ingreso_helper.dart';
import 'package:flutter_test/flutter_test.dart';

PlanVisita _visita({required int id, required String granja}) {
  return PlanVisita(
    id: id,
    granja: granja,
    nombreGranja: '',
    campania: '007',
    fecha: '2026-01-01',
    areaProveedor: '',
    areaProveedorValor: '',
    ruc: '',
    razonSocial: '',
    proceso: '',
    observacion: '',
    personas: const [],
    vehiculos: const [],
    galpones: const [],
  );
}

void main() {
  test('estatus no infiere granja sin formulario ni plan resuelto', () {
    final ctx = granjaCampaniaParaEstatusSanitario(
      granjaFormulario: '',
      campaniaFormulario: '',
      visitaFormularioGlobal: null,
      visitasResueltasEnFilas: const [],
    );
    expect(ctx.granja, isEmpty);
    expect(ctx.campania, isEmpty);
  });

  test('estatus usa visita planificada resuelta en fila', () {
    final v = _visita(id: 1, granja: '621');
    final ctx = granjaCampaniaParaEstatusSanitario(
      granjaFormulario: '',
      campaniaFormulario: '',
      visitaFormularioGlobal: null,
      visitasResueltasEnFilas: [v],
    );
    expect(ctx.granja, '621');
    expect(ctx.campania, '007');
  });

  test('planVisitaIdsEnFilaDni una sola visita elegida', () {
    expect(
      planVisitaIdsEnFilaDni(
        planificado: true,
        visitaPlanId: 10,
        visitasPlanIdsSeleccionados: {20},
      ),
      {20},
    );
  });
}
