import 'package:bioseguridad/services/plan_visitas_service.dart';
import 'package:flutter_test/flutter_test.dart';

PlanDescarga _descarga() => PlanDescarga.fromJson({
  'desde': '2026-09-26',
  'hasta': '2026-10-02',
  'visitas': [
    {
      'id': 1,
      'fecha': '2026-09-26',
      'granja': '621',
      'campania': '193',
      'nombreGranja': 'GJA SANTA TERESA',
      'placa': 'AHX-742',
      'personas': [
        {'dni': '47614754', 'nombre': 'DIEGO RIVAS'},
        {'dni': '41234567', 'nombre': ''},
      ],
    },
    {
      'id': 2,
      'fecha': '2026-09-28',
      'granja': '623',
      'placa': '',
      'personas': [
        {'dni': '43456789', 'nombre': 'CARLOS'},
      ],
    },
  ],
});

void main() {
  test('la placa se compara sin guiones ni espacios, en la granja y fecha', () {
    final d = _descarga();
    final c = d.buscarPlaca('ahx 742', granja: '621', fechaYmd: '2026-09-26');
    expect(c.planificado, isTrue);
    expect(c.visita!.personas.map((p) => p.dni), ['47614754', '41234567']);

    // Otro día: no coincide.
    expect(
      d.buscarPlaca('AHX742', granja: '621', fechaYmd: '2026-09-27').planificado,
      isFalse,
    );
  });

  test('en otra granja se informa dónde sí figura', () {
    final c = _descarga().buscarPlaca(
      'AHX742',
      granja: '700',
      fechaYmd: '2026-09-26',
    );
    expect(c.planificado, isFalse);
    expect(c.otraGranja?.granja, '621');
  });

  test('sin granja elegida se busca en todas', () {
    final c = _descarga().buscarDni(
      '43456789',
      granja: '',
      fechaYmd: '2026-09-28',
    );
    expect(c.planificado, isTrue);
  });

  test('visitasPorDni filtra por granja cuando se indica', () {
    final d = PlanDescarga.fromJson({
      'desde': '2026-09-26',
      'hasta': '2026-09-26',
      'visitas': [
        {
          'id': 10,
          'fecha': '2026-09-26',
          'granja': '621',
          'personas': [
            {'dni': '11111111', 'nombre': 'A'},
          ],
        },
        {
          'id': 11,
          'fecha': '2026-09-26',
          'granja': '622',
          'personas': [
            {'dni': '11111111', 'nombre': 'A'},
          ],
        },
      ],
    });
    expect(
      d.visitasPorDni('11111111', granja: '621', fechaYmd: '2026-09-26').length,
      1,
    );
    expect(
      d.visitasPorDni('11111111', granja: '', fechaYmd: '2026-09-26').length,
      2,
    );
  });

  test('cubre solo el rango descargado', () {
    final d = _descarga();
    expect(d.cubre('2026-09-26'), isTrue);
    expect(d.cubre('2026-10-02'), isTrue);
    expect(d.cubre('2026-10-03'), isFalse);
    expect(PlanDescarga.vacia.cubre('2026-09-26'), isFalse);
  });

  test('se guarda y se lee igual (JSON)', () {
    final d = _descarga();
    final otra = PlanDescarga.fromJson(d.toJson());
    expect(otra.visitas.length, 2);
    expect(otra.visitas.first.personas.last.nombre, '');
    expect(otra.hasta, '2026-10-02');
  });

  test('el área o proveedor y el motivo llegan como los envía el servidor', () {
    // Tal cual el payload del endpoint: `areaproveedor` es el tipo ('AREA' o
    // 'PROVEEDOR') y `motivo` el valor elegido en la lista de la web.
    final visita = PlanVisita.fromJson({
      'id': 7,
      'fecha': '2026-09-30',
      'granja': '621',
      'campania': '193',
      'placa': 'ABC123',
      'areaproveedor': 'AREA',
      'motivo': 'Producción',
      'observacion': 'Sistemas',
      'personas': const [],
    });

    expect(visita.areaProveedor, 'AREA');
    expect(visita.areaProveedorValor, 'Producción');
    expect(visita.areaProveedorEtiqueta, 'Área · Producción');
    expect(visita.observacion, 'Sistemas');
  });

  test('un proveedor se rotula «Proveedor» aunque la web lo guarde en mayúsculas', () {
    final visita = PlanVisita.fromJson({
      'areaproveedor': 'PROVEEDOR',
      'motivo': 'Retiro de guano',
    });
    expect(visita.areaProveedorEtiqueta, 'Proveedor · Retiro de guano');
  });

  test('sin área registrada queda vacío, para mostrar «—» en vez de un rótulo solo', () {
    // Es lo que devuelve hoy el servidor para las visitas programadas antes de
    // que la web pidiera el dato: el rótulo no debe salir sin valor.
    final visita = PlanVisita.fromJson({
      'areaproveedor': '',
      'motivo': '',
      'observacion': 'Instalacion wifi',
    });
    expect(visita.areaProveedorEtiqueta, '');
    expect(visita.observacion, 'Instalacion wifi');
  });

  test('la descarga informa si el servidor trae el área o proveedor', () {
    final conColumnas = PlanDescarga.fromJson({
      'desde': '2026-09-30',
      'hasta': '2026-10-06',
      'conAreaproveedor': true,
      'visitas': [
        {'placa': 'ABC123', 'areaproveedor': 'AREA', 'motivo': 'Producción'},
        {'placa': 'XYZ123', 'areaproveedor': '', 'motivo': ''},
      ],
    });
    expect(conColumnas.areaProveedorSoportado, isTrue);
    expect(conColumnas.conAreaProveedor, 1);

    // Servidor sin las columnas: llegan vacías y hay que poder distinguirlo de
    // «esa visita no tiene área».
    final sinColumnas = PlanDescarga.fromJson({
      'desde': '2026-09-30',
      'hasta': '2026-10-06',
      'conAreaproveedor': false,
      'visitas': [
        {'placa': 'ABC123', 'areaproveedor': '', 'motivo': ''},
      ],
    });
    expect(sinColumnas.areaProveedorSoportado, isFalse);
    expect(sinColumnas.conAreaProveedor, 0);
  });

  test('un servidor viejo, que no manda la bandera, no se marca como incompleto', () {
    expect(_descarga().areaProveedorSoportado, isTrue);
    expect(PlanDescarga.vacia.areaProveedorSoportado, isTrue);
  });

  test('la bandera del servidor sobrevive al guardado en el equipo', () {
    final d = PlanDescarga.fromJson({
      'desde': '2026-09-30',
      'hasta': '2026-10-06',
      'conAreaproveedor': false,
      'visitas': const [],
    });
    expect(PlanDescarga.fromJson(d.toJson()).areaProveedorSoportado, isFalse);
  });

  test('código registrador y RUC del proveedor llegan y sobreviven al guardado',
      () {
    final visita = PlanVisita.fromJson({
      'placa': 'ABC123',
      'registradoPor': 'PRV001',
      'ruc': '20123456789',
      'personas': const [],
    });
    expect(visita.registradoPor, 'PRV001');
    expect(visita.ruc, '20123456789');
    final otra = PlanVisita.fromJson(visita.toJson());
    expect(otra.registradoPor, 'PRV001');
    expect(otra.ruc, '20123456789');

    expect(PlanVisita.fromJson(const {}).registradoPor, '');
    expect(PlanVisita.fromJson(const {}).ruc, '');
  });

  test('el detalle de vehículos viaja con su «ingresa» y sobrevive al guardado', () {
    final visita = PlanVisita.fromJson({
      'placa': 'AHX-742',
      'vehiculos': [
        {'placa': 'AHX-742', 'ingresa': 1},
        {'placa': 'BCD-123', 'ingresa': 0},
        {'placa': ''},
      ],
    });
    expect(visita.vehiculos.map((v) => v.placa), ['AHX-742', 'BCD-123']);
    expect(visita.vehiculos.map((v) => v.ingresa), [true, false]);
    expect(visita.placasEfectivas, ['AHX-742', 'BCD-123']);
    expect(visita.vehiculoDe('ahx-742')!.ingresa, isTrue);
    expect(visita.vehiculoDe('bcd123')!.ingresa, isFalse);

    // El guardado en el equipo no puede perder el flag: al reabrir la app el
    // «no ingresa» tiene que seguir ahí.
    final otra = PlanVisita.fromJson(visita.toJson());
    expect(otra.vehiculos.map((v) => v.placa), ['AHX-742', 'BCD-123']);
    expect(otra.vehiculos.map((v) => v.ingresa), [true, false]);
  });

  test('sin el detalle, las placas se toman como vehículos que ingresan', () {
    // Planificación vieja (o web con una sola placa): no viene `vehiculos`.
    final visita = PlanVisita.fromJson({
      'placas': ['AHX-742', 'BCD-123'],
    });
    expect(visita.vehiculosEfectivos.map((v) => v.placa), [
      'AHX-742',
      'BCD-123',
    ]);
    expect(visita.vehiculosEfectivos.every((v) => v.ingresa), isTrue);
  });

  test('«no», «0» y false son «no ingresa»; el resto, sí', () {
    for (final v in <dynamic>['no', 'NO', 0, '0', false, 'false', 'n']) {
      expect(PlanVehiculo.boolIngresa(v), isFalse, reason: '«$v»');
    }
    for (final v in <dynamic>['si', 'SI', 1, '1', true, null, '']) {
      expect(PlanVehiculo.boolIngresa(v), isTrue, reason: '«$v»');
    }
  });

  test('la razón social y el proceso del proveedor vuelven del guardado', () {
    final visita = PlanVisita.fromJson({
      'registradoPor': 'PRV001',
      'ruc': '20123456789',
      'razonsocial': 'TRANSPORTES SANTA TERESA SAC',
      'proceso': 'Logística',
    });
    expect(visita.razonSocial, 'TRANSPORTES SANTA TERESA SAC');
    expect(visita.proceso, 'Logística');

    final otra = PlanVisita.fromJson(visita.toJson());
    expect(otra.razonSocial, 'TRANSPORTES SANTA TERESA SAC');
    expect(otra.proceso, 'Logística');
  });
}
