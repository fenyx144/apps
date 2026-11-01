import 'dart:convert';

import 'package:bioseguridad/services/plan_visitas_service.dart';
import 'package:bioseguridad/widgets/granja_campania_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PlanVisita aporta granja y campaña al registro', () {
    const visita = PlanVisita(
      id: 99,
      fecha: '2026-10-19',
      granja: '622',
      nombreGranja: 'GRANJA B',
      campania: '8',
      razonSocial: 'PROVEEDOR',
    );
    final g3 = visita.granja;
    final camp = GranjaCampaniaPicker.padCampania(visita.campania);
    expect(g3, '622');
    expect(camp, '008');
    expect(jsonEncode({'granja': g3, 'campania': camp}), contains('622'));
  });
}
