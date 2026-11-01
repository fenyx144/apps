import 'package:bioseguridad/services/estatus_sanitario_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('estatusSanitarioDeDocumento encuentra por DNI normalizado', () {
    const aviso = EstatusDni(enRiesgo: true);
    final map = {'12345678': aviso};
    expect(estatusSanitarioDeDocumento(map, '12345678'), aviso);
    expect(estatusSanitarioDeDocumento(map, '12.345.678'), aviso);
  });
}
