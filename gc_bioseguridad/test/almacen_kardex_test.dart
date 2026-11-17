import 'package:bioseguridad/services/almacen_kardex.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('entrega, devolución y lavado mueven Limpio y Lavadero', () {
    final base = [
      AlmacenLinea(
        insumoId: 1,
        codigo: 'IND-001',
        nombre: 'Overol',
        categoria: 'INDUMENTARIA',
        unidad: 'UND',
        almacen: 'LIMPIO',
        si: 20,
      ),
      AlmacenLinea(
        insumoId: 1,
        codigo: 'IND-001',
        nombre: 'Overol',
        categoria: 'INDUMENTARIA',
        unidad: 'UND',
        almacen: 'LAVADERO',
      ),
    ];
    final ops = [
      {'operacion': 'ENTREGA', 'insumo_id': 1, 'codigo': 'IND-001', 'cantidad': 1},
      {'operacion': 'DEVOLUCION', 'insumo_id': 1, 'codigo': 'IND-001', 'cantidad': 1},
      {'operacion': 'LAVADO', 'insumo_id': 1, 'codigo': 'IND-001', 'cantidad': 2},
    ];
    final out = aplicarAlmacen(base, ops);
    final limpio = out.firstWhere((l) => l.almacen == 'LIMPIO');
    final lavadero = out.firstWhere((l) => l.almacen == 'LAVADERO');
    expect(limpio.s, 1);
    expect(limpio.e, 2);
    expect(limpio.stock, 21);
    expect(lavadero.e, 1);
    expect(lavadero.s, 2);
    expect(lavadero.stock, -1);
  });
}
