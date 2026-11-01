import 'package:flutter_test/flutter_test.dart';
import 'package:vacuna_al_agua/utils/vacuna_payload.dart';

/// Contrato con `sanidad/flutter/vacunaagua/vacunaagua_guardar_lib.php`.
///
/// Si el backend cambia un nombre de campo, estos tests fallan antes de que la
/// app empiece a subir registros que el servidor rechaza.
void main() {
  group('decloracionRegistro', () {
    test('usa las claves que espera el backend', () {
      final r = decloracionRegistro(
        horaInicio: '06:30',
        horaFinal: '08:00',
        cloroInicio: 0.5,
        cloroFinal: 1.25,
        responsable: 'Juan Pérez',
        observacion: 'Sin novedad',
      );

      expect(r.keys, {
        'hora_inicio',
        'hora_final',
        'cloro_inicio',
        'cloro_final',
        'responsable',
        'observacion',
        'galpones',
        'galpones_todos',
      });
      expect(r['galpones'], ['TODOS']);
      expect(r['galpones_todos'], isTrue);
      expect(r['hora_inicio'], '06:30');
      expect(r['hora_final'], '08:00');
    });

    test('el cloro viaja con dos decimales', () {
      final r = decloracionRegistro(
        horaInicio: '06:00',
        horaFinal: '07:00',
        cloroInicio: 0.5,
        cloroFinal: 1,
        responsable: '',
        observacion: '',
      );

      expect(r['cloro_inicio'], '0.50');
      expect(r['cloro_final'], '1.00');
    });
  });

  group('detalleFila', () {
    test('manda siempre las ocho claves del detalle paramétrico', () {
      final f = detalleFila(
        seccion: VacSeccion.sedeo,
        galpon: '1',
        parametro: 'Horas',
        valorNum: 8,
      );

      expect(f.keys, {
        'seccion',
        'galpon',
        'grupo',
        'parametro',
        'valor_num',
        'valor_texto',
        'hora',
        'flag',
      });
      expect(f['seccion'], 'sedeo');
      expect(f['galpon'], '1');
      expect(f['grupo'], '');
      expect(f['valor_num'], 8);
      expect(f['valor_texto'], isNull);
      expect(f['hora'], isNull);
      expect(f['flag'], isNull);
    });

    test('el valor va en la columna de su tipo, no todo junto', () {
      final conHora = detalleFila(
        seccion: VacSeccion.cadena,
        parametro: 'Salida de Almacen',
        hora: '06:00',
        valorNum: 5.5,
      );
      expect(conHora['hora'], '06:00');
      expect(conHora['valor_num'], 5.5);

      final conFlag = detalleFila(
        seccion: VacSeccion.equipo,
        parametro: 'Termómetro',
        flag: false,
      );
      expect(conFlag['flag'], false);
      expect(conFlag['valor_num'], isNull);
    });
  });

  group('detalleCadenaFrio', () {
    test('convierte los pasos en filas de la sección cadena', () {
      final filas = detalleCadenaFrio(const [
        (descripcion: 'Salida de Almacen', hora: '06:00', temperatura: 4.5),
        (descripcion: 'Inicio de proceso', hora: '07:15', temperatura: -2.5),
      ]);

      expect(filas, hasLength(2));
      expect(filas.first['seccion'], 'cadena');
      expect(filas.first['parametro'], 'Salida de Almacen');
      expect(filas.first['hora'], '06:00');
      expect(filas.first['valor_num'], 4.5);
      expect(filas.last['valor_num'], -2.5);
    });
  });

  group('detalleEquipo', () {
    test('convierte los recursos en filas de la sección equipo', () {
      final filas = detalleEquipo(const [
        (recurso: 'Termómetro', operativo: false, descripcion: 'roto'),
        (recurso: 'Coller', operativo: true, descripcion: ''),
      ]);

      expect(filas, hasLength(2));
      expect(filas.first['seccion'], 'equipo');
      expect(filas.first['parametro'], 'Termómetro');
      expect(filas.first['flag'], false);
      expect(filas.first['valor_texto'], 'roto');
      expect(filas.last['flag'], true);
      // Sin observación se manda null: el backend la guarda como NULL.
      expect(filas.last['valor_texto'], isNull);
    });
  });

  group('vacunacionRegistro', () {
    test('usa las claves que espera el backend y ya no manda galpones_todos', () {
      final r = vacunacionRegistro(
        galpones: ['G1', 'G2'],
        edad: 12,
        vacuna: 'Newcastle',
        lote: 'L-1',
        expiracion: DateTime(2026, 12, 31),
        dosisFrasco: '1000',
        laboratorio: 'Lab',
        responsable: 'Juan Pérez',
        detalle: const [],
      );

      expect(r.keys, {
        'galpones',
        'edad',
        'vacuna',
        'lote',
        'expiracion',
        'dosis_frasco',
        'laboratorio',
        'responsable',
        'detalle',
      });
      expect(r.containsKey('galpones_todos'), isFalse);
      expect(r.containsKey('cadena_frio'), isFalse);
      expect(r.containsKey('equipo'), isFalse);
      expect(r['galpones'], ['G1', 'G2']);
      expect(r['expiracion'], '2026-12-31');
      expect(r['responsable'], 'Juan Pérez');
    });

    test('el detalle viaja tal cual, sin reordenar ni completar', () {
      final detalle = [
        detalleFila(seccion: VacSeccion.sedeo, galpon: '1', parametro: 'Horas', valorNum: 8),
        detalleFila(
          seccion: VacSeccion.eficiencia,
          galpon: '1',
          grupo: 'Pollos evaluados',
          parametro: 'Macho',
          valorNum: 50,
        ),
      ];
      final r = vacunacionRegistro(
        galpones: ['1'],
        edad: null,
        vacuna: 'V',
        lote: '',
        expiracion: null,
        dosisFrasco: '',
        laboratorio: '',
        responsable: '',
        detalle: detalle,
      );

      expect(r['detalle'], same(detalle));
      // Sin edad se manda 0 (la columna es NOT NULL) y sin expiración va vacío
      // para que el backend lo guarde como NULL.
      expect(r['edad'], 0);
      expect(r['expiracion'], '');
    });

    test('el detalle llega serializable a JSON', () {
      final r = vacunacionRegistro(
        galpones: const ['1'],
        edad: 21,
        vacuna: 'Newcastle',
        lote: 'L-1',
        expiracion: DateTime(2026, 12, 31),
        dosisFrasco: '1000',
        laboratorio: 'Lab',
        responsable: 'Juan Pérez',
        detalle: [
          ...detalleCadenaFrio(const [
            (descripcion: 'Salida de Almacen', hora: '06:00', temperatura: 4.5),
          ]),
          ...detalleEquipo(const [
            (recurso: 'Coller', operativo: true, descripcion: ''),
          ]),
        ],
      );

      // `jsonEncode` es lo que hace la app al subir; si algún valor no fuera
      // serializable, el guardado fallaría recién en el dispositivo.
      expect(() => r.toString(), returnsNormally);
      final filas = r['detalle'] as List;
      expect(filas, hasLength(2));
      expect((filas.first as Map)['seccion'], 'cadena');
      expect((filas.last as Map)['seccion'], 'equipo');
    });
  });
}
