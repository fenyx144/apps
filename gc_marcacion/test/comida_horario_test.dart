import 'package:flutter_test/flutter_test.dart';
import 'package:marcacion/utils/comida_horario.dart';

void main() {
  test('tipos 4 a 9 cubren inicio y fin de las tres comidas', () {
    expect(TipoMarcacion.codigo(Comida.desayuno, MomentoComida.inicio), 4);
    expect(TipoMarcacion.codigo(Comida.desayuno, MomentoComida.fin), 5);
    expect(TipoMarcacion.codigo(Comida.almuerzo, MomentoComida.inicio), 6);
    expect(TipoMarcacion.codigo(Comida.almuerzo, MomentoComida.fin), 7);
    expect(TipoMarcacion.codigo(Comida.cena, MomentoComida.inicio), 8);
    expect(TipoMarcacion.codigo(Comida.cena, MomentoComida.fin), 9);
    expect(TipoMarcacion.validos, {4, 5, 6, 7, 8, 9});
  });

  test('tcencos concatena granja y campaña a 6 dígitos', () {
    expect(tcencosDe('621', '192'), '621192');
    expect(tcencosDe('62', '7'), '062007');
    expect(tcencosDe('', '192'), '');
  });

  test('carne tiene las tres comidas y automático no cena', () {
    final carne = horarioDe(grupo: 'G4', nomGrupo: 'Proc. Carne 02');
    final auto = horarioDe(grupo: '', nomGrupo: 'Proc. Automático');
    expect(carne?.comidas, [Comida.desayuno, Comida.almuerzo, Comida.cena]);
    expect(auto?.desayuno, isTrue);
    expect(auto?.cena, isFalse);
  });

  test('administrativo no tiene comidas', () {
    final h = horarioDe(grupo: 'G10', nomGrupo: 'Administrativo');
    expect(h, isNull);
  });

  test('la comida sugerida sigue la hora del día', () {
    expect(comidaSugerida(DateTime(2026, 10, 23, 7, 30)), Comida.desayuno);
    expect(comidaSugerida(DateTime(2026, 10, 23, 10)), Comida.almuerzo);
    expect(comidaSugerida(DateTime(2026, 10, 23, 17)), Comida.cena);
  });

  test('fin sin inicio no se puede marcar y la nota lo dice', () {
    expect(
      estadoMarcacion(
        momento: MomentoComida.fin,
        tieneInicio: false,
        tieneEstaMarca: false,
      ),
      MarcaPersonaEstado.sinInicio,
    );
    expect(
      estadoMarcacion(
        momento: MomentoComida.fin,
        tieneInicio: true,
        tieneEstaMarca: false,
      ),
      MarcaPersonaEstado.pendiente,
    );
    expect(
      estadoMarcacion(
        momento: MomentoComida.inicio,
        tieneInicio: false,
        tieneEstaMarca: true,
      ),
      MarcaPersonaEstado.marcada,
    );
    expect(
      notaMarcacion(
        estado: MarcaPersonaEstado.marcada,
        momento: MomentoComida.inicio,
        horaMarca: '06:10',
      ),
      '06:10',
    );
    expect(
      notaMarcacion(
        estado: MarcaPersonaEstado.sinInicio,
        momento: MomentoComida.fin,
      ),
      'Falta inicio',
    );
    expect(
      notaMarcacion(
        estado: MarcaPersonaEstado.pendiente,
        momento: MomentoComida.fin,
        horaInicio: '12:00',
      ),
      'Inicio 12:00',
    );
  });

  test('el ingreso masivo agrupa y deja al final quien no come', () {
    const remotos = [
      HorarioComida(
        sede: '',
        grupo: 'G1',
        nomGrupo: 'Auto',
        desayuno: false,
        almuerzo: true,
        cena: false,
      ),
      HorarioComida(
        sede: '',
        grupo: 'G2',
        nomGrupo: 'Brasa',
        desayuno: true,
        almuerzo: true,
        cena: false,
      ),
    ];
    final grupos = agruparMarcacion(
      personas: [
        _persona('10000002', 'G1', 'Auto', 'Ana'),
        _persona('10000001', 'G2', 'Brasa', 'Luis'),
        _persona('10000003', 'G2', 'Brasa', 'Bea'),
        _persona('10000004', 'ADM', 'Administrativo', 'Zoe'),
      ],
      comida: Comida.desayuno,
      remotos: remotos,
      origen: 'tabla',
    );
    expect(grupos.map((g) => g.clave), ['G2', 'G1']);
    expect(grupos.first.permite, isTrue);
    expect(grupos.first.personas.map((p) => p.nombre), ['Luis', 'Bea']);
    expect(grupos.first.comidas, [Comida.desayuno, Comida.almuerzo]);
    expect(grupos.last.permite, isFalse);
    expect(grupos.last.comidas, [Comida.almuerzo]);
  });

  test('un horario de servidor reemplaza la referencia', () {
    final remoto = [
      const HorarioComida(
        sede: '',
        grupo: 'G1',
        nomGrupo: 'Proc. Automático',
        desayuno: false,
        almuerzo: false,
        cena: true,
      ),
    ];
    final h = horarioDe(
      grupo: 'G1',
      nomGrupo: '',
      remotos: remoto,
      origen: 'dpollo_mae_horario_alimentacion',
    );
    expect(h?.cena, isTrue);
    expect(h?.desayuno, isFalse);
  });
}

PersonalDespacho _persona(String dni, String grupo, String nom, String nombre) {
  return PersonalDespacho(
    dni: dni,
    codigo: dni,
    nombre: nombre,
    cargo: '',
    grupo: grupo,
    nomGrupo: nom,
    fecha: '2026-10-23',
  );
}
