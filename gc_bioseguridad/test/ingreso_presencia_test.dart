import 'package:bioseguridad/services/ingreso_presencia_service.dart';
import 'package:bioseguridad/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('salida parcial deja al resto dentro del grupo', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    const fecha = '2026-10-09';
    const planId = '1001';

    await storage.saveRecord({
      'id': 'ing-1',
      'reporte': 'ingreso',
      'fecha': fecha,
      'granja': '621',
      'campania': '001',
      'turno': 'Dia',
      'registro': {
        'plan_visita_id': planId,
        'hora': '08:00',
        'proveedor': 'ACME',
        'motivo': 'Mantenimiento',
        'dnis': [
          {'dni': '11111111', 'nombre': 'Ana'},
          {'dni': '22222222', 'nombre': 'Luis'},
        ],
      },
      'created_at': '2026-10-09T08:00:00',
    });

    await storage.saveRecord({
      'id': 'sal-1',
      'reporte': 'salida',
      'fecha': fecha,
      'granja': '621',
      'campania': '001',
      'turno': 'Dia',
      'registro': {
        'movimiento': 'salida',
        'grupo_id': 'plan:$planId',
        'hora': '12:00',
        'dnis': [
          {'dni': '11111111', 'nombre': 'Ana'},
        ],
      },
      'created_at': '2026-10-09T12:00:00',
    });

    final grupos = IngresoPresenciaService.gruposDelDia(
      storage,
      fechaYmd: fecha,
      granja: '621',
    );
    expect(grupos, hasLength(1));
    expect(grupos.first.dentro.map((p) => p.dni), ['22222222']);
    expect(grupos.first.fuera.map((p) => p.dni), ['11111111']);
  });

  test('reingreso vuelve a poner dentro', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    const fecha = '2026-10-09';

    await storage.saveRecord({
      'id': 'ing-2',
      'reporte': 'ingreso',
      'fecha': fecha,
      'granja': '621',
      'campania': '001',
      'turno': 'Dia',
      'registro': {
        'hora': '09:00',
        'proveedor': 'X',
        'dnis': [
          {'dni': '33333333', 'nombre': 'Pepe'},
        ],
      },
      'created_at': '2026-10-09T09:00:00',
    });

    final gid = IngresoPresenciaService.grupoIdDeIngreso(storage.getMyRecords().first);

    await storage.saveRecord({
      'id': 'sal-2',
      'reporte': 'salida',
      'fecha': fecha,
      'granja': '621',
      'campania': '001',
      'turno': 'Dia',
      'registro': {
        'movimiento': 'salida',
        'grupo_id': gid,
        'hora': '10:00',
        'dnis': [
          {'dni': '33333333', 'nombre': 'Pepe'},
        ],
      },
      'created_at': '2026-10-09T10:00:00',
    });

    await storage.saveRecord({
      'id': 're-1',
      'reporte': 'salida',
      'fecha': fecha,
      'granja': '621',
      'campania': '001',
      'turno': 'Dia',
      'registro': {
        'movimiento': 'reingreso',
        'grupo_id': gid,
        'hora': '11:00',
        'dnis': [
          {'dni': '33333333', 'nombre': 'Pepe'},
        ],
      },
      'created_at': '2026-10-09T11:00:00',
    });

    final g = IngresoPresenciaService.gruposDelDia(
      storage,
      fechaYmd: fecha,
      granja: '621',
    ).single;
    expect(g.dentro.map((p) => p.dni), ['33333333']);
    expect(g.fuera, isEmpty);
  });

  test('salida parcial de vehículo deja el resto dentro', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    const fecha = '2026-10-09';

    await storage.saveRecord({
      'id': 'ing-v',
      'reporte': 'ingreso',
      'fecha': fecha,
      'granja': '621',
      'campania': '001',
      'turno': 'Dia',
      'registro': {
        'hora': '08:00',
        'proveedor': 'Transportes',
        'vehiculos': [
          {'placa': 'ABC-123', 'ingresa': true},
          {'placa': 'XYZ-999', 'ingresa': true},
        ],
      },
      'created_at': '2026-10-09T08:00:00',
    });

    final gid = IngresoPresenciaService.grupoIdDeIngreso(
      storage.getMyRecords().first,
    );

    await storage.saveRecord({
      'id': 'sal-v',
      'reporte': 'salida',
      'fecha': fecha,
      'granja': '621',
      'campania': '001',
      'turno': 'Dia',
      'registro': {
        'movimiento': 'salida',
        'grupo_id': gid,
        'hora': '14:00',
        'vehiculos': [
          {'placa': 'ABC-123'},
        ],
      },
      'created_at': '2026-10-09T14:00:00',
    });

    final g = IngresoPresenciaService.gruposDelDia(
      storage,
      fechaYmd: fecha,
      granja: '621',
    ).single;
    expect(
      g.vehiculosDentro.map((v) => v.etiqueta),
      ['XYZ-999'],
    );
    expect(
      g.vehiculosFuera.map((v) => v.etiqueta),
      ['ABC-123'],
    );
  });

  test('salida temporal permite regreso y definitiva no', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    const fecha = '2026-10-09';

    await storage.saveRecord({
      'id': 'ing-t',
      'reporte': 'ingreso',
      'fecha': fecha,
      'granja': '621',
      'campania': '001',
      'turno': 'Dia',
      'registro': {
        'hora': '08:00',
        'proveedor': 'Y',
        'dnis': [
          {'dni': '44444444', 'nombre': 'Temp'},
          {'dni': '55555555', 'nombre': 'Def'},
        ],
      },
      'created_at': '2026-10-09T08:00:00',
    });

    final gid = IngresoPresenciaService.grupoIdDeIngreso(
      storage.getMyRecords().first,
    );

    await storage.saveRecord({
      'id': 'sal-temp',
      'reporte': 'salida',
      'fecha': fecha,
      'granja': '621',
      'registro': {
        'movimiento': 'salida',
        'tipo_salida': 'temporal',
        'grupo_id': gid,
        'hora': '10:00',
        'dnis': [
          {'dni': '44444444', 'nombre': 'Temp'},
        ],
      },
      'created_at': '2026-10-09T10:00:00',
    });

    await storage.saveRecord({
      'id': 'sal-def',
      'reporte': 'salida',
      'fecha': fecha,
      'granja': '621',
      'registro': {
        'movimiento': 'salida',
        'tipo_salida': 'definitiva',
        'grupo_id': gid,
        'hora': '11:00',
        'dnis': [
          {'dni': '55555555', 'nombre': 'Def'},
        ],
      },
      'created_at': '2026-10-09T11:00:00',
    });

    var g = IngresoPresenciaService.gruposDelDia(
      storage,
      fechaYmd: fecha,
      granja: '621',
    ).single;
    expect(g.fueraTemporal.map((p) => p.dni), ['44444444']);
    expect(g.fueraDefinitiva.map((p) => p.dni), ['55555555']);

    await storage.saveRecord({
      'id': 'reg-t',
      'reporte': 'salida',
      'fecha': fecha,
      'granja': '621',
      'registro': {
        'movimiento': 'regreso',
        'grupo_id': gid,
        'hora': '12:00',
        'dnis': [
          {'dni': '44444444', 'nombre': 'Temp'},
        ],
      },
      'created_at': '2026-10-09T12:00:00',
    });

    g = IngresoPresenciaService.gruposDelDia(
      storage,
      fechaYmd: fecha,
      granja: '621',
    ).single;
    expect(g.dentro.map((p) => p.dni), ['44444444']);
    expect(g.fueraTemporal, isEmpty);
  });

  test('resolverPorDni encuentra dentro y fuera temporal', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    const fecha = '2026-10-09';

    await storage.saveRecord({
      'id': 'ing-r',
      'reporte': 'ingreso',
      'fecha': fecha,
      'granja': '621',
      'registro': {
        'hora': '08:00',
        'proveedor': 'Z',
        'dnis': [
          {'dni': '12345678', 'nombre': 'Dentro'},
        ],
      },
      'created_at': '2026-10-09T08:00:00',
    });

    final gid = IngresoPresenciaService.grupoIdDeIngreso(
      storage.getMyRecords().first,
    );

    await storage.saveRecord({
      'id': 'ing-r2',
      'reporte': 'ingreso',
      'fecha': fecha,
      'granja': '621',
      'registro': {
        'hora': '09:00',
        'proveedor': 'Z2',
        'dnis': [
          {'dni': '87654321', 'nombre': 'Fuera'},
        ],
      },
      'created_at': '2026-10-09T09:00:00',
    });

    final gid2 = IngresoPresenciaService.grupoIdDeIngreso(
      storage.getMyRecords()[1],
    );

    await storage.saveRecord({
      'id': 'sal-r',
      'reporte': 'salida',
      'fecha': fecha,
      'granja': '621',
      'registro': {
        'movimiento': 'salida',
        'tipo_salida': 'temporal',
        'grupo_id': gid2,
        'hora': '09:30',
        'dnis': [
          {'dni': '87654321', 'nombre': 'Fuera'},
        ],
      },
      'created_at': '2026-10-09T09:30:00',
    });

    final dentro = IngresoPresenciaService.resolverPorDni(
      storage,
      dni: '12345678',
      granja: '621',
    );
    expect(dentro.encontrado, isTrue);
    expect(dentro.ubicacion, PresenciaUbicacion.dentro);
    expect(dentro.persona?.nombre, 'Dentro');

    final fuera = IngresoPresenciaService.resolverPorDni(
      storage,
      dni: '87654321',
      granja: '621',
    );
    expect(fuera.encontrado, isTrue);
    expect(fuera.ubicacion, PresenciaUbicacion.fueraTemporal);

    final none = IngresoPresenciaService.resolverPorDni(
      storage,
      dni: '00000000',
      granja: '621',
    );
    expect(none.encontrado, isFalse);
    expect(none.ubicacion, PresenciaUbicacion.noEncontrado);
  });

  test('resolverPorDni respeta granjas de trabajo configuradas', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());

    await storage.saveRecord({
      'id': 'ing-a',
      'reporte': 'ingreso',
      'fecha': '2026-10-09',
      'granja': '621',
      'registro': {
        'hora': '08:00',
        'dnis': [
          {'dni': '70707070', 'nombre': 'A'},
        ],
      },
      'created_at': '2026-10-09T08:00:00',
    });
    await storage.saveRecord({
      'id': 'ing-b',
      'reporte': 'ingreso',
      'fecha': '2026-10-09',
      'granja': '622',
      'registro': {
        'hora': '09:00',
        'dnis': [
          {'dni': '80808080', 'nombre': 'B'},
        ],
      },
      'created_at': '2026-10-09T09:00:00',
    });

    final solo621 = IngresoPresenciaService.resolverPorDni(
      storage,
      dni: '70707070',
      granjas: ['621'],
    );
    expect(solo621.encontrado, isTrue);

    final fuera = IngresoPresenciaService.resolverPorDni(
      storage,
      dni: '80808080',
      granjas: ['621'],
    );
    expect(fuera.encontrado, isFalse);
  });

  test('resolverPorDni con duplicados elige el ingreso más reciente dentro', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());

    await storage.saveRecord({
      'id': 'ing-dup-1',
      'reporte': 'ingreso',
      'fecha': '2026-10-08',
      'granja': '621',
      'registro': {
        'hora': '08:00',
        'proveedor': 'Viejo',
        'dnis': [
          {'dni': '55555555', 'nombre': 'Antiguo'},
        ],
      },
      'created_at': '2026-10-08T08:00:00',
    });

    await storage.saveRecord({
      'id': 'ing-dup-2',
      'reporte': 'ingreso',
      'fecha': '2026-10-09',
      'granja': '621',
      'registro': {
        'hora': '10:00',
        'proveedor': 'Nuevo',
        'dnis': [
          {'dni': '55555555', 'nombre': 'Reciente'},
        ],
      },
      'created_at': '2026-10-09T10:00:00',
    });

    final c = IngresoPresenciaService.resolverPorDni(
      storage,
      dni: '55555555',
    );
    expect(c.encontrado, isTrue);
    expect(c.ambiguo, isFalse);
    expect(c.ubicacion, PresenciaUbicacion.dentro);
    expect(c.persona?.nombre, 'Reciente');
    expect(c.grupo?.proveedor, 'Nuevo');
  });

  test('resolverPorPlaca normaliza guiones', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());

    await storage.saveRecord({
      'id': 'ing-p',
      'reporte': 'ingreso',
      'fecha': '2026-10-09',
      'granja': '621',
      'registro': {
        'hora': '08:00',
        'proveedor': 'V',
        'vehiculos': [
          {'placa': 'AHX-742', 'ingresa': true},
        ],
      },
      'created_at': '2026-10-09T08:00:00',
    });

    final c = IngresoPresenciaService.resolverPorPlaca(
      storage,
      placa: 'ahx742',
      granja: '621',
    );
    expect(c.encontrado, isTrue);
    expect(c.ubicacion, PresenciaUbicacion.dentro);
    expect(c.vehiculo?.etiqueta, 'AHX-742');
  });

  test('gruposConPersonalDentro incluye ingreso de otro día', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());

    await storage.saveRecord({
      'id': 'ing-old',
      'reporte': 'ingreso',
      'fecha': '2026-10-01',
      'granja': '621',
      'registro': {
        'hora': '07:00',
        'proveedor': 'Antiguo',
        'dnis': [
          {'dni': '99999999', 'nombre': 'Sigue'},
        ],
      },
      'created_at': '2026-10-01T07:00:00',
    });

    final grupos = IngresoPresenciaService.gruposConPersonalDentro(
      storage,
      granja: '621',
    );
    expect(grupos, hasLength(1));
    expect(grupos.first.fechaIngreso, '2026-10-01');
    expect(grupos.first.dentro.single.dni, '99999999');
  });
}
