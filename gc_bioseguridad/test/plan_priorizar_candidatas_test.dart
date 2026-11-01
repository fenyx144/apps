import 'package:flutter_test/flutter_test.dart';
import 'package:bioseguridad/services/plan_visitas_service.dart';
import 'package:bioseguridad/services/storage_service.dart';
import 'package:bioseguridad/utils/plan_ingreso_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

PlanVisita _visita(int id, {String granja = '621'}) => PlanVisita(
      id: id,
      fecha: '2026-10-15',
      granja: granja,
      personas: const [],
    );

void main() {
  test('misma granja: id menor gana el empate', () {
    final ordenadas = priorizarVisitasCandidatas(
      [_visita(20), _visita(10)],
      granjaFormulario: '621',
      granjasTrabajo: const [],
    );
    expect(ordenadas.map((v) => v.id).toList(), [10, 20]);
  });

  test('granja del formulario antes que otra', () {
    final ordenadas = priorizarVisitasCandidatas(
      [_visita(1, granja: '100'), _visita(2, granja: '621')],
      granjaFormulario: '621',
      granjasTrabajo: const [],
    );
    expect(ordenadas.first.granja, '621');
  });

  test('visitasPlanPendientesParaDni excluye plan ya ingresado hoy', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    await storage.saveRecord({
      'reporte': 'ingreso',
      'fecha': '2026-10-15',
      'registro': {
        'plan_visita_id': '42',
        'dnis': [
          {'dni': '12345678', 'nombre': 'Test'},
        ],
      },
    });
    final v = PlanVisita(
      id: 42,
      fecha: '2026-10-15',
      granja: '621',
      personas: const [PlanPersona(dni: '12345678', nombre: 'Test')],
    );
    final pendientes = visitasPlanPendientesParaDni(
      storage,
      [v],
      '12345678',
      fechaYmd: '2026-10-15',
    );
    expect(pendientes, isEmpty);
    final c = planCoincidenciaSinDniConsumido(
      PlanCoincidencia(visita: v),
      storage,
      '12345678',
      fechaYmd: '2026-10-15',
    );
    expect(c.visita, isNull);
  });
}
