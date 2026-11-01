import 'package:bioseguridad/services/nomina_proveedor_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final nomina = NominaProveedores.fromJson({
    'generado': '2026-10-23T08:00:00-05:00',
    'proveedores': {
      '20100000001': 'LIMPIEZA SAC',
      '20100000002': 'VACUNADORES EIRL',
    },
    'nomina': {
      '11111111': ['20100000001'],
      '22222222': ['20100000001'],
      '33333333': ['20100000002'],
    },
    'historial': {
      '44444444': ['20100000002'],
    },
  });

  test('propone primero el proveedor que agrupa más personas', () {
    final s = nomina.sugerir(['11111111', '22222222', '33333333']);
    expect(s.first.proveedor.ruc, '20100000001');
    expect(s.first.proveedor.nombre, 'LIMPIEZA SAC');
    expect(s.first.dnis, ['11111111', '22222222']);
    expect(s.first.desdeNomina, isTrue);
    expect(s[1].dnis, ['33333333']);
  });

  test('sin nómina usa el historial y lo marca como tal', () {
    final s = nomina.sugerir(['44444444']);
    expect(s.single.proveedor.ruc, '20100000002');
    expect(s.single.desdeNomina, isFalse);
  });

  test('DNI desconocido no propone nada', () {
    expect(nomina.sugerir(['99999999']), isEmpty);
    expect(nomina.fecha, '2026-10-23');
  });
}
