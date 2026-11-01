import 'package:flutter_test/flutter_test.dart';
import 'package:bioseguridad/services/estatus_sanitario_service.dart';

void main() {
  test('EstatusConsulta normaliza claves DNI a 8 dígitos', () {
    final c = EstatusConsulta.fromJson({
      'dnis': {
        '1234567': {
          'enRiesgo': true,
          'origenes': [
            {'granja': '621', 'estado': 'SOSPECHA', 'fechaIngreso': '2026-10-01'},
          ],
        },
      },
    });
    expect(c.dnis['01234567'], isNotNull);
    expect(c.dnis['01234567']!.enRiesgo, isTrue);
  });

  test('OrdenEdadConsulta parsea enRiesgo y origenes', () {
    final c = OrdenEdadConsulta.fromJson({
      'disponible': true,
      'edadGranja': 12,
      'dnis': {
        '12345678': {
          'enRiesgo': true,
          'origenes': [
            {
              'granja': '621',
              'nombreGranja': 'SANTA TERESA',
              'campania': '190',
              'edad': 45,
              'horaIngreso': '08:30:00',
            },
          ],
        },
      },
      'placas': {},
    });
    expect(c, isNotNull);
    expect(c!.disponible, isTrue);
    expect(c.edadGranja, 12);
    final d = c.dnis['12345678']!;
    expect(d.enRiesgo, isTrue);
    expect(d.avisoIngresoCorto('Esta persona'), 'Esta persona visitó una granja de mayor edad');
    expect(d.avisoIngreso('Esta persona'), contains('621'));
  });
}
